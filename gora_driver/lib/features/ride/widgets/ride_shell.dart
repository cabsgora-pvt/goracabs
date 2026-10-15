import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../utils/call_util.dart';
import '../pages/emergency_actions_page.dart';
import '../pages/ride_chat_page.dart';
import 'nav_engine.dart';
import 'nav_map.dart';

// ─────────────────────────────────────────────────────────────────────────────
// One on-ride layout for every service.
//
// Taxi and outstation had a full-screen navigation map with the job in a sheet
// over it. Rental, hire and parcel each had their own app bar, a 210px map card
// in a scrolling form, and an SOS button in a different corner — and none of the
// three could call or message the customer at all. A driver switching between
// services met a different screen, with its controls in different places, for
// what is the same job: drive there, deal with this person, do the next thing.
//
//   ┌──────────────────────────────┐
//   │ PHASE                    SOS │  top bar
//   │     turn-by-turn map         │
//   │                              │
//   ├──────────────────────────────┤
//   │ ═══  status strip            │  always visible
//   │ (o) Contact        ☎  💬     │  ┐ scroll together; tap the handle
//   │ … service details …          │  ┘ to fold the details away
//   │ [ primary action ]           │  always visible
//   └──────────────────────────────┘
//
// The sheet is measured, and the map is told its height, so the recenter
// controls, the "Navigate to" button and the camera's centre all sit in the
// part of the map the driver can actually see.
// ─────────────────────────────────────────────────────────────────────────────

/// Who the driver is dealing with right now — the rider, or for a parcel the
/// sender and then the receiver.
class RideContact {
  final String name;
  final String phone;
  /// What they are to this job: "Rider", "Sender", "Receiver".
  final String role;
  final String picUrl;
  const RideContact({required this.name, this.phone = '', this.role = '', this.picUrl = ''});
}

class RideShell extends StatefulWidget {
  final String rideId;
  final String vehicleType;
  final NavLeg leg;
  final String? fallbackPolyline;
  final VoidCallback? onArrived;
  final ValueChanged<NavStep>? onTollRoad;
  final ValueChanged<LatLng>? onPosition;

  /// Short, upper-case state for the top bar — "TO PICKUP", "ON RENTAL".
  final String phase;
  final Widget status;
  final RideContact contact;

  /// In-app chat is always with the customer who booked, whoever [contact] is.
  final String chatWith;
  final Widget? contactTrailing;

  /// Service detail. Scrolls, and folds away when the driver wants the map.
  final List<Widget> details;

  /// The next thing to do. Always visible, never scrolled out of reach.
  final List<Widget> actions;

  /// The trip is under way — the rider (or the parcel) is on board and there is
  /// a destination to drive to. The details fold away so the map, with the turn
  /// ahead, gets the screen; the handle still opens them. Before, the sheet
  /// stayed open over all but the top 170pt of the map for the whole drive.
  final bool driving;

  const RideShell({
    super.key,
    required this.rideId,
    required this.leg,
    required this.phase,
    required this.status,
    required this.contact,
    required this.chatWith,
    this.vehicleType = '',
    this.fallbackPolyline,
    this.onArrived,
    this.onTollRoad,
    this.onPosition,
    this.contactTrailing,
    this.details = const [],
    this.actions = const [],
    this.driving = false,
  });

  @override
  State<RideShell> createState() => _RideShellState();
}

class _RideShellState extends State<RideShell> {
  // A first guess until the sheet has been measured, close to its usual height
  // so the map controls do not visibly jump on the first frame.
  double _sheetHeight = 300;
  // Folded while driving — including a trip reopened mid-drive.
  late bool _detailsOpen = !widget.driving;

  @override
  void didUpdateWidget(covariant RideShell old) {
    super.didUpdateWidget(old);
    // Setting off (the OTP just went in): hand the screen to the map.
    if (widget.driving && !old.driving) _detailsOpen = false;
  }

  void _onSheetSize(Size size) {
    if (!mounted || (size.height - _sheetHeight).abs() < 1) return;
    setState(() => _sheetHeight = size.height);
  }

  void _openChat() => Navigator.push(context, MaterialPageRoute(
      builder: (_) => RideChatPage(rideId: widget.rideId, otherName: widget.chatWith)));

  void _openSos() => Navigator.push(context, MaterialPageRoute(
      builder: (_) => EmergencyActionsPage(rideId: widget.rideId)));

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topBar = media.padding.top + 56;
    // The sheet may take most of the screen, but always leaves enough map for
    // the manoeuvre banner and the driver's own position to stay visible.
    final maxSheet = (media.size.height - topBar - 170).clamp(220.0, double.infinity);

