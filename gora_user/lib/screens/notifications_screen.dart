import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../widgets/ride_ui/ride_ui.dart';

/// The rider's notification feed: admin broadcasts and messages sent to this
/// rider, newest first, with the image the admin attached when there is one.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Map<String, dynamic> res;
    try {
      res = await ApiService.getNotifications();
    } catch (_) {
      res = const {'error': 'Could not reach Gora. Check your connection and try again.'};
    }
    if (!mounted) return;
    final list = res['notifications'];
    setState(() {
      _loading = false;
      if (list is List) {
        _error = null;
        _items = list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
          // The server sends newest first; sort anyway so the order never
          // depends on it.
          ..sort((a, b) => (_time(b['sentAt']) ?? DateTime(0)).compareTo(_time(a['sentAt']) ?? DateTime(0)));
      } else {
        _error = (res['error'] ?? 'Could not load notifications').toString();
      }
    });
  }

  static DateTime? _time(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  /// "Just now", "5 min ago", "3 h ago", "Yesterday", else "Wed, 29 Oct".
  static String _when(Object? v) {
    final t = _time(v);
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays == 1) return 'Yesterday';
    final s = serviceDate(t);
    return t.year == DateTime.now().year ? s : '$s ${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RideUi.surface(context),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: RideUi.surface(context),
        title: Text('Notifications', style: RideUi.title(context, size: 18)),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _body(),
            ),
    );
  }

  Widget _body() {
    // Every state is a scrollable, so pull-to-refresh works on all of them.
    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(RideUi.gutter),
        children: [
          const SizedBox(height: 40),
          NoticeRow(_error!, tone: NoticeTone.warning, onRetry: () {
            setState(() => _loading = true);
            _load();
          }),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(RideUi.gutter),
        children: [
          const SizedBox(height: 90),
          Center(
            child: Container(
              width: 84, height: 84,
              decoration: BoxDecoration(color: RideUi.tile(context), shape: BoxShape.circle),
              child: Icon(Icons.notifications_none_rounded, size: 40, color: RideUi.muted(context)),
            ),
          ),
          const SizedBox(height: 16),
          Text('No notifications yet', textAlign: TextAlign.center, style: RideUi.title(context, size: 17)),
          const SizedBox(height: 6),
          Text('Offers and updates from Gora will show up here.',
              textAlign: TextAlign.center, style: RideUi.caption(context, size: 13.5)),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(RideUi.gutter, 4, RideUi.gutter, 24),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _card(_items[i]),
    );
  }

  Widget _card(Map<String, dynamic> n) {
    final title = (n['title'] ?? '').toString();
    final body = (n['body'] ?? '').toString();
    final image = (n['imageUrl'] ?? '').toString().trim();
    final personal = n['type'] == 'personal';
    final when = _when(n['sentAt']);
    return RideTile(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: RideUi.surface(context), shape: BoxShape.circle),
            child: Icon(personal ? Icons.person_outline_rounded : Icons.campaign_outlined,
                size: 19, color: RideUi.accent(context)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(title.isNotEmpty ? title : 'Gora Cabs',
                      style: RideUi.body(context, size: 14.5, weight: FontWeight.w800)),
                ),
                if (when.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(when, style: RideUi.caption(context, size: 11.5)),
                ],
              ]),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(body, style: RideUi.body(context, size: 13, weight: FontWeight.w500).copyWith(height: 1.4)),
              ],
            ]),
          ),
        ]),
        if (image.isNotEmpty) _NotificationImage(url: AppConfig.imageUrl(image)),
      ]),
    );
  }
}

/// The admin's image under a notification. A broken link hides the image
/// entirely rather than leaving an empty frame or an error glyph.
class _NotificationImage extends StatelessWidget {
  final String url;
  const _NotificationImage({required this.url});

  @override
  Widget build(BuildContext context) => Image.network(
        url,
        width: double.infinity,
        fit: BoxFit.cover,
        // The gap and rounding live here, not around the Image: when the image
        // fails, errorBuilder replaces all of it and nothing is left behind.
        frameBuilder: (_, child, frame, wasSync) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: wasSync || frame != null
                ? child
                : AspectRatio(aspectRatio: 16 / 9, child: Container(color: RideUi.divider(context))),
          ),
        ),
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
}
