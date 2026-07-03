import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../bloc/notification_bloc.dart';

class NotificationPage extends StatelessWidget {
  static const route = '/notifications';
  const NotificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => NotifBloc()..add(LoadNotifEvent()),
      child: Scaffold(
        appBar: blueAppBar('Notifications'),
        backgroundColor: AppColors.cardBg,
        body: BlocBuilder<NotifBloc, NotifState>(
          builder: (context, state) {
            if (state is NotifLoading) return const AppLoader();
            if (state is NotifLoaded) return _NotifList(items: state.items);
            return const EmptyState(message: 'No notifications', icon: Icons.notifications_off);
          },
        ),
      ),
    );
  }
}

class _NotifList extends StatelessWidget {
  final List<NotificationModel> items;
  const _NotifList({required this.items});
  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.all(16),
    itemCount: items.length,
    separatorBuilder: (_, __) => const SizedBox(height: 8),
    itemBuilder: (_, i) => _NotifCard(notif: items[i]),
  );
}

class _NotifCard extends StatelessWidget {
  final NotificationModel notif;
  const _NotifCard({required this.notif});

  Color get _typeColor {
    switch (notif.type) {
      case 'ride': return AppColors.primary;
      case 'payment': return AppColors.green;
      case 'incentive': return AppColors.orange;
      case 'document': return AppColors.red;
      default: return AppColors.accent;
    }
  }

  IconData get _typeIcon {
    switch (notif.type) {
      case 'ride': return Icons.directions_car;
      case 'payment': return Icons.payment;
      case 'incentive': return Icons.celebration;
      case 'document': return Icons.folder;
      default: return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: notif.isRead ? AppColors.white : AppColors.primary.withOpacity(0.04),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: notif.isRead ? Colors.transparent : AppColors.primary.withOpacity(0.2)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _typeColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
        child: Icon(_typeIcon, color: _typeColor, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(notif.title, style: TextStyle(fontWeight: notif.isRead ? FontWeight.w600 : FontWeight.w800, fontSize: 13, color: AppColors.textDark)),
        const SizedBox(height: 3),
        Text(notif.body, style: TextStyle(fontSize: 12, color: AppColors.textGrey, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(notif.time, style: TextStyle(fontSize: 10, color: AppColors.textGrey)),
      ])),
      if (!notif.isRead)
        Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
    ]),
  );
}
