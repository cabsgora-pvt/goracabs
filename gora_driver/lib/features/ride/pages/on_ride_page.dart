import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import '../../account/pages/face_single_capture_page.dart';
import '../bloc/ride_bloc.dart';
import '../logic/job_settlement.dart';
import '../widgets/nav_engine.dart';
import '../widgets/arrival_hint.dart';
import '../widgets/nav_map.dart';
import '../widgets/otp_dialog.dart';
import '../widgets/ride_shell.dart';
import '../widgets/ride_status_strip.dart';
import '../widgets/swipe_to_confirm.dart';
import '../widgets/waiting_timer.dart';
import '../../../utils/call_util.dart';
import 'invoice_page.dart';
import 'collect_fare_page.dart';
import 'rental_progress_page.dart';
import 'hire_progress_page.dart';
import 'delivery_progress_page.dart';

class OnRidePage extends StatelessWidget {
  static const route = '/on-ride';
  const OnRidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    // Every caller passes the ride. This used to fall back to a MOCK ride, so a
    // navigation mistake produced a working-looking screen whose Arrived and
    // Start buttons sent requests for a ride that does not exist.
    if (args is! RideRequestModel) return const _NoRide();
    // Keyed on the ride, so progress can never carry over from another one.
    return _OnRideView(key: ValueKey(args.id), ride: args);
  }
}

class _NoRide extends StatelessWidget {
  const _NoRide();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: blueAppBar('Ride'),
    body: const EmptyState(message: 'No active ride', icon: Icons.directions_car_outlined),
  );
}

class _OnRideView extends StatefulWidget {
  final RideRequestModel ride;
  const _OnRideView({super.key, required this.ride});
  @override
  State<_OnRideView> createState() => _OnRideViewState();
}

class _OnRideViewState extends State<_OnRideView> {
  // Round-trip leg and multi-stop progress. These were STATIC notifiers, shared
  // by every ride for the life of the app and reset only by a completed End
  // swipe — so a ride cancelled mid-trip handed its "returning" leg or its stop
  // number to the next ride. They also started from scratch when a ride was
  // reopened. Now they belong to this ride and start where the server says.
  late String _leg;          // 'enroute' | 'at_destination' | 'returning'
  late bool _nightHaltConfirmed;
  late int _stopIndex;
  late bool _waitingAtStop;
  bool _stepBusy = false;

  // ── Outstation tolls ──
  // Each toll the driver pays, as the server holds it. The rider pays them back
  // at the end of the trip, outside the fare.
  late List<TollEntry> _tolls;
  bool _tollBusy = false;
  // Frozen once the trip is being ended: the list is what the rider settles.
  late bool _tollsLocked;
  bool _ending = false;
  // The toll road the driver has just reached, waiting on "add the toll".
  NavStep? _tollPrompt;
  // Where the driver was when it was reached — where the toll is paid.
  LatLng? _tollPromptAt;
  // The latest GPS fix, for the location of a toll added by hand. Not state:
  // it changes every second and nothing on screen shows it.
  LatLng? _lastFix;
  // An add that did not reach the server, kept so a retry reuses its reference
  // and cannot be counted twice.
  ({int amount, String ref, String source, LatLng? at, NavStep? step})? _unsent;
  // "You have reached the pickup / drop", until the driver acts on it.
  final _arrivalHint = ArrivalHint();

  // ── Mid-ride face re-check ──
  // Polls while the trip is underway; paused while a check prompt is open on
  // screen, resumed once it's answered (if the ride survives it).
  Timer? _faceCheckTimer;
  bool _faceCheckShowing = false;

  RideRequestModel get r => widget.ride;
  bool get _isRound => r.service == 'outstation' && r.tripType == 'round_trip';
  bool get _tracksTolls => r.service == 'outstation';
  num get _tollTotal => TollEntry.total(_tolls);
  bool get _tollsEditable => _tracksTolls && !_tollsLocked && !_ending;