    return Scaffold(
      backgroundColor: AppColors.background,
      // The sheet is the Scaffold's bottom bar, with the map extended behind it.
      // As a plain overlay in the body, every snackbar was drawn ON TOP of the
      // sheet — so "Could not finish, swipe again" sat over the very swipe it
      // asked for, for six seconds. The Scaffold lifts snackbars above its
      // bottom bar, for every screen and every message, with no per-call setup.
      extendBody: true,
      body: Stack(children: [
        Positioned.fill(
          child: NavMapPanel(
            vehicleType: widget.vehicleType,
            leg: widget.leg,
            fallbackPolyline: widget.fallbackPolyline,
            height: media.size.height,
            topInset: topBar + 8,
            bottomInset: _sheetHeight + 10,
            onArrived: widget.onArrived,
            onTollRoad: widget.onTollRoad,
            onPosition: widget.onPosition,
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: _topBar(media.padding.top)),
      ]),
      bottomNavigationBar: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheet),
        child: _MeasureSize(onChange: _onSheetSize, child: _sheet(media.padding.bottom)),
      ),
    );
  }

  Widget _topBar(double safeTop) => Container(
    padding: EdgeInsets.only(top: safeTop + 8, left: 16, right: 16, bottom: 12),
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
    ),
    child: Row(children: [
      Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8,
              decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(child: Text(widget.phase,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
          ]),
        ),
      ),
      const SizedBox(width: 12),
      Semantics(
        button: true,
        label: 'Emergency SOS',
        excludeSemantics: true,
        child: Material(
          color: AppColors.red,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _openSos,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900,
                fontSize: 12, letterSpacing: 0.5)),
            ),
          ),
        ),
      ),
    ]),
  );

  Widget _sheet(double safeBottom) => Container(
    padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + safeBottom),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 16)],
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // The handle folds the details away, giving the map back to the driver.
      Semantics(
        button: true,
        label: _detailsOpen ? 'Hide trip details' : 'Show trip details',
        excludeSemantics: true,
        child: InkWell(
          onTap: widget.details.isEmpty ? null : () => setState(() => _detailsOpen = !_detailsOpen),
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 72, height: 20,
            child: Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
          ),
        ),
      ),
      const SizedBox(height: 4),
      // Pinned: the job's state and the next action. Everything between them
      // shares one scroll area, so however much a service has to show — and
      // however small the phone or large the text — the sheet scrolls instead
      // of overflowing, and neither the state nor the action is ever pushed off.
      widget.status,
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _contactRow(),
            if (_detailsOpen && widget.details.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...widget.details,
            ],
          ]),
        ),
      ),
      if (widget.actions.isNotEmpty) ...[
        const SizedBox(height: 12),
        ...widget.actions,
      ],
    ]),
  );

  Widget _contactRow() {
    final c = widget.contact;
    final initial = c.name.trim().isNotEmpty ? c.name.trim()[0].toUpperCase() : '?';
    return Row(children: [
      CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.primary,
        backgroundImage: c.picUrl.isNotEmpty ? NetworkImage(c.picUrl) : null,
        child: c.picUrl.isEmpty
            ? Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))
            : null,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.name,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textDark)),
          if (c.role.isNotEmpty)
            Text(c.role,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
        ]),
      ),
      if (widget.contactTrailing != null) ...[
        const SizedBox(width: 6),
        // Shares the row with the name rather than taking a fixed width: a
        // six-figure fare beside two 44pt buttons overflowed a 320pt screen.
        Flexible(
          child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight,
            child: widget.contactTrailing!),
        ),
      ],
      const SizedBox(width: 4),
      if (c.phone.trim().isNotEmpty)
        _roundAction(
          icon: Icons.call,
          color: AppColors.green,
          tooltip: c.role.isEmpty ? 'Call' : 'Call ${c.role.toLowerCase()}',
          onTap: () => dialPhone(c.phone, context: context),
        ),
      const SizedBox(width: 6),
      _roundAction(
        icon: Icons.chat_bubble_outline,
        color: AppColors.primary,
        tooltip: 'Message rider',
        onTap: _openChat,
      ),
    ]);
  }

  /// A 44pt tinted circle — the minimum a driver can hit reliably in a mount.
  Widget _roundAction({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) => Tooltip(
    message: tooltip,
    child: Material(
      color: color.withOpacity(0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 44, height: 44, child: Icon(icon, color: color, size: 21)),
      ),
    ),
  );
}

/// Reports its child's laid-out size after each layout that changes it.
class _MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onChange;
  const _MeasureSize({required this.onChange, required Widget child}) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureSize renderObject) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  ValueChanged<Size> onChange;
  Size? _last;
  _RenderMeasureSize(this.onChange);

  @override
  void performLayout() {
    super.performLayout();
    final s = child?.size ?? Size.zero;
    if (s == _last) return;
    _last = s;
    // Never setState during layout: report once the frame is done.
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(s));
  }
}
