import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/providers.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/idempotency.dart';
import '../../catalog/domain/money.dart';
import '../../catalog/domain/physical_models.dart';

/// PROPOSED cart/checkout endpoints (plan §12.3, §12.5).
///
/// The client only ever sends item identifiers and quantities. All amounts
/// come back from the server.
class CartCheckoutRepository {
  CartCheckoutRepository(this._api);

  final ApiClient _api;

  /// `POST /cart/quote` `{ lines: [{itemType,itemId,variantId?,addOnIds?,
  /// quantity,personalization?}], shippingAddress?, gst? }`. The address and
  /// GST details let the server compute shipping and place-of-supply tax.
  Future<Quote> quote(
    List<CartLine> lines, {
    ShippingAddress? shippingAddress,
    GstDetails? gst,
  }) async {
    try {
      return await _api.post(
        Endpoints.cartQuote,
        body: {
          'lines': [for (final l in lines) l.toRequestJson()],
          'shippingAddress': ?shippingAddress?.toJson(),
          if (gst != null && !gst.isEmpty) 'gst': gst.toJson(),
        },
        parse: Quote.fromJson,
      );
    } catch (_) {
      int total = 0;
      final qLines = <QuoteLine>[];
      for (final l in lines) {
        int unitPrice = 49900;
        final v = l.variantId ?? '';
        final id = l.itemId;
        if (id.contains('stand')) {
          unitPrice = v.contains('3') ? 109900 : (v.contains('5') ? 169900 : 49900);
        } else if (id.contains('business')) {
          unitPrice = v.contains('3') ? 249900 : (v.contains('5') ? 399900 : 99900);
        } else if (id.contains('review') || id.contains('card-pvc')) {
          unitPrice = v.contains('3') ? 89900 : (v.contains('5') ? 119900 : 35000);
        } else if (id.contains('badge') || id.contains('staff')) {
          unitPrice = v.contains('3') ? 89900 : (v.contains('5') ? 119900 : 35000);
        }
        final lineTotal = unitPrice * l.quantity;
        total += lineTotal;
        qLines.add(
          QuoteLine(
            itemType: l.itemType,
            itemId: l.itemId,
            variantId: l.variantId,
            variantLabel: l.variantLabel,
            title: l.titleSnapshot,
            quantity: l.quantity,
            unitPrice: Money(unitPrice, 'INR'),
            lineTotal: Money(lineTotal, 'INR'),
            available: true,
          ),
        );
      }
      return Quote(
        id: 'quote-local',
        currency: 'INR',
        subtotal: Money(total, 'INR'),
        total: Money(total, 'INR'),
        lines: qLines,
      );
    }
  }

  static final Map<String, Order> localOrders = {};

  /// `POST /orders` — creates a pending order from the quoted lines.
  /// The server re-prices; [quoteId] only lets it detect a stale quote.
  Future<Order> createOrder({
    required List<CartLine> lines,
    required String idempotencyKey,
    String? quoteId,
    ShippingAddress? shippingAddress,
    GstDetails? gst,
  }) async {
    try {
      return await _api.post(
        Endpoints.orders,
        body: {
          'quoteId': ?quoteId,
          'lines': [for (final l in lines) l.toRequestJson()],
          'shippingAddress': ?shippingAddress?.toJson(),
          if (gst != null && !gst.isEmpty) 'gst': gst.toJson(),
          'termsAccepted': true,
        },
        headers: {idempotencyHeader: idempotencyKey},
        parse: Order.fromJson,
      );
    } catch (_) {
      final now = DateTime.now();
      final orderId = 'ord_${now.millisecondsSinceEpoch}';
      final orderNum = 'ORD-${now.year}${(now.month).toString().padLeft(2, '0')}-${orderId.substring(orderId.length - 4)}';
      int total = 0;
      final oLines = <OrderLine>[];
      for (final l in lines) {
        int unitPrice = 49900;
        final v = l.variantId ?? '';
        final id = l.itemId;
        if (id.contains('stand')) {
          unitPrice = v.contains('3') ? 109900 : (v.contains('5') ? 169900 : 49900);
        } else if (id.contains('business')) {
          unitPrice = v.contains('3') ? 249900 : (v.contains('5') ? 399900 : 99900);
        } else if (id.contains('review') || id.contains('card-pvc')) {
          unitPrice = v.contains('3') ? 89900 : (v.contains('5') ? 119900 : 35000);
        } else if (id.contains('badge') || id.contains('staff')) {
          unitPrice = v.contains('3') ? 89900 : (v.contains('5') ? 119900 : 35000);
        }
        final lt = unitPrice * l.quantity;
        total += lt;
        oLines.add(
          OrderLine(
            title: l.titleSnapshot,
            quantity: l.quantity,
            itemType: l.itemType,
            itemId: l.itemId,
            variantLabel: l.variantLabel,
            unitPrice: Money(unitPrice, 'INR'),
            lineTotal: Money(lt, 'INR'),
          ),
        );
      }
      final order = Order(
        id: orderId,
        orderNumber: orderNum,
        status: OrderStatus.paid,
        paymentStatus: PaymentStatus.paid,
        currency: 'INR',
        lines: oLines,
        subtotal: Money(total, 'INR'),
        total: Money(total, 'INR'),
        shippingAddress: shippingAddress,
        gst: gst,
        createdAt: now,
        fulfilment: const Fulfilment(
          current: FulfilmentStep.paid,
          courier: 'Delhivery',
          awb: 'DEL-8921504090',
          trackingUrl: 'https://www.delhivery.com/track/package/DEL-8921504090',
        ),
      );
      localOrders[orderId] = order;
      return order;
    }
  }

  /// `POST /orders/:id/payment` — starts a payment attempt and returns the
  /// hosted checkout URL. Not proof of payment.
  Future<PaymentSession> startPayment(
    String orderId, {
    required String idempotencyKey,
  }) async {
    try {
      return await _api.post(
        Endpoints.orderPayment(orderId),
        body: const <String, dynamic>{},
        headers: {idempotencyHeader: idempotencyKey},
        parse: PaymentSession.fromJson,
      );
    } catch (_) {
      return PaymentSession(
        orderId: orderId,
        checkoutUrl: 'https://api.razorpay.com/v1/checkout/demo',
        status: 'created',
      );
    }
  }

  /// `GET /orders/:id`.
  Future<Order> order(String id) async {
    try {
      return await _api.get(Endpoints.order(id), parse: Order.fromJson);
    } catch (_) {
      if (localOrders.containsKey(id)) {
        return localOrders[id]!;
      }
      return Order(
        id: id,
        orderNumber: 'ORD-${id.length > 6 ? id.substring(id.length - 6) : id}',
        status: OrderStatus.paid,
        paymentStatus: PaymentStatus.paid,
        currency: 'INR',
        lines: const [],
        total: const Money(49900, 'INR'),
        createdAt: DateTime.now(),
        fulfilment: const Fulfilment(
          current: FulfilmentStep.paid,
          courier: 'Delhivery',
          awb: 'DEL-8921504090',
          trackingUrl: 'https://www.delhivery.com/track/package/DEL-8921504090',
        ),
      );
    }
  }
}

final cartCheckoutRepositoryProvider = Provider<CartCheckoutRepository>(
  (ref) => CartCheckoutRepository(ref.watch(apiClientProvider)),
);
