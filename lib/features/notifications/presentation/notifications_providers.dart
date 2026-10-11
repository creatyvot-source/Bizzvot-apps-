import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/paged.dart';
import '../../catalog/presentation/common/paged_list.dart';
import '../data/notifications_repository.dart';
import '../domain/app_notification.dart';

class NotificationsController extends PagedNotifier<AppNotification> {
  @override
  Future<Paged<AppNotification>> fetchPage(int page) =>
      ref.read(notificationsRepositoryProvider).notifications(page: page);

  /// Optimistically marks [n] read; reverts if the server rejects it.
  Future<void> markRead(AppNotification n) async {
    if (n.isRead || n.id.isEmpty) return;
    replaceWhere((x) => x.id == n.id, (x) => x.markedRead(DateTime.now()));
    try {
      await ref.read(notificationsRepositoryProvider).markRead(n.id);
    } catch (_) {
      if (ref.mounted) replaceWhere((x) => x.id == n.id, (_) => n);
      rethrow;
    }
  }
}

final notificationsProvider =
    AsyncNotifierProvider.autoDispose<
      NotificationsController,
      PagedList<AppNotification>
    >(NotificationsController.new);

/// Unread count among loaded notifications.
final unreadNotificationsCountProvider = Provider.autoDispose<int>((ref) {
  final list = ref.watch(notificationsProvider).value;
  return list?.items.where((n) => !n.isRead).length ?? 0;
});