  @override
  void initState() {
    super.initState();
    final p = r.progress;
    _leg = p.outstationPhase.isEmpty ? 'enroute' : p.outstationPhase;
    _nightHaltConfirmed = p.nightHaltConfirmed;
    _stopIndex = p.currentStopIndex.clamp(0, r.stops.length);
    _waitingAtStop = p.waitingAtStop;
    _tolls = List.of(p.tolls);
    // Reopened after payment was requested: the server has frozen the list.
    _tollsLocked = p.awaitingPayment;
    // A resumed screen (app restart mid-trip) can already be 'ongoing' —
    // RideStartedState won't fire again to trigger this, so check directly.
    if (r.status == 'ongoing') _startFaceCheckTimer();
  }

  void _startFaceCheckTimer() {
    _faceCheckTimer?.cancel();
    _faceCheckTimer = Timer.periodic(const Duration(seconds: 45), (_) => _pollFaceCheck());
  }

  Future<void> _pollFaceCheck() async {
    if (_faceCheckShowing || !mounted) return;
    try {
      final res = await DriverApiService.checkFaceVerificationDue(r.id);
      if (res['required'] != true || !mounted) return;
      final attemptId = res['attemptId']?.toString();
      final deadlineSec = (res['deadlineSec'] as num?)?.toInt() ?? 60;
      if (attemptId == null) return;

      _faceCheckShowing = true;
      _faceCheckTimer?.cancel();
      final result = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(
        builder: (_) => FaceSingleCapturePage(
          title: 'Identity check',
          subtitle: 'Look straight at the camera to continue this trip',
          deadlineSec: deadlineSec,
          submit: (embedding, photoUrl) => DriverApiService.respondFaceVerification(attemptId, embedding, photoUrl),
        ),
      ));
      _faceCheckShowing = false;
      if (!mounted) return;

      if (result != null && result['matched'] == true) {
        _startFaceCheckTimer(); // passed — carry on, ride stays active
        return;
      }
      // Mismatch, timeout, or no response — the server has already cancelled
      // this ride and locked the driver out of going online again.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("This trip was ended — identity couldn't be verified. You'll need to re-verify before your next ride."),
        backgroundColor: AppColors.red,
        duration: Duration(seconds: 6),
      ));
      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (_) {/* network blip — next poll tries again */}
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => RideBloc()..currentRide = r,
      child: BlocListener<RideBloc, RideState>(
        listener: (context, state) {
          // Rental, hire and parcel continue on their own screens once started.
          if (state is RideStartedState && r.service == 'rental') {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RentalProgressPage(ride: r)));
            return;
          }
          if (state is RideStartedState && r.service == 'hire_driver') {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HireProgressPage(ride: r)));
            return;
          }
          if (state is RideStartedState && r.service == 'delivery') {
            // The pickup OTP is the sender's handover code: the parcel is in
            // hand, so the page marks it collected and heads for the receiver.
            Navigator.pushReplacement(context, MaterialPageRoute(
                builder: (_) => DeliveryProgressPage(ride: r, collectOnOpen: true)));
            return;
          }
          // Taxi/outstation stay on this page once started — the other three
          // services already left via the branches above.
          if (state is RideStartedState) _startFaceCheckTimer();
          // Done what the nudge asked: it has nothing more to say.
          if (state is ArrivedAtPickupState) _arrivalHint.dismiss();
          if (state is ArriveFailedState) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(state.message), backgroundColor: AppColors.red));
            return;
          }
          if (state is RideEndedState) {
            Navigator.pushReplacementNamed(
              context, InvoicePage.route,
              arguments: RideCompletionArgs(
                state.ride,
                driverEarning: state.driverEarning,
                adminProfit: state.adminProfit,
                tollCollected: _tollTotal,
              ),
            );
          }
          if (state is OtpErrorState) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid OTP')));
          }
        },
        child: BlocBuilder<RideBloc, RideState>(
          builder: (context, state) {
            final bloc = context.read<RideBloc>();
            // A resumed screen starts its BLoC at RideInitial, so deriving these from
            // BLoC state alone put an already-arrived — or even already-started —
            // ride back at "arrive". The server status can only move forward, so
            // OR-ing it in is safe: it can make these true, never false.
            final serverArrived = r.status == 'arrived' || r.status == 'ongoing';
            final arrived = serverArrived || state is ArrivedAtPickupState || state is RideStartedState || state is RideEndedState || state is OtpErrorState;
            final started = r.status == 'ongoing' || state is RideStartedState;

            return RideShell(
              rideId: r.id,
              vehicleType: r.rideType,
              driving: started,
              leg: _currentLeg(started),
              fallbackPolyline: r.routePolyline,
              // Geofence hit — prompt the action rather than performing it, so
              // the driver stays in control of ride state.
              onArrived: () {
                if (!context.mounted) return;
                _arrivalHint.show(context, started
                    ? 'You have reached the drop — end the ride when the rider is out'
                    : 'You have reached the pickup — swipe Arrived');
              },
              // Asks as each toll road is reached on an outstation trip.
              onTollRoad: _tracksTolls && started ? _onTollRoad : null,
              onPosition: (p) => _lastFix = p,
              phase: _phaseChip(started: started, arrived: arrived),
              status: RideStatusStrip(
                phase: started ? 'On trip' : (arrived ? 'At pickup' : 'To pickup'),
                metrics: [
                  RideStatusMetric(Icons.route, '${r.distanceKm.toStringAsFixed(1)} km'),
                  if (r.durationMin > 0) RideStatusMetric(Icons.schedule, '${r.durationMin} min'),
                  // Once there is a toll pill, the fare gives way to it: the
                  // fare is on the rider card just below, and with both the
                  // time was cut to a bare "310" on a common phone.
                  if (_tollTotal <= 0) RideStatusMetric(Icons.payments_outlined, r.fare),
                ],
                // Tolls are owed on top of the fare, so they take the pill that
                // never scrolls away — as a fourth metric they sat past the
                // edge of a common phone.
                accruing: _tollTotal,
                accruingLabel: 'toll',
              ),
              contact: RideContact(name: r.userName, phone: r.userPhone, role: 'Rider', picUrl: r.userProfilePicUrl),
              chatWith: r.userName,
              contactTrailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(8)),
                child: Text(r.fare, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 14)),
              ),
              details: _details(started),
              actions: _actions(context, state, bloc, arrived: arrived, started: started),
            );
          },
        ),
      ),
    );
  }

  /// Heading to the rider until the trip starts, then to the next stop, then to
  /// the drop — and on a round trip, back to the start once returning.
  NavLeg _currentLeg(bool started) {
    if (!started) {
      return NavLeg(label: 'Pickup', destLat: r.pickupLat, destLng: r.pickupLng, destAddress: r.pickupAddress);
    }
    if (r.stops.isNotEmpty && _stopIndex < r.stops.length) {
      final s = r.stops[_stopIndex];
      return NavLeg(
        label: 'Stop ${_stopIndex + 1}',
        destLat: (s['lat'] as num?)?.toDouble(),
        destLng: (s['lng'] as num?)?.toDouble(),
        destAddress: (s['address'] ?? '').toString(),
      );
    }
    if (_isRound && _leg == 'returning') {
      // Navigation kept pointing at the destination for the whole drive home.
      return NavLeg(label: 'Start point', destLat: r.pickupLat, destLng: r.pickupLng, destAddress: r.pickupAddress);
    }
    return NavLeg(label: 'Drop', destLat: r.dropLat, destLng: r.dropLng, destAddress: r.dropAddress);
  }

  String _phaseChip({required bool started, required bool arrived}) {
    if (!started) return arrived ? 'AT PICKUP' : 'TO PICKUP';
    if (_isRound && _leg == 'at_destination') return 'AT DESTINATION';
    if (_isRound && _leg == 'returning') return 'RETURN TRIP';
    if (r.stops.isNotEmpty && _stopIndex < r.stops.length) {
      return _waitingAtStop ? 'WAITING AT STOP ${_stopIndex + 1}' : 'TO STOP ${_stopIndex + 1}';
    }
    return 'ON TRIP';
  }

  List<Widget> _details(bool started) => [
    if (started && r.stops.isNotEmpty && _stopIndex < r.stops.length) _stopInfo(),
    if (r.service == 'outstation' && (r.cityFrom.isNotEmpty || r.cityTo.isNotEmpty))
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          const Icon(Icons.map_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('${r.cityFrom} ${_isRound ? '⇄' : '→'} ${r.cityTo}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark))),
          Text(_isRound ? 'ROUND TRIP' : 'ONE WAY',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primary)),
        ]),
      ),
    if (_tracksTolls && started) _tollPanel(),
    _locationRow(Icons.radio_button_checked, AppColors.green, started ? 'From' : 'Pickup', r.pickupAddress),
    for (final (i, s) in r.stops.indexed)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _locationRow(
          i < _stopIndex ? Icons.check_circle : Icons.trip_origin,
          i < _stopIndex ? AppColors.green : AppColors.orange,
          'Stop ${i + 1}${i < _stopIndex ? ' · done' : ''}',
          (s['address'] ?? '').toString(),
        ),
      ),
    const SizedBox(height: 8),
    _locationRow(Icons.location_on, AppColors.red, 'Drop', r.dropAddress),
  ];

  List<Widget> _actions(BuildContext context, RideState state, RideBloc bloc,
      {required bool arrived, required bool started}) {
    if (state is RideLoading) return const [AppLoader()];
    return [
      // Swipe, not tap: a misfired "arrived" tells the rider their driver is
      // outside when they are not, and starts the wait. Labels carry no emoji —
      // TalkBack reads them aloud by name.
      if (!arrived)
        SwipeToConfirm(
          label: 'Swipe when you have arrived',
          icon: Icons.place_rounded,
          onConfirm: () async => bloc.add(ArrivedEvent()),
        ),
      if (arrived && !started) ...[
        // Keyed on the ride so it keeps counting through state changes while
        // waiting (arrived -> wrong OTP -> retry) instead of restarting at zero.
        Padding(
          key: ValueKey('wait-${r.id}'),
          padding: const EdgeInsets.only(bottom: 10),
          child: WaitingTimer(
            // Fresh arrival: 0. Resumed mid-wait: the server's count.
            seedSeconds: state is ArrivedAtPickupState ? state.waitingSec : (r.waitingSec ?? 0),
            onCallRider: () => dialPhone(r.userPhone, context: context),
          ),
        ),
        PrimaryButton(label: 'Enter OTP to start ride', onTap: () => _showOtpDialog(context, bloc)),
      ],
      if (started && r.stops.isNotEmpty && _stopIndex < r.stops.length) ...[
        _stopControl(),
        const SizedBox(height: 10),
      ],
      if (started && _tollPrompt != null && _tollsEditable) ...[
        _tollPromptCard(),
        const SizedBox(height: 10),
      ],
      if (started) ..._tripEnd(context, bloc),
    ];
  }

  /// Which stop is next, and whether the rider is there now. Sits with the
  /// details; only its control is pinned with the actions.
  Widget _stopInfo() {
    final stopName = (r.stops[_stopIndex]['address'] ?? 'Stop ${_stopIndex + 1}').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.08), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orange.withOpacity(0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Stop ${_stopIndex + 1} of ${r.stops.length}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.orange, fontSize: 12)),
        Text(stopName, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
        if (_waitingAtStop)
          Padding(padding: const EdgeInsets.only(top: 4),
            child: Text('Waiting while the rider is at the stop', style: TextStyle(fontSize: 12, color: AppColors.textGrey))),
      ]),
    );
  }

  Widget _stopControl() => !_waitingAtStop
      // Reaching a stop starts the rider's billable waiting time.
      ? SwipeToConfirm(
          label: 'Swipe at stop ${_stopIndex + 1}',
          icon: Icons.flag_circle_outlined,
          enabled: !_stepBusy,
          onConfirm: () => _stopAction('reached'),
        )
      : PrimaryButton(
          label: _stopIndex + 1 < r.stops.length ? 'Continue to stop ${_stopIndex + 2}' : 'Continue to drop',
          loading: _stepBusy,
          onTap: () => _stopAction('resume'),
        );

  /// Advances a multi-stop ride. The screen used to move on whether or not the
  /// server accepted it, so its stop number and the server's billing of waiting
  /// time could drift apart. It now takes the server's answer.
  Future<void> _stopAction(String action) async {
    setState(() => _stepBusy = true);
    Map<String, dynamic> res;
    try {
      res = await DriverApiService.stopAction(r.id, {'action': action, 'index': _stopIndex});
    } catch (_) {
      res = const {'error': 'No connection'};
    }
    if (!mounted) return;
    setState(() {
      _stepBusy = false;
      if (res['error'] == null) {
        _stopIndex = ((res['currentStopIndex'] as num?)?.toInt() ?? (action == 'resume' ? _stopIndex + 1 : _stopIndex))
            .clamp(0, r.stops.length);
        _waitingAtStop = res['isWaitingAtStop'] == true;
      }
    });
    if (res['error'] != null) _fail('Could not update the stop', res['error']);
  }

  Future<void> _setLeg(String leg) async {
    setState(() => _stepBusy = true);
    final res = await DriverApiService.updatePhase(r.id, {'phase': leg});
    if (!mounted) return;
    setState(() {
      _stepBusy = false;
      if (res['error'] == null) _leg = leg;
    });
    if (res['error'] != null) _fail('Could not update the trip', res['error']);
  }

  Future<void> _confirmNightHalt() async {
    setState(() => _stepBusy = true);
    final res = await DriverApiService.updatePhase(r.id, {'confirmNightHalt': true});
    if (!mounted) return;
    setState(() {
      _stepBusy = false;
      if (res['error'] == null) _nightHaltConfirmed = true;
    });
    if (res['error'] != null) {
      _fail('Could not confirm the night halt', res['error']);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Night halt confirmed'), backgroundColor: AppColors.green));
    }
  }

  // ── Tolls ──────────────────────────────────────────────────────────────────

  void _onTollRoad(NavStep step) {
    if (!mounted || !_tollsEditable) return;
    setState(() { _tollPrompt = step; _tollPromptAt = _lastFix ?? step.start; });
  }

  /// Every toll entered this trip, and the way to add or remove one.
  Widget _tollPanel() => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
    decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(children: [
          const Icon(Icons.toll, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('Tolls', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textDark))),
          Text('₹${_tollTotal.round()}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.textDark)),
        ]),
      ),
      if (_tolls.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 8),
          child: Text('Add each toll you pay. The rider pays them back at the end of the trip.',
            style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
        ),
      for (final (i, t) in _tolls.indexed)
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Toll ${i + 1}${t.at != null ? ' · ${_clock(t.at!)}' : ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppColors.textDark)),
            if (t.place.isNotEmpty)
              Text(t.place, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: AppColors.textGrey)),
            if (t.reported)
              const Text('Reported by the rider — support will review it',
                style: TextStyle(fontSize: 11.5, color: AppColors.red, fontWeight: FontWeight.w700)),
          ])),
          Text('₹${t.amount.round()}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          if (_tollsEditable)
            IconButton(
              tooltip: 'Remove toll ${i + 1}',
              visualDensity: VisualDensity.compact,
              onPressed: _tollBusy ? null : () => _removeToll(t, i + 1),
              icon: Icon(Icons.close, size: 18, color: AppColors.textGrey),
            )
          else
            const SizedBox(width: 8, height: 36),
        ]),
      if (_tollsEditable)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _tollBusy ? null : () => _addToll(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add toll'),
          ),
        ),
    ]),
  );

  /// Pinned with the actions, so it is seen without scrolling. The question on
  /// one line and the answers under it: side by side, the question broke into
  /// three short lines on a common phone.
  Widget _tollPromptCard() => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
    decoration: BoxDecoration(
      color: AppColors.orange.withOpacity(0.10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.orange.withOpacity(0.45)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.toll, color: AppColors.orange),
        const SizedBox(width: 10),
        Expanded(child: Text('Toll road. Paying a toll here? Add it.',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textDark))),
      ]),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(
          onPressed: () => setState(() => _tollPrompt = null),
          child: const Text('No toll'),
        ),
        const SizedBox(width: 6),
        ElevatedButton(
          onPressed: _tollBusy ? null : () => _addToll(fromPrompt: _tollPrompt),
          // Sized for the card, not the theme's full-width 56pt primary button.
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), minimumSize: const Size(0, 40)),
          child: const Text('Add toll'),
        ),
      ]),
    ]),
  );

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _addToll({NavStep? fromPrompt}) async {
    final amount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _TollAmountSheet(),
    );
    if (amount == null || !mounted) return;
    await _sendToll((
      amount: amount,
      ref: '${r.id}-${DateTime.now().microsecondsSinceEpoch}',
      source: fromPrompt != null ? 'prompt' : 'manual',
      // Where it was paid: where the toll road was reached, or — added by
      // hand — where the driver is now. The server turns it into an address.
      at: fromPrompt != null ? _tollPromptAt : _lastFix,
      step: fromPrompt,
    ));
  }

  Future<void> _sendToll(({int amount, String ref, String source, LatLng? at, NavStep? step}) toll) async {
    setState(() => _tollBusy = true);
    Map<String, dynamic> res;
    var offline = false;
    try {
      res = await DriverApiService.tollAction(r.id, {
        'action': 'add',
        'amount': toll.amount,
        'clientRef': toll.ref,
        'source': toll.source,
        if (toll.at != null) 'lat': toll.at!.latitude,
        if (toll.at != null) 'lng': toll.at!.longitude,
      });
    } catch (_) {
      offline = true;
      res = const {'error': 'No connection'};
    }
    if (!mounted) return;
    setState(() {
      _tollBusy = false;
      if (res['error'] == null) {
        _tolls = TollEntry.listFrom(res['tolls']);
        _unsent = null;
        if (toll.step != null && identical(_tollPrompt, toll.step)) _tollPrompt = null;
      } else if (offline) {
        _unsent = toll;
      }
    });
    if (res['error'] == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(offline
          ? 'Toll of ₹${toll.amount} not saved — no connection'
          : 'Could not add the toll: ${res['error']}'),
      backgroundColor: AppColors.red,
      duration: const Duration(seconds: 8),
      // An unsaved toll must not slip away unseen — the driver would not be
      // repaid — so Retry stays until tapped, or until the trip is ended.
      persist: offline,
      // Same reference, so if the first attempt did reach the server after
      // all, the retry is recognised instead of adding the toll twice.
      action: offline
          ? SnackBarAction(label: 'Retry', textColor: Colors.white,
              onPressed: () { final u = _unsent; if (mounted && u != null) _sendToll(u); })
          : null,
    ));
  }

  Future<void> _removeToll(TollEntry t, int number) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('Remove toll $number?'),
        content: Text('₹${t.amount.round()} will be taken off the rider\'s bill.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _tollBusy = true);
    Map<String, dynamic> res;
    try {
      res = await DriverApiService.tollAction(r.id, {'action': 'remove', 'tollId': t.id});
    } catch (_) {
      res = const {'error': 'No connection'};
    }
    if (!mounted) return;
    setState(() {
      _tollBusy = false;
      if (res['error'] == null) _tolls = TollEntry.listFrom(res['tolls']);
    });
    if (res['error'] != null) _fail('Could not remove the toll', res['error']);
  }

  void _fail(String what, dynamic error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$what: $error'), backgroundColor: AppColors.red));
  }

  List<Widget> _tripEnd(BuildContext context, RideBloc bloc) {
    // Outstation round trip: arrive at the destination, optional night halt,
    // then the return leg, before the ride can end.
    if (_isRound && _leg == 'enroute') {
      return [
        SwipeToConfirm(
          label: 'Swipe at your destination',
          icon: Icons.flag_rounded,
          enabled: !_stepBusy,
          onConfirm: () => _setLeg('at_destination'),
        ),
      ];
    }
    if (_isRound && _leg == 'at_destination') {
      return [
        OutlinedButton.icon(
          onPressed: (_nightHaltConfirmed || _stepBusy) ? null : _confirmNightHalt,
          icon: Icon(Icons.bedtime, color: _nightHaltConfirmed ? Colors.grey : AppColors.orange),
          label: Text(_nightHaltConfirmed ? 'Night halt confirmed' : 'Confirm night halt (optional)'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46),
            side: BorderSide(color: _nightHaltConfirmed ? Colors.grey : AppColors.orange)),
        ),
        const SizedBox(height: 10),
        SwipeToConfirm(
          label: 'Swipe to start the return',
          icon: Icons.u_turn_left_rounded,
          enabled: !_stepBusy,
          onConfirm: () => _setLeg('returning'),
        ),
      ];
    }
    // The label states what ending actually does for this payment mode —
    // including any tolls, which the rider pays the driver in every mode.
    final toll = _tollTotal;
    final endLabel = r.paymentMode == 'cash'
        ? 'Swipe to collect ₹${(_fareOf(r) + toll).round()}'
        : r.paymentMode == 'online'
            ? (toll > 0 ? 'Swipe to collect toll & request payment' : 'Swipe to request payment')
            : (toll > 0 ? 'Swipe to collect toll & end ride' : 'Swipe to end ride');
    return [
      SwipeToConfirm(
        label: endLabel,
        tone: SwipeTone.danger,
        icon: Icons.stop_circle_outlined,
        onConfirm: () => _endRide(context, bloc),
      ),
    ];
  }

  Widget _locationRow(IconData icon, Color color, String label, String addr) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.textGrey)),
        Text(addr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textDark),
          maxLines: 2, overflow: TextOverflow.ellipsis),
      ])),
    ]);
  }

  void _showOtpDialog(BuildContext context, RideBloc bloc) {
    OtpDialog.show(context, title: 'Enter Ride OTP', label: 'OTP from Rider', hint: 'e.g. 5678', action: 'Start')
        .then((otp) { if (otp != null) bloc.add(StartRideEvent(otp)); });
  }

  double _fareOf(RideRequestModel r) => r.totalFareValue > 0
      ? r.totalFareValue.toDouble()
      : (double.tryParse(r.fare.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0);

  /// Ends the ride for its payment mode. The swipe that calls this is itself
  /// the confirmation. Cash still gets a real one: the collect-fare screen,
  /// where the driver confirms the money is in hand.
  ///
  /// Tolls are always paid to the driver in hand, whatever the fare was paid
  /// with: in cash they are collected with the fare; otherwise on their own,
  /// before the ride is closed. They never pass through the wallet.
  Future<void> _endRide(BuildContext context, RideBloc bloc) async {
    // No toll can be added or removed from here on: this is the bill. A Retry
    // still up for an unsaved toll could only be refused now.
    if (_unsent != null) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    _arrivalHint.dismiss();
    setState(() { _ending = true; _tollPrompt = null; });
    final toll = _tollTotal;
    var done = false;
    try {
      if (r.paymentMode == 'cash') {
        final collected = await Navigator.push<bool>(
          context, MaterialPageRoute(builder: (_) => CollectFarePage(
            amount: _fareOf(r) + toll.toDouble(),
            title: toll > 0 ? 'Fare + tolls' : 'Estimated Order Fare')));
        if (collected == true) { done = true; bloc.add(EndRideEvent()); }
        return;
      }
      if (toll > 0) {
        final collected = await Navigator.push<bool>(
          context, MaterialPageRoute(builder: (_) => CollectFarePage(
            amount: toll.toDouble(), title: 'Collect tolls from the rider')));
        if (collected != true || !context.mounted) return;
      }
      done = true;
      if (r.paymentMode == 'online') {
        // Online: the driver requests payment; the ride completes when the rider
        // pays. Requesting it freezes the tolls on the server too.
        setState(() => _tollsLocked = true);
        await waitForRiderPayment(context, r,
            invoiceArgs: RideCompletionArgs(r, tollCollected: toll));
      } else {
        bloc.add(EndRideEvent()); // wallet — auto-deducted
      }
    } finally {
      // Backed out before anything was sent: the trip, and its tolls, go on.
      if (!done && mounted) setState(() => _ending = false);
    }
  }

  @override
  void dispose() {
    _faceCheckTimer?.cancel();
    super.dispose();
  }
}

/// Asks how much the toll was. Pops the whole-rupee amount, or null.
///
/// Checks the same bounds as the server, so a mistyped amount is caught here
/// rather than after a round trip.
class _TollAmountSheet extends StatefulWidget {
  const _TollAmountSheet();
  static const maxRupees = 2000;
  @override
  State<_TollAmountSheet> createState() => _TollAmountSheetState();
}

class _TollAmountSheetState extends State<_TollAmountSheet> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_ctrl.text.trim());
    if (v == null || v < 1) {
      setState(() => _error = 'Enter the toll amount');
      return;
    }
    if (v > _TollAmountSheet.maxRupees) {
      setState(() => _error = 'A single toll cannot be more than ₹${_TollAmountSheet.maxRupees}');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Add toll', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark)),
      const SizedBox(height: 4),
      Text('The amount you paid at the toll plaza.', style: TextStyle(fontSize: 12.5, color: AppColors.textGrey)),
      const SizedBox(height: 14),
      TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          prefixText: '₹ ',
          labelText: 'Toll amount',
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
        const SizedBox(width: 10),
        Expanded(child: ElevatedButton(onPressed: _submit, child: const Text('Add'))),
      ]),
    ]),
  );
}
