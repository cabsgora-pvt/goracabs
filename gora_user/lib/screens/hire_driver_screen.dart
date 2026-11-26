import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../utils/net_errors.dart';
import '../utils/ride_booking.dart';
import '../widgets/payment_coupon_bar.dart';
import '../widgets/ride_ui/ride_ui.dart';

// Hire a Driver — customer's own car, priced by hours (pickup time → drop time).
class HireDriverScreen extends StatefulWidget {
  /// Start and end of the hire, when already known (a repeat booking, a test).
  final DateTime? initialStartAt;
  final DateTime? initialEndAt;
  const HireDriverScreen({super.key, this.initialStartAt, this.initialEndAt});
  @override
  State<HireDriverScreen> createState() => _HireDriverScreenState();
}

class _HireDriverScreenState extends State<HireDriverScreen> {
  final _pickupCtrl = TextEditingController();
  final _dropCtrl = TextEditingController();
  double? _pickupLat, _pickupLng, _dropLat, _dropLng;
  DateTime? _startAt, _endAt;
  String _transmission = 'manual';
  String _tripType = 'one_way';   // one_way | round_trip
  String _paymentMode = 'cash';
  String _couponCode = '';
  String? _selectedVehicle;
  List<Map<String, dynamic>> _vehicles = [];
  bool _loading = false;
  String? _error;
  bool _errorOffline = false; // the fare load never reached the server
  bool _errorRetry = false;   // the error is a failed load (show Retry), not "not offered here"
  int _faresSeq = 0;

  // Autocomplete: one Places session per search, _searchSeq drops stale answers.
  List<Map<String, dynamic>> _pickSug = [], _dropSug = [];
  Timer? _debounce;
  final PlacesSession _places = PlacesSession();
  int _searchSeq = 0;
  bool _searching = false, _searchingPickup = true;
  String? _searchProblem;
  String _searched = '';
  // Map picker
  bool _showMap = false, _pickingPickup = true;
  LatLng _center = const LatLng(23.0225, 72.5714);
  GoogleMapController? _mapCtrl;
  String _mapAddr = '';
  // The booked hire is tracked on ActiveRideScreen (see _confirmHire), so this
  // screen holds no live ride state.

  int get _totalHours {
    if (_startAt == null || _endAt == null) return 0;
    final h = _endAt!.difference(_startAt!).inMinutes / 60;
    return h <= 0 ? 0 : h.ceil();
  }

  @override
  void initState() {
    super.initState();
    _startAt = widget.initialStartAt;
    _endAt = widget.initialEndAt;
    _initLocation();
  }

  @override
  void dispose() { _debounce?.cancel(); _pickupCtrl.dispose(); _dropCtrl.dispose(); super.dispose(); }

  Future<void> _initLocation() async {
    final pos = await LocationService.getCurrentLocation();
    if (pos == null || !mounted) return;
    _pickupLat = pos.latitude; _pickupLng = pos.longitude;
    final addr = await ApiService.reverseGeocode(pos.latitude, pos.longitude);
    if (mounted && addr.isNotEmpty) setState(() => _pickupCtrl.text = addr);
    if (mounted && _totalHours > 0) _loadFares();
  }

