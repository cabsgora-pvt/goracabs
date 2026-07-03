import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../config/app_config.dart';
import '../../../services/driver_api_service.dart';

class IdCardPage extends StatefulWidget {
  static const route = '/id-card';
  const IdCardPage({super.key});
  @override
  State<IdCardPage> createState() => _IdCardPageState();
}

class _IdCardPageState extends State<IdCardPage> {
  final GlobalKey _cardKey = GlobalKey();
  bool _loading = true, _busy = false;
  Map<String, dynamic> _d = {};

  static const _navy = Color(0xFF1C2656);
  static const _orange = Color(0xFFFF7A00);

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try { _d = await DriverApiService.getIdCard(); } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _fmtDate(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final boundary = _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/gora_captain_id.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], text: 'My Gora Captain ID — ${_d['goraId'] ?? ''}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not export: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('My ID Card'),
      backgroundColor: AppColors.cardBg,
      body: _loading
          ? const AppLoader()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                RepaintBoundary(key: _cardKey, child: _card()),
                const SizedBox(height: 20),
                PrimaryButton(label: _busy ? 'Preparing...' : 'Download / Share', loading: _busy, onTap: _download),
              ]),
            ),
    );
  }

  Widget _card() {
    final pic = (_d['profilePicUrl'] ?? '').toString();
    final picUrl = pic.isEmpty ? '' : AppConfig.imageUrl(pic);
    final goraId = (_d['goraId'] ?? '—').toString();
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 14, offset: const Offset(0, 6))]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(children: [
          // Header (white) — logo + GORA CAPTAIN + shield
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                width: 58, height: 58,
                decoration: const BoxDecoration(color: _navy, shape: BoxShape.circle),
                child: ClipOval(child: Padding(padding: const EdgeInsets.all(6), child: Image.asset('assets/images/logo.png', fit: BoxFit.contain))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text.rich(TextSpan(children: [
                  TextSpan(text: 'GORA ', style: TextStyle(color: _orange, fontWeight: FontWeight.w900, fontSize: 20)),
                  TextSpan(text: 'CAPTAIN', style: TextStyle(color: _navy, fontWeight: FontWeight.w900, fontSize: 20)),
                ])),
                Container(margin: const EdgeInsets.symmetric(vertical: 3), height: 2.5, width: 88, color: _orange),
                Text('YOUR RIDE, OUR RESPONSIBILITY', style: TextStyle(color: Colors.grey[600], fontSize: 7.5, letterSpacing: 0.3, fontWeight: FontWeight.w700)),
              ])),
              Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.shield, color: _navy, size: 30),
                Text('SAFE • RELIABLE', style: TextStyle(color: _navy, fontSize: 6, fontWeight: FontWeight.w800)),
                Text('TRUSTED', style: TextStyle(color: _navy, fontSize: 6, fontWeight: FontWeight.w800)),
              ]),
            ]),
          ),
          // Body — photo (left) · details (center) · QR + signature (right)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 70, height: 88,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: AppColors.cardBg, border: Border.all(color: _navy.withOpacity(0.25), width: 2)),
                child: ClipRRect(borderRadius: BorderRadius.circular(7),
                    child: picUrl.isEmpty
                        ? const Icon(Icons.person, size: 40, color: AppColors.textGrey)
                        : Image.network(picUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 40, color: AppColors.textGrey))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((_d['name'] ?? '').toString().toUpperCase(),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _navy), maxLines: 1, overflow: TextOverflow.ellipsis),
                Divider(height: 12, color: _navy.withOpacity(0.2)),
                Text('GORA ID', style: TextStyle(fontSize: 9, color: Colors.grey[600], fontWeight: FontWeight.w700, letterSpacing: 1)),
                const SizedBox(height: 3),
                Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: _navy, width: 1.4)),
                  child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                      child: Text(goraId, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _navy, letterSpacing: 0.5))),
                ),
                const SizedBox(height: 8),
                _row(Icons.calendar_month, 'JOINING DATE', _fmtDate(_d['joiningDate'])),
                _row(Icons.location_on, 'CITY', (_d['city'] ?? '').toString()),
                _row(Icons.call, 'MOBILE', (_d['mobile'] ?? '').toString()),
                _row(Icons.directions_car, 'VEHICLE NO.', (_d['vehicleNumber'] ?? '').toString()),
              ])),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(border: Border.all(color: _navy.withOpacity(0.3)), borderRadius: BorderRadius.circular(6)),
                      child: QrImageView(data: goraId, size: 50, padding: EdgeInsets.zero)),
                  Text('SCAN TO VERIFY', style: TextStyle(fontSize: 5.5, color: Colors.grey[600], fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  const Text('Gora Captain', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 11, color: _navy, fontWeight: FontWeight.w600)),
                  Container(height: 1, width: 54, color: _navy.withOpacity(0.35)),
                  const SizedBox(height: 2),
                  Text('AUTHORISED', style: TextStyle(fontSize: 5.5, color: Colors.grey[600], fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
          // Footer (navy)
          Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: _navy,
            child: Row(children: [
              const Icon(Icons.verified_user, color: Colors.white, size: 17),
              const SizedBox(width: 6),
              const Text('APPROVED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
              const SizedBox(width: 10),
              Container(width: 1, height: 16, color: Colors.white30),
              const SizedBox(width: 10),
              const Icon(Icons.public, color: Colors.white70, size: 13),
              const SizedBox(width: 5),
              const Expanded(child: Text('www.goracaptain.com', style: TextStyle(color: Colors.white70, fontSize: 10))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _row(IconData ic, String label, String val) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(children: [
          Container(width: 18, height: 18, decoration: const BoxDecoration(color: _navy, shape: BoxShape.circle),
              child: Icon(ic, size: 10, color: Colors.white)),
          const SizedBox(width: 6),
          SizedBox(width: 54, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 7.5, color: Colors.grey[700], fontWeight: FontWeight.w700))),
          const Text(': ', style: TextStyle(fontWeight: FontWeight.w900, color: _navy, fontSize: 11)),
          Expanded(child: Text(val.isEmpty ? '—' : val, maxLines: 1, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _navy), overflow: TextOverflow.ellipsis)),
        ]),
      );
}
