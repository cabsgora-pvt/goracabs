import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_colors.dart';
import '../services/app_update.dart';

/// Sits over every screen (MaterialApp.builder). A required update covers the
/// app with a screen that cannot be closed; an optional one is a banner at the
/// bottom with "Update" and a close button.
class UpdateGate extends StatelessWidget {
  final Widget child;
  const UpdateGate({super.key, required this.child});

  static Future<void> openStore(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<UpdateNotice>(
    valueListenable: AppUpdate.notice,
    builder: (context, n, _) {
      if (n.level == UpdateLevel.required) {
        return Stack(children: [
          // Kept mounted underneath (no state is lost), but unreachable.
          ExcludeSemantics(child: AbsorbPointer(child: child)),
          Positioned.fill(child: _RequiredUpdate(notice: n)),
        ]);
      }
      if (n.level == UpdateLevel.optional) {
        return Column(children: [
          Expanded(child: MediaQuery.removePadding(context: context, removeBottom: true, child: child)),
          _UpdateBanner(notice: n),
        ]);
      }
      return child;
    },
  );
}

class _RequiredUpdate extends StatelessWidget {
  final UpdateNotice notice;
  const _RequiredUpdate({required this.notice});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.system_update_rounded, size: 72, color: AppColors.primary),
          const SizedBox(height: 20),
          const Text('Update required', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF111111))),
          const SizedBox(height: 10),
          Text(
            notice.message.isNotEmpty
                ? notice.message
                : 'This version of Gora Captain is no longer supported. Please update to keep taking trips.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              key: const ValueKey('update_required_button'),
              onPressed: () => UpdateGate.openStore(notice.storeUrl),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Text('Update now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    ),
  );
}

class _UpdateBanner extends StatelessWidget {
  final UpdateNotice notice;
  const _UpdateBanner({required this.notice});
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF111827),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(children: [
          const Icon(Icons.system_update_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notice.message.isNotEmpty
                  ? notice.message
                  : 'A new version${notice.latestVersion.isNotEmpty ? ' (${notice.latestVersion})' : ''} is available.',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => UpdateGate.openStore(notice.storeUrl),
            child: const Text('Update', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          // No tooltip: the gate sits above the Navigator (MaterialApp.builder),
          // where there is no Overlay — a Tooltip there throws. The semantic
          // label gives screen readers the same "Close".
          Semantics(
            label: 'Close',
            button: true,
            child: const IconButton(
              key: ValueKey('update_banner_close'),
              onPressed: AppUpdate.dismiss,
              icon: Icon(Icons.close, color: Colors.white70, size: 20),
            ),
          ),
        ]),
      ),
    ),
  );
}