  void _search(String q, {required bool pickup}) {
    _debounce?.cancel();
    final seq = ++_searchSeq;
    if (q.trim().length < 2) {
      setState(() { if (pickup) { _pickSug = []; } else { _dropSug = []; } _searching = false; _searchProblem = null; _searched = ''; });
      return;
    }
    setState(() {
      _searching = true; _searchingPickup = pickup; _searchProblem = null;
      if (pickup) { _dropSug = []; } else { _pickSug = []; }
    });
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      // Biased towards the pickup (the GPS fix until one is chosen).
      final r = await ApiService.placesSearch(q, lat: _pickupLat, lng: _pickupLng, sessionToken: _places.token);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        if (pickup) { _pickSug = r.predictions; } else { _dropSug = r.predictions; }
        _searching = false; _searchProblem = r.problem; _searched = q.trim();
      });
    });
  }

  /// Under the fields while the active list is empty: searching / problem / none found.
  Widget _searchStatus() {
    if ((_searchingPickup ? _pickSug : _dropSug).isNotEmpty) return const SizedBox.shrink();
    if (_searching) return const SearchStatusLine(searching: true);
    if (_searchProblem != null) return SearchStatusLine(message: _searchProblem);
    final text = (_searchingPickup ? _pickupCtrl : _dropCtrl).text.trim();
    if (_searched.isNotEmpty && text.length >= 2) return SearchStatusLine(message: 'No places found for "$_searched"');
    return const SizedBox.shrink();
  }

  Future<void> _pickSuggestion(Map<String, dynamic> s, {required bool pickup}) async {
    final d = await ApiService.placeDetails(s['placeId'] as String? ?? '', sessionToken: _places.token);
    _places.renew(); // the pick ends this search session
    if (d == null || !mounted) return;
    // placeDetails returns numeric lat/lng or null, never an error map.
    final lat = ApiService.toDoubleOrNull(d['lat']), lng = ApiService.toDoubleOrNull(d['lng']);
    if (lat == null || lng == null) return;
    setState(() {
      if (pickup) { _pickupLat = lat; _pickupLng = lng; _pickupCtrl.text = '${d['address'] ?? ''}'; _pickSug = []; }
      else { _dropLat = lat; _dropLng = lng; _dropCtrl.text = '${d['address'] ?? ''}'; _dropSug = []; }
      _searched = ''; _searchProblem = null;
    });
    // Hire pricing is per zone: a new pickup can change it.
    if (pickup && _totalHours > 0) _loadFares();
  }

  /// Hire prices for the pickup and hours. [_faresSeq] keeps an older,
  /// slower answer (the rider changed the time or trip type meanwhile) from
  /// replacing a newer one; every setState checks mounted.
  Future<void> _loadFares() async {
    if (!mounted) return;
    final seq = ++_faresSeq;
    if (_pickupLat == null || _totalHours <= 0) {
      setState(() { _vehicles = []; _loading = false; _error = null; _errorOffline = false; });
      return;
    }
    setState(() { _loading = true; _error = null; _errorOffline = false; });
    try {
      final res = await ApiService.post('/fare/estimate', _estimateBody());
      if (!mounted || seq != _faresSeq) return;
      if (res['available'] != true) {
        // An error answer (offline page, 5xx) is not "not available here".
        final failed = res['error'] != null && res['available'] == null;
        final f = classifyResponse(res);
        setState(() {
          _loading = false;
          _vehicles = [];
          _errorOffline = failed && f == LoadFailure.offline;
          _errorRetry = failed;
          _error = failed ? loadFailureMessage(f, what: 'hire prices') : (res['message'] ?? 'Not available').toString();
        });
        return;
      }
      setState(() {
        _vehicles = ((res['vehicles'] as List?) ?? []).map((v) => Map<String, dynamic>.from(v as Map)).toList();
        _loading = false;
        _errorRetry = false;
        _error = _vehicles.isEmpty ? 'No hire pricing configured for this zone' : null;
      });
    } catch (e) {
      if (!mounted || seq != _faresSeq) return;
      final f = classifyFailure(e);
      setState(() {
        _loading = false;
        _vehicles = [];
        _errorOffline = f == LoadFailure.offline;
        _errorRetry = true;
        _error = loadFailureMessage(f, what: 'hire prices');
      });
    }
  }

  /// What /fare/estimate is asked. The quote is signed over its hours and
  /// trip type, so they are exactly what the hire is booked with
  /// (hireTotalHours, tripType).
  Map<String, dynamic> _estimateBody() => {
        'pickupLat': _pickupLat, 'pickupLng': _pickupLng, 'service': 'hire_driver',
        'totalHours': _totalHours, 'tripType': _tripType,
      };

  /// Books the hire and returns the server's answer; [bookAndTrack] reports a
  /// failure and opens the live ride screen on success. The quoted fare is sent
  /// in full and only the coupon code: the server applies the discount.
  Future<Map<String, dynamic>> _book(String clientRequestId, bool freshQuote) async {
    final v = _vehicles.firstWhere((x) => x['name'] == _selectedVehicle, orElse: () => {});
    if (freshQuote) {
      final q = await freshQuoteFor(_estimateBody(), _selectedVehicle);
      if (q != null) v.addAll(q);
    }
    final num fare = (v['fare'] as num?) ?? 0;
    return ApiService.bookRide({
        'clientRequestId': clientRequestId,
        'pickupAddress': _pickupCtrl.text, 'dropAddress': _dropCtrl.text,
        'pickupLat': _pickupLat, 'pickupLng': _pickupLng,
        'dropLat': _dropLat ?? _pickupLat, 'dropLng': _dropLng ?? _pickupLng,
        'service': 'hire_driver', 'vehicleType': _selectedVehicle,
        'fare': fare, 'hirePerHour': v['perHour'] ?? 0,
        'quoteToken': v['quoteToken'],
        'hireTotalHours': _totalHours, 'transmission': _transmission,
        'tripType': _tripType,
        'hireStartAt': _startAt?.toUtc().toIso8601String(), 'hireEndAt': _endAt?.toUtc().toIso8601String(),
        'paymentMode': _paymentMode,
        if (_couponCode.isNotEmpty) 'couponCode': _couponCode,
      });
  }

  /// Book once, from the button — never from a route builder — then track the
  /// hire on the live ride screen. The server validates the coupon and keeps
  /// its discount on the ride.
  Future<void> _confirmHire() => bookAndTrack(
    context,
    book: _book,
  );

  Future<void> _pickDateTime({required bool isStart}) async {
    final base = (isStart ? _startAt : _endAt) ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: base, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (t == null) return;
    final dt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() { if (isStart) { _startAt = dt; } else { _endAt = dt; } });
    if (_totalHours > 0) _loadFares();
  }

  @override
  Widget build(BuildContext context) {
    if (_showMap) return _buildMapPicker();
    return Scaffold(
      backgroundColor: RideUi.surface(context),
      body: Column(children: [
        const ServiceBackBar(),
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          const ServiceTitle(title: 'Hire a driver', subtitle: 'A verified driver for your own car, paid by the hour'),
          RouteInputBlock(rows: [
            RouteFieldRow(
              marker: RouteMarkerKind.pickup,
              trailing: MapPickAction(tooltip: 'Pick pickup on map', onTap: () => _openMap(pickup: true)),
              child: _locInput(_pickupCtrl, 'Pickup location', pickup: true),
            ),
            RouteFieldRow(
              marker: RouteMarkerKind.drop,
              trailing: MapPickAction(tooltip: 'Pick drop on map', onTap: () => _openMap(pickup: false)),
              child: _locInput(_dropCtrl, 'Drop location', pickup: false),
            ),
          ]),
          ..._pickSug.map((s) => _sugTile(s, pickup: true)),
          ..._dropSug.map((s) => _sugTile(s, pickup: false)),
          _searchStatus(),

          const ServiceSection('When do you need the driver?', subtitle: 'The driver is paid from pickup time to drop time'),
          PickerPill(
            icon: Icons.schedule,
            label: 'Pickup time',
            value: _startAt == null ? 'Select date & time' : serviceDateTime(_startAt!),
            placeholder: _startAt == null,
            onTap: () => _pickDateTime(isStart: true),
          ),
          const SizedBox(height: 10),
          PickerPill(
            icon: Icons.flag_outlined,
            label: 'Drop time',
            value: _endAt == null ? 'Select date & time' : serviceDateTime(_endAt!),
            placeholder: _endAt == null,
            onTap: () => _pickDateTime(isStart: false),
          ),
          if (_totalHours > 0) Padding(padding: const EdgeInsets.only(top: 10),
            child: NoticeRow('Total: $_totalHours hour${_totalHours > 1 ? 's' : ''} — driver paid for this duration',
              icon: Icons.timelapse)),

          const ServiceSection('Trip type'),
          ChoiceSegment<String>(
            options: const [ChoiceOption('one_way', 'One Way'), ChoiceOption('round_trip', 'Round Trip')],
            selected: _tripType,
            onChanged: (val) { setState(() => _tripType = val); if (_totalHours > 0) _loadFares(); },
          ),
          const SizedBox(height: 10),
          NoticeRow(
            _tripType == 'one_way'
              ? 'One Way: you also pay the driver\'s return charge from the drop location.'
              : 'Round Trip: driver returns with you — no extra return charge.',
            icon: _tripType == 'one_way' ? Icons.info_outline : Icons.check_circle_outline,
            tone: _tripType == 'one_way' ? NoticeTone.warning : NoticeTone.success,
          ),

          const ServiceSection('Car transmission'),
          ChoiceSegment<String>(
            options: const [
              ChoiceOption('manual', 'Manual', icon: Icons.settings_outlined),
              ChoiceOption('automatic', 'Automatic', icon: Icons.motion_photos_auto_outlined),
            ],
            selected: _transmission,
            onChanged: (val) => setState(() => _transmission = val),
          ),

          const ServiceSection('Select vehicle type'),
          if (_loading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else if (_error != null && _errorRetry)
            NoticeRow(_error!,
                tone: NoticeTone.warning,
                icon: _errorOffline ? Icons.wifi_off_rounded : Icons.error_outline,
                onRetry: _loadFares)
          else if (_error != null) _info(_error!)
          else if (_vehicles.isEmpty) _info('Set pickup + times to see hire prices')
          else ..._vehicles.map(_vehicleCard),
        ])),
        _bottomBar(),
      ]),
    );
  }

  void _openMap({required bool pickup}) => setState(() { _pickingPickup = pickup; _mapAddr = ''; _showMap = true; });

  Widget _bottomBar() {
    final ready = _selectedVehicle != null && _totalHours > 0 && _pickupLat != null;
    final v = _vehicles.firstWhere((x) => x['name'] == _selectedVehicle, orElse: () => {});
    return PrimaryCtaBar(
      top: PaymentCouponBar(
        baseFare: (v['fare'] as num?) ?? 0,
        // The discount shown is the server's preview (/promos/preview) for
        // this trip; the booking applies the same rules.
        service: 'hire_driver',
        pickupLat: _pickupLat, pickupLng: _pickupLng,
        onChanged: (pm, cc, _) => setState(() { _paymentMode = pm; _couponCode = cc; }),
      ),
      label: ready ? 'Book Driver · ₹${v['fare'] ?? ''}' : 'Select time & vehicle',
      onPressed: ready ? _showConfirm : null,
    );
  }

  void _showConfirm() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final v = _vehicles.firstWhere((x) => x['name'] == _selectedVehicle, orElse: () => {});
        final raw = (v['imageUrl'] as String?) ?? '';
        return SingleChildScrollView(
          padding: EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 16 + MediaQuery.of(ctx).viewPadding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetHandle(bottom: 14),
            Text('Confirm Hire', style: RideUi.title(ctx, size: 22)),
            const SizedBox(height: 14),
            SummaryVehicleTile(
              leading: VehicleThumb(networkUrl: raw.isEmpty ? '' : AppConfig.imageUrl(raw), fallbackIcon: Icons.directions_car, size: 48),
              name: _selectedVehicle ?? '',
              caption: '$_totalHours hr · ${_tripType == 'one_way' ? 'One Way' : 'Round Trip'}',
              price: '₹${v['fare'] ?? 0}',
            ),
            if (_pickupCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 14),
              TripRouteSummary(pickup: _pickupCtrl.text, drop: _dropCtrl.text, fontSize: 13.5),
            ],
            const RideDivider(vertical: 12),
            SummaryRow('Vehicle', _selectedVehicle ?? ''),
            SummaryRow('Transmission', _transmission == 'manual' ? 'Manual' : 'Automatic'),
            SummaryRow('Duration', '$_totalHours hr'),
            SummaryRow('Rate', '₹${v['perHour'] ?? 0}/hr'),
            const RideDivider(vertical: 6),
            SummaryRow('Total', '₹${v['fare'] ?? 0}', bold: true),
            const SizedBox(height: 16),
            PrimaryRideButton(
              label: 'Confirm & Find Driver',
              onPressed: () { Navigator.pop(ctx); _confirmHire(); },
            ),
          ]));
      });
  }

  // ── Map picker ──
  Widget _buildMapPicker() {
    return ServiceMapPicker(
      title: _pickingPickup ? 'Pick pickup' : 'Pick drop',
      forPickup: _pickingPickup,
      address: _mapAddr,
      onBack: () => setState(() => _showMap = false),
      onLocate: () async {
        final pos = await LocationService.getCurrentLocation();
        if (pos == null) return;
        _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15));
      },
      map: GoogleMap(initialCameraPosition: CameraPosition(target: _center, zoom: 14),
        onMapCreated: (c) => _mapCtrl = c, onCameraMove: (p) => _center = p.target,
        onCameraIdle: () async { final a = await ApiService.reverseGeocode(_center.latitude, _center.longitude); if (mounted) setState(() => _mapAddr = a); },
        myLocationEnabled: true, myLocationButtonEnabled: false, zoomControlsEnabled: false),
      onConfirm: _mapAddr.isEmpty ? null : () {
        setState(() {
          if (_pickingPickup) { _pickupLat = _center.latitude; _pickupLng = _center.longitude; _pickupCtrl.text = _mapAddr; }
          else { _dropLat = _center.latitude; _dropLng = _center.longitude; _dropCtrl.text = _mapAddr; }
          _showMap = false;
        });
        if (_pickingPickup && _totalHours > 0) _loadFares();
      },
    );
  }

  // ── Small builders ──
  Widget _info(String t) => NoticeRow(t, tone: NoticeTone.warning);

  Widget _locInput(TextEditingController ctrl, String hint, {required bool pickup}) => TextField(
    controller: ctrl, onChanged: (q) => _search(q, pickup: pickup),
    textAlignVertical: TextAlignVertical.center,
    decoration: RideUi.bareInput(context, hint), style: RideUi.body(context, size: 14.5, weight: FontWeight.w600));

  Widget _sugTile(Map<String, dynamic> s, {required bool pickup}) => PlaceSuggestionTile(
    title: s['mainText']?.toString() ?? '',
    subtitle: s['secondaryText']?.toString(),
    onTap: () => _pickSuggestion(s, pickup: pickup));

  Widget _vehicleCard(Map<String, dynamic> v) {
    final sel = _selectedVehicle == v['name'];
    final raw = (v['imageUrl'] as String?) ?? '';
    final img = raw.isEmpty ? '' : AppConfig.imageUrl(raw);
    final bk = v['breakdown'] as Map? ?? {};
    final num base = (bk['base'] as num?) ?? 0;
    final num hourCharge = (bk['hourCharge'] as num?) ?? 0;
    final num retCharge = (bk['returnCharge'] as num?) ?? 0;
    return VehicleOptionRow(
      selected: sel,
      onTap: () => setState(() => _selectedVehicle = v['name'] as String?),
      leading: VehicleThumb(networkUrl: img, fallbackIcon: Icons.directions_car),
      name: v['name']?.toString() ?? '',
      // The base fee is part of the price; without it ₹120/hr × 3 hr read as ₹460.
      subtitle: '₹${v['perHour'] ?? 0}/hr × $_totalHours hr${base > 0 ? ' + ₹${base.round()} base' : ''}',
      tagline: v['etaMin'] != null ? 'Driver ~${v['etaMin']} min away' : null,
      price: '₹${v['fare'] ?? 0}',
      // The breakdown of the SELECTED vehicle only: on every card it turned the
      // list into a wall of near-identical numbers.
      footer: sel && (base > 0 || hourCharge > 0)
          ? Padding(
              padding: const EdgeInsets.only(left: 4, right: 2),
              child: Column(children: [
                const RideDivider(vertical: 8),
                _bk('Base fare', '₹${base.toStringAsFixed(0)}'),
                _bk('Driver time ($_totalHours hr × ₹${v['perHour'] ?? 0})', '₹${hourCharge.toStringAsFixed(0)}'),
                if (retCharge > 0) _bk('Driver return (one-way)', '₹${retCharge.toStringAsFixed(0)}', color: Colors.orange),
                const RideDivider(vertical: 6),
                _bk('Total', '₹${v['fare'] ?? 0}', bold: true),
              ]),
            )
          : null,
    );
  }

  Widget _bk(String l, String v, {bool bold = false, Color? color}) => SummaryRow(l, v, bold: bold, valueColor: color);
}
