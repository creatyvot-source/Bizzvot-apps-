import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/providers.dart';
import '../../../shared/models/paged.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/idempotency.dart';

/// PROPOSED subscription endpoints (plan §12.5, §13.10).
class SubscriptionsRepository {
  SubscriptionsRepository(this._api);

  final ApiClient _api;

  /// `GET /subscriptions`.
  Future<Paged<Subscription>> subscriptions({int page = 1}) => _api.get(
    Endpoints.subscriptions,
    query: {'page': page, 'limit': 20},
    parse: (d) => Paged.parse(
      d,
      Subscription.fromJson,
      listKeys: const ['subscriptions', 'items', 'docs', 'results', 'data'],
    ),
  );

  /// `GET /subscriptions/:id`.
  Future<Subscription> subscription(String id) =>
      _api.get(Endpoints.subscription(id), parse: Subscription.fromJson);

  /// `POST /subscriptions/:id/renew` — starts a renewal payment attempt.
  Future<PaymentSession> renew(String id, {required String idempotencyKey}) =>
      _api.post(
        Endpoints.subscriptionRenew(id),
        body: const <String, dynamic>{},
        headers: {idempotencyHeader: idempotencyKey},
        parse: PaymentSession.fromJson,
      );
}

final subscriptionsRepositoryProvider = Provider<SubscriptionsRepository>(
  (ref) => SubscriptionsRepository(ref.watch(apiClientProvider)),
);
