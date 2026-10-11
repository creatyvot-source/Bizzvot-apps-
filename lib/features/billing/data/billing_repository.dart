import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/models/paged.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/idempotency.dart';
import '../domain/billing_models.dart';

class BillingRepository {
  BillingRepository(this._api);

  final ApiClient _api;

  /// `GET /organization/billing` (existing).
  Future<BillingSummary> billing() =>
      _api.get(Endpoints.billing, parse: BillingSummary.fromJson);

  /// Purchasable plans: PROPOSED `GET /catalog/plans`, falling back to the
  /// `plans` list inside the billing response when the catalogue route is
  /// unavailable (not deployed / no access).
  Future<List<Plan>> plans() async {
    try {
      final list = await _api.get(
        Endpoints.catalogPlans,
        parse: (d) =>
            Paged.parse(
                  d,
                  Plan.fromJson,
                  listKeys: const ['plans', 'items', 'data'],
                ).items
                .where((p) => p.id.isNotEmpty && p.active)
                .toList(growable: false),
      );
      if (list.isNotEmpty) return list;
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.unauthenticated ||
          e.kind == AppErrorKind.network) {
        rethrow;
      }
    }
    final b = await billing();
    return b.plans.where((p) => p.active).toList(growable: false);
  }

  /// Server price for [quantity] additional seats on [planId]
  /// (PROPOSED `POST /cart/quote`).
  Future<Quote> quoteSeats({required String planId, required int quantity}) =>
      _api.post(
        Endpoints.cartQuote,
        body: {
          'purpose': 'seats',
          'lines': [
            {
              'itemType': CatalogItemType.plan.name,
              'itemId': planId,
              'quantity': quantity,
            },
          ],
        },
        parse: Quote.fromJson,
      );

  /// Starts the seat subscription via the EXISTING `POST /organization/billing`
  /// `{ quantity, planId }`. Returns the hosted checkout, never a success.
  Future<PaymentSession> startSubscription({
    required int quantity,
    required String planId,
    required String idempotencyKey,
  }) => _api.post(
    Endpoints.billing,
    body: {'quantity': quantity, 'planId': planId},
    headers: {idempotencyHeader: idempotencyKey},
    parse: PaymentSession.fromJson,
  );
}

final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => BillingRepository(ref.watch(apiClientProvider)),
);
