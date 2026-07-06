import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import '../../account/pages/support_page.dart';

// Arguments passed to the completion screen: the ride plus the money split
// returned by the complete-ride API (driver's earning + the admin commission).
class RideCompletionArgs {
  final RideRequestModel ride;
  final num driverEarning;
  final num adminProfit; // commission taken by admin; 0 when a subscription covers it
  const RideCompletionArgs(this.ride, {this.driverEarning = 0, this.adminProfit = 0});
}

// "Order Complete" screen shown after a ride ends: estimated earning, the
// 0%-commission badge (or the commission that was deducted), a customer rating
// and quick tags. Styled in the app's brand colours.
class InvoicePage extends StatefulWidget {
  static const route = '/invoice';
  const InvoicePage({super.key});
  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  int _stars = 5;
  final _tags = const ['Polite', 'Timely', 'Friendly', 'Clean', 'Safe Driving'];
  final Set<String> _selected = {};
  bool _submitting = false;

  Future<void> _done(RideRequestModel? ride) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    if (ride != null && ride.id.isNotEmpty && _stars > 0) {
      try {
        await DriverApiService.rateRide(ride.id, _stars, _selected.join(', '));
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    // Accept the new args object, but stay backward-compatible with a bare ride.
    final RideCompletionArgs data = args is RideCompletionArgs
        ? args
        : RideCompletionArgs(args as RideRequestModel? ?? _fallbackRide());
    final ride = data.ride;

    final earning = data.driverEarning > 0 ? data.driverEarning : ride.totalFareValue;
    final distKm = ride.distanceKm > 0 ? ride.distanceKm : ride.pickupDistanceKm;
    final perKm = distKm > 0 ? earning / distKm : 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0.5,
        automaticallyImplyLeading: false,
        title: Text('Order Complete',
            style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.w800, fontSize: 20)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(context, SupportPage.route),
              icon: Icon(Icons.headset_mic_outlined, size: 18, color: AppColors.textDark),
              label: Text('Help', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.divider),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              // ── Earning + commission ──
              _Card(child: Column(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Estimated Earning', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                    const SizedBox(height: 6),
                    Text('₹${earning.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: AppColors.green)),
                    const SizedBox(height: 4),
                    Text('${distKm.toStringAsFixed(2)} km · ${ride.durationMin} min',
                        style: TextStyle(fontSize: 13, color: AppColors.textGrey, fontWeight: FontWeight.w600)),
                  ])),
                  _commissionBadge(data.adminProfit),
                ]),
                Divider(color: AppColors.divider, height: 28),
                Row(children: [
                  const Icon(Icons.check_circle, color: AppColors.green, size: 20),
                  const SizedBox(width: 8),
                  Text('₹${perKm.toStringAsFixed(2)} per km earned',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                ]),
              ])),
              const SizedBox(height: 14),
              // ── Rate the customer ──
              _Card(child: Column(children: [
                Text('Rate your Customer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) =>
                  GestureDetector(
                    onTap: () => setState(() => _stars = i + 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(i < _stars ? Icons.star_rounded : Icons.star_border_rounded,
                          color: AppColors.orange, size: 46),
                    ),
                  ),
                )),
                const SizedBox(height: 6),
                Text(_ratingLabel(_stars),
                    style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.5)),
              ])),
              const SizedBox(height: 14),
              // ── Quick tags ──
              _Card(child: Column(children: [
                Text('What did you like?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: _tags.map((tag) {
                  final sel = _selected.contains(tag);
                  return GestureDetector(
                    onTap: () => setState(() => sel ? _selected.remove(tag) : _selected.add(tag)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.primary.withOpacity(0.1) : AppColors.cardBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: sel ? AppColors.primary : AppColors.divider),
                      ),
                      child: Text(tag, style: TextStyle(
                        color: sel ? AppColors.primary : AppColors.textGrey,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500, fontSize: 13,
                      )),
                    ),
                  );
                }).toList()),
              ])),
            ]),
          ),
        ),
        // ── Done (brand colour, not yellow) ──
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, -2))],
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : () => _done(ride),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: _submitting
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Done', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
        ),
      ]),
    );
  }

  // 0%-commission badge when a subscription covers the ride; otherwise a chip
  // showing the commission that was actually deducted.
  Widget _commissionBadge(num adminProfit) {
    if (adminProfit <= 0) {
      return Container(
        width: 96, height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withOpacity(0.06),
          border: Border.all(color: AppColors.primary.withOpacity(0.45), width: 1.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('0%', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 28, height: 1)),
          const SizedBox(height: 2),
          Text('COMMISSION', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 8, letterSpacing: 0.5)),
          Text('Lifetime Guarantee', style: TextStyle(color: AppColors.primary.withOpacity(0.7), fontWeight: FontWeight.w600, fontSize: 6.5)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withOpacity(0.3)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Commission', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 11)),
        const SizedBox(height: 2),
        Text('- ₹${adminProfit.toStringAsFixed(0)}',
            style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w900, fontSize: 20)),
      ]),
    );
  }

  String _ratingLabel(int s) {
    if (s <= 0) return 'TAP TO RATE';
    if (s <= 2) return 'POOR';
    if (s == 3) return 'OKAY';
    if (s == 4) return 'GOOD';
    return 'EXCELLENT';
  }

  RideRequestModel _fallbackRide() => const RideRequestModel(
        id: '', userName: 'Customer', userPhone: '', userRating: '5.0',
        pickupAddress: '', dropAddress: '', distance: '0 km', fare: '₹ 0', eta: '0 min',
        rideType: 'taxi', pickupLat: 0, pickupLng: 0, dropLat: 0, dropLng: 0,
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
        ),
        child: child,
      );
}
