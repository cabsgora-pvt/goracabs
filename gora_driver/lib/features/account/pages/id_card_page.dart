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
  static const _deep = Color(0xFF0E1B3D);
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
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [_deep, _navy])),
            child: Row(children: [
              Container(width: 50, height: 50, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.local_taxi, color: _navy, size: 26)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                Text.rich(TextSpan(children: [
                  TextSpan(text: 'GORA ', style: TextStyle(color: _orange, fontWeight: FontWeight.w900, fontSize: 18)),
                  TextSpan(text: 'CAPTAIN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                ])),
                SizedBox(height: 3),
                Text('YOUR RIDE, OUR RESPONSIBILITY', style: TextStyle(color: Colors.white70, fontSize: 8, letterSpacing: 0.4)),
              ])),
              Column(children: const [
                Icon(Icons.verified_user, color: Colors.white, size: 24),
                SizedBox(height: 2),
                Text('SAFE • TRUSTED', style: TextStyle(color: Colors.white70, fontSize: 6.5, fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(children: [
                Container(
                  width: 92, height: 108,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: AppColors.cardBg, border: Border.all(color: AppColors.divider)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: picUrl.isEmpty
                        ? const Icon(Icons.person, size: 50, color: AppColors.textGrey)
                        : Image.network(picUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 50, color: AppColors.textGrey)),
                  ),
                ),
                const SizedBox(height: 10),
                QrImageView(data: goraId, size: 74, padding: EdgeInsets.zero),
                const Text('SCAN TO VERIFY', style: TextStyle(fontSize: 7, color: AppColors.textGrey, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((_d['name'] ?? '').toString().toUpperCase(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _navy), maxLines: 2),
                const Divider(height: 14),
                const Text('GORA ID', style: TextStyle(fontSize: 10, color: AppColors.textGrey, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: _navy, width: 1.4)),
                  child: Text(goraId, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _navy, letterSpacing: 0.8)),
                ),
                const SizedBox(height: 10),
                _row(Icons.calendar_month, 'JOINING', _fmtDate(_d['joiningDate'])),
                _row(Icons.location_on, 'CITY', (_d['city'] ?? '').toString()),
                _row(Icons.call, 'MOBILE', (_d['mobile'] ?? '').toString()),
                _row(Icons.directions_car, 'VEHICLE', (_d['vehicleNumber'] ?? '').toString()),
              ])),
            ]),
          ),
          // Footer
          Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [_deep, _navy])),
            child: Row(children: const [
              Icon(Icons.verified, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text('APPROVED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              Spacer(),
              Text('www.goracaptain.com', style: TextStyle(color: Colors.white70, fontSize: 10)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _row(IconData ic, String label, String val) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Container(width: 22, height: 22, decoration: const BoxDecoration(color: _navy, shape: BoxShape.circle),
              child: Icon(ic, size: 12, color: Colors.white)),
          const SizedBox(width: 8),
          SizedBox(width: 62, child: Text(label, style: const TextStyle(fontSize: 9.5, color: AppColors.textGrey, fontWeight: FontWeight.w700))),
          const Text(': ', style: TextStyle(fontWeight: FontWeight.w700)),
          Expanded(child: Text(val.isEmpty ? '—' : val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _navy), overflow: TextOverflow.ellipsis)),
        ]),
      );
}
