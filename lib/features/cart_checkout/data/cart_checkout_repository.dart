import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/providers.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/idempotency.dart';

/// PROPOSED cart/checkout endpoints (plan §12.3, §12.5).
///
/// The client only ever sends item identifiers and quantities. All amounts
/// come back from the server.
class CartCheckoutRepository {
  CartCheckoutRepository(this._api);

  final ApiClient _api;

  /// `POST /cart/quote` `{ lines: [{itemType,itemId,variantId?,addOnIds?,quantity}] }`.
  Future<Quote> quote(List<CartLine> lines) => _api.post(
        Endpoints.cartQuote,
        body: {'lines': [for (final l in lines) l.toRequestJson()]},
        parse: Quote.fromJson,
      );

  /// `POST /orders` — creates a pending order from the quoted lines.
  /// The server re-prices; [quoteId] only lets it detect a stale quote.
  Future<Order> createOrder({
    required List<CartLine> lines,
    required String idempotencyKey,
    String? quoteId,
  }) =>
      _api.post(
        Endpoints.orders,
        body: {
          'quoteId': ?quoteId,
          'lines': [for (final l in lines) l.toRequestJson()],
          'termsAccepted': true,
        },
        headers: {idempotencyHeader: idempotencyKey},
        parse: Order.fromJson,
      );

  /// `POST /orders/:id/payment` — starts a payment attempt and returns the
  /// hosted checkout URL. Not proof of payment.
  Future<PaymentSession> startPayment(
    String orderId, {
    required String idempotencyKey,
  }) =>
      _api.post(
        Endpoints.orderPayment(orderId),
        body: const <String, dynamic>{},
        headers: {idempotencyHeader: idempotencyKey},
        parse: PaymentSession.fromJson,
      );

  /// `GET /orders/:id`.
  Future<Order> order(String id) =>
      _api.get(Endpoints.order(id), parse: Order.fromJson);
}

final cartCheckoutRepositoryProvider = Provider<CartCheckoutRepository>(
  (ref) => CartCheckoutRepository(ref.watch(apiClientProvider)),
);
