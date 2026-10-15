import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../services/driver_api_service.dart';
import '../../../models/models.dart';

abstract class NotifEvent extends Equatable {
  @override List<Object?> get props => [];
}
class LoadNotifEvent extends NotifEvent {}

abstract class NotifState extends Equatable {
  @override List<Object?> get props => [];
}
class NotifInitial extends NotifState {}
class NotifLoading extends NotifState {}
class NotifLoaded extends NotifState {
  final List<NotificationModel> items;
  NotifLoaded(this.items);
  @override List<Object?> get props => [items];
}

class NotifBloc extends Bloc<NotifEvent, NotifState> {
  NotifBloc() : super(NotifInitial()) {
    on<LoadNotifEvent>(_onLoad);
  }
  Future<void> _onLoad(LoadNotifEvent e, Emitter emit) async {
    emit(NotifLoading());
    try {
      final res = await DriverApiService.getNotifications();
      final raw = (res['notifications'] as List?) ?? const [];
      emit(NotifLoaded(raw.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return NotificationModel(
          id: (m['id'] ?? '').toString(),
          title: (m['title'] ?? '').toString(),
          body: (m['body'] ?? '').toString(),
          time: _ago(m['sentAt']),
          type: (m['type'] ?? 'broadcast').toString(),
          // The backend does not track per-driver read state yet, so nothing
          // is claimed to be read rather than inventing a flag.
          isRead: false,
        );
      }).toList()));
    } catch (_) {
      // An empty feed is honest; a mock one is not.
      emit(NotifLoaded(const []));
    }
  }

  static String _ago(dynamic iso) {
    final t = DateTime.tryParse((iso ?? '').toString())?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }
}
