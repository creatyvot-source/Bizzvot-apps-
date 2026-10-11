import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/providers.dart';
import '../../../shared/models/paged.dart';
import '../domain/app_notification.dart';

/// PROPOSED notification endpoints (plan §13.12).
class NotificationsRepository {
  NotificationsRepository(this._api);

  final ApiClient _api;

  /// `GET /notifications?page=&limit=`.
  Future<Paged<AppNotification>> notifications({int page = 1}) => _api.get(
        Endpoints.notifications,
        query: {'page': page, 'limit': 20},
        parse: (d) => Paged.parse(d, AppNotification.fromJson,
            listKeys: const ['notifications', 'items', 'docs', 'results', 'data']),
      );

  /// `POST /notifications/:id/read`.
  Future<void> markRead(String id) =>
      _api.post(Endpoints.notificationRead(id), parse: (_) {});
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);
