import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../mock/mock_data.dart';
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
    final items = await MockNotificationService.getAll();
    emit(NotifLoaded(items));
  }
}
