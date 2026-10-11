import '../../../core/utilities/json.dart';
import 'catalog_models.dart';
import 'formatting.dart';
import 'money.dart';

// ---------------------------------------------------------------------------
// Cart (client side — identifiers and quantities only, never prices)
// ---------------------------------------------------------------------------

/// A line in the client-side cart. Holds **no prices**: the server quote is
/// the only source of amounts. [titleSnapshot] is for display only.
class CartLine {
  const CartLine({
    required this.itemType,
    required this.itemId,
    required this.quantity,
    required this.titleSnapshot,
    this.variantId,
    this.variantLabel,
    this.addOnIds = const [],
    this.paymentPolicy,
  });

  final CatalogItemType itemType;
  final String itemId;
  final String? variantId;
  final String? variantLabel;
  final List<String> addOnIds;
  final int quantity;
  final String titleSnapshot;

  /// Classification captured when added; the quote's value wins if present.
  final PaymentPolicy? paymentPolicy;

  static const maxQuantity = 99;

  /// Identity of the purchasable configuration (same key = merge lines).
  String get key {
    final addOns = [...addOnIds]..sort();
    return '${itemType.wire}|$itemId|${variantId ?? ''}|${addOns.join(',')}';
  }

  CartLine copyWith({int? quantity}) => CartLine(
        itemType: itemType,
        itemId: itemId,
        variantId: variantId,
        variantLabel: variantLabel,
        addOnIds: addOnIds,
        quantity: quantity ?? this.quantity,
        titleSnapshot: titleSnapshot,
        paymentPolicy: paymentPolicy,
      );

  /// Body for `POST /cart/quote` and `POST /orders`. No amounts, no titles.
  Json toRequestJson() => compact({
        'itemType': itemType.wire,
        'itemId': itemId,
        'variantId': variantId,
        if (addOnIds.isNotEmpty) 'addOnIds': addOnIds,
        'quantity': quantity,
      });

  bool matches({
    required String itemId,
    String? itemType,
    String? variantId,
  }) =>
      this.itemId == itemId &&
      (itemType == null ||
          CatalogItemType.parse(itemType) == this.itemType) &&
      (variantId == null || this.variantId == variantId);
}

// ---------------------------------------------------------------------------
// Quote (server)
// ---------------------------------------------------------------------------

/// Labeled amount: discount, tax or fee line.
class Adjustment {
  const Adjustment({required this.label, required this.amount, this.rate});
  final String label;
  final Money amount;

  /// Display string such as "18%"; never used for maths.
  final String? rate;

  static List<Adjustment> listFrom(Object? raw, {String? currency, String fallbackLabel = 'Adjustment'}) {
    final out = <Adjustment>[];
    for (final j in asJsonList(raw)) {
      final amount = Money.firstField(j, const ['amount', 'value', 'total'],
          currency: currency);
      if (amount == null) continue;
      final rate = j['rate'] ?? j['percent'] ?? j['percentage'];
      out.add(Adjustment(
        label: strOr(
          j['label'] ?? j['name'] ?? j['title'] ?? j['code'] ?? j['type'],
          fallbackLabel,
        ),
        amount: amount,
        rate: rate == null ? null : (rate is num ? '$rate%' : str(rate)),
      ));
    }
    return out;
  }
}

class QuoteLine {
  const QuoteLine({
    required this.itemType,
    required this.itemId,
    required this.title,
    required this.quantity,
    this.variantId,
    this.variantLabel,
    this.unitPrice,
    this.lineTotal,
    this.available = true,
    this.issue,
    this.paymentPolicy,
  });

  final CatalogItemType itemType;
  final String itemId;
  final String? variantId;
  final String title;
  final String? variantLabel;
  final int quantity;
  final Money? unitPrice;
  final Money? lineTotal;
  final bool available;

  /// Server explanation when the line cannot be purchased.
  final String? issue;
  final PaymentPolicy? paymentPolicy;

  factory QuoteLine.fromJson(Object? raw, {String? currency}) {
    final j = asJson(raw);
    final item = asJson(j['item']);
    final status = wireKey(str(j['status']));
    final issue = str(j['issue'] ?? j['error'] ?? j['reason'] ?? j['message']);
    return QuoteLine(
      itemType: CatalogItemType.parse(j['itemType'] ?? j['type'] ?? item['type']),
      itemId: strOr(j['itemId'] ?? (item.isEmpty ? null : idOf(item))),
      variantId: str(j['variantId']),
      title: strOr(j['title'] ?? j['name'] ?? item['title'] ?? item['name'], 'Item'),
      variantLabel: str(j['variantName'] ?? j['variantLabel']),
      quantity: intOr(j['quantity'], 1),
      unitPrice: Money.firstField(j, const ['unitPrice', 'price'], currency: currency),
      lineTotal: Money.firstField(j, const ['lineTotal', 'total', 'amount'],
          currency: currency),
      available: boolOrNull(j['available'] ?? j['valid']) ??
          !(status == 'unavailable' || status == 'invalid' || issue != null),
      issue: issue,
      paymentPolicy: PaymentPolicy.tryParse(j['paymentPolicy'] ?? item['paymentPolicy']),
    );
  }
}

/// A line the server refused (inactive, out of stock, not eligible…).
class InvalidLine {
  const InvalidLine({
    required this.itemId,
    required this.reason,
    this.itemType,
    this.variantId,
  });

  final String itemId;
  final String? itemType;
  final String? variantId;
  final String reason;

  factory InvalidLine.fromJson(Object? raw) {
    final j = asJson(raw);
    return InvalidLine(
      itemId: strOr(j['itemId'] ?? j['id']),
      itemType: str(j['itemType'] ?? j['type']),
      variantId: str(j['variantId']),
      reason: strOr(
        j['reason'] ?? j['message'] ?? j['error'],
        'This item is no longer available.',
      ),
    );
  }
}

/// Authoritative cart pricing from `POST /cart/quote`.
class Quote {
  const Quote({
    required this.id,
    required this.currency,
    required this.lines,
    this.subtotal,
    this.discounts = const [],
    this.discountTotal,
    this.taxes = const [],
    this.taxTotal,
    this.shipping,
    this.total,
    this.invalidLines = const [],
    this.expiresAt,
    this.checkoutAllowed,
    this.termsUrl,
    this.notes = const [],
  });

  final String? id;
  final String currency;
  final List<QuoteLine> lines;
  final Money? subtotal;
  final List<Adjustment> discounts;
  final Money? discountTotal;
  final List<Adjustment> taxes;
  final Money? taxTotal;
  final Money? shipping;
  final Money? total;
  final List<InvalidLine> invalidLines;
  final DateTime? expiresAt;

  /// Explicit server flag; null when not sent.
  final bool? checkoutAllowed;
  final String? termsUrl;
  final List<String> notes;

  bool get hasUnavailable =>
      invalidLines.isNotEmpty || lines.any((l) => !l.available);

  /// Checkout requires a server total and no unavailable lines.
  bool get canCheckout =>
      (checkoutAllowed ?? true) && !hasUnavailable && total != null && lines.isNotEmpty;

  /// Policy classifications across lines (server value, else cart snapshot).
  bool blocksInApp(List<CartLine> cart) {
    for (final l in lines) {
      if (l.paymentPolicy?.blocksCheckout ?? false) return true;
    }
    return cart.any((c) => c.paymentPolicy?.blocksCheckout ?? false);
  }

  factory Quote.fromJson(Object? raw) {
    var j = asJson(raw);
    if (j['quote'] is Map) j = asJson(j['quote']);
    final totals = asJson(j['totals']);
    final currency = Money.normalizeCurrency(j['currency'] ?? totals['currency']);
    final cur = currency.isEmpty ? null : currency;
    Money? total(List<String> keys) =>
        Money.firstField(totals, keys, currency: cur) ??
        Money.firstField(j, keys, currency: cur);
    final invalid = [
      ...asJsonList(j['invalidLines']),
      ...asJsonList(j['unavailable']),
      ...asJsonList(j['unavailableLines']),
    ].map(InvalidLine.fromJson).toList(growable: false);
    return Quote(
      id: str(j['quoteId']) ?? (idOf(j).isEmpty ? null : idOf(j)),
      currency: currency,
      lines: asJsonList(j['lines'] ?? j['items'])
          .map((l) => QuoteLine.fromJson(l, currency: cur))
          .toList(growable: false),
      subtotal: total(const ['subtotal', 'subTotal']),
      discounts: Adjustment.listFrom(j['discounts'], currency: cur, fallbackLabel: 'Discount'),
      discountTotal: total(const ['discountTotal', 'discount']),
      taxes: Adjustment.listFrom(j['taxes'] ?? j['taxLines'], currency: cur, fallbackLabel: 'Tax'),
      taxTotal: total(const ['taxTotal', 'tax']),
      shipping: total(const ['shipping', 'shippingTotal']),
      total: total(const ['total', 'grandTotal', 'amountDue']),
      invalidLines: invalid,
      expiresAt: dateOrNull(j['expiresAt']),
      checkoutAllowed: boolOrNull(j['checkoutAllowed'] ?? j['valid'] ?? j['canCheckout']),
      termsUrl: str(j['termsUrl']),
      notes: strList(j['notes'] ?? j['messages']),
    );
  }
}

// ---------------------------------------------------------------------------
// Orders & payments (server)
// ---------------------------------------------------------------------------

/// Order lifecycle (Appendix B). Unknown values map to [unknown] and the raw
/// string is kept on [Order.statusRaw] for display.
enum OrderStatus {
  draft,
  pendingPayment,
  paid,
  processing,
  fulfilled,
  completed,
  paymentFailed,
  cancelled,
  refunded,
  expired,
  unknown;

  static OrderStatus parse(Object? v) => switch (wireKey(str(v))) {
        'draft' => OrderStatus.draft,
        'pending_payment' || 'pending' || 'awaiting_payment' || 'created' =>
          OrderStatus.pendingPayment,
        'paid' => OrderStatus.paid,
        'processing' || 'in_progress' => OrderStatus.processing,
        'fulfilled' || 'delivered' || 'shipped' => OrderStatus.fulfilled,
        'completed' || 'complete' => OrderStatus.completed,
        'payment_failed' || 'failed' => OrderStatus.paymentFailed,
        'cancelled' || 'canceled' => OrderStatus.cancelled,
        'refunded' => OrderStatus.refunded,
        'expired' => OrderStatus.expired,
        _ => OrderStatus.unknown,
      };

  String get wire => switch (this) {
        OrderStatus.draft => 'draft',
        OrderStatus.pendingPayment => 'pending_payment',
        OrderStatus.paid => 'paid',
        OrderStatus.processing => 'processing',
        OrderStatus.fulfilled => 'fulfilled',
        OrderStatus.completed => 'completed',
        OrderStatus.paymentFailed => 'payment_failed',
        OrderStatus.cancelled => 'cancelled',
        OrderStatus.refunded => 'refunded',
        OrderStatus.expired => 'expired',
        OrderStatus.unknown => 'unknown',
      };

  String get label => humanize(wire);
}

enum PaymentStatus {
  pending,
  processing,
  paid,
  failed,
  cancelled,
  expired,
  refunded,
  partiallyRefunded,
  unknown;

  static PaymentStatus parse(Object? v) => switch (wireKey(str(v))) {
        'pending' || 'created' || 'unpaid' || 'awaiting_payment' ||
        'requires_payment' || 'pending_payment' =>
          PaymentStatus.pending,
        'processing' || 'authorized' || 'authorised' || 'in_progress' =>
          PaymentStatus.processing,
        'paid' || 'captured' || 'succeeded' || 'success' || 'successful' ||
        'completed' =>
          PaymentStatus.paid,
        'failed' || 'payment_failed' || 'declined' || 'error' =>
          PaymentStatus.failed,
        'cancelled' || 'canceled' => PaymentStatus.cancelled,
        'expired' => PaymentStatus.expired,
        'refunded' => PaymentStatus.refunded,
        'partially_refunded' || 'partial_refund' =>
          PaymentStatus.partiallyRefunded,
        _ => PaymentStatus.unknown,
      };

  String get label => switch (this) {
        PaymentStatus.partiallyRefunded => 'Partially refunded',
        _ => humanize(name),
      };
}

/// What the payment status screen shows, derived only from server state.
enum PaymentOutcome {
  pending,
  processing,
  paid,
  failed,
  cancelled,
  expired,
  refunded;

  bool get isTerminal => switch (this) {
        PaymentOutcome.pending || PaymentOutcome.processing => false,
        _ => true,
      };
}

class TaxLine {
  const TaxLine({required this.label, this.rate, this.amount});
  final String label;
  final String? rate;
  final Money? amount;

  static List<TaxLine> listFrom(Object? raw, {String? currency}) {
    if (raw is Map) {
      final j = asJson(raw);
      if (j['lines'] is List || j['items'] is List) {
        return listFrom(j['lines'] ?? j['items'], currency: currency);
      }
      return [_one(j, currency)].whereType<TaxLine>().toList();
    }
    return asJsonList(raw)
        .map((j) => _one(j, currency))
        .whereType<TaxLine>()
        .toList(growable: false);
  }

  static TaxLine? _one(Json j, String? currency) {
    final amount = Money.firstField(j, const ['amount', 'value', 'total'],
        currency: currency);
    final label = str(j['label'] ?? j['name'] ?? j['type'] ?? j['code']);
    if (amount == null && label == null) return null;
    final rate = j['rate'] ?? j['percent'];
    return TaxLine(
      label: label ?? 'Tax',
      rate: rate == null ? null : (rate is num ? '$rate%' : str(rate)),
      amount: amount,
    );
  }
}

/// Immutable snapshot line of an order.
class OrderLine {
  const OrderLine({
    required this.title,
    required this.quantity,
    this.itemType,
    this.itemId,
    this.variantLabel,
    this.unitPrice,
    this.lineTotal,
    this.tax,
  });

  final String title;
  final int quantity;
  final CatalogItemType? itemType;
  final String? itemId;
  final String? variantLabel;
  final Money? unitPrice;
  final Money? lineTotal;
  final Money? tax;

  factory OrderLine.fromJson(Object? raw, {String? currency}) {
    final j = asJson(raw);
    final t = str(j['itemType'] ?? j['type']);
    return OrderLine(
      title: strOr(j['title'] ?? j['name'], 'Item'),
      quantity: intOr(j['quantity'], 1),
      itemType: t == null ? null : CatalogItemType.parse(t),
      itemId: str(j['itemId']),
      variantLabel: str(j['variantName'] ?? j['variantLabel'] ?? j['sku']),
      unitPrice: Money.firstField(j, const ['unitPrice', 'price'], currency: currency),
      lineTotal: Money.firstField(j, const ['lineTotal', 'total', 'amount'],
          currency: currency),
      tax: Money.firstField(j, const ['tax', 'taxAmount'], currency: currency),
    );
  }
}

class Order {
  const Order({
    required this.id,
    required this.status,
    required this.paymentStatus,
    this.statusRaw,
    this.paymentStatusRaw,
    this.orderNumber,
    this.currency = '',
    this.lines = const [],
    this.subtotal,
    this.discountTotal,
    this.taxTotal,
    this.shipping,
    this.total,
    this.taxLines = const [],
    this.fulfilmentStatus,
    this.refundStatus,
    this.refundedAmount,
    this.subscriptionId,
    this.invoiceId,
    this.canRetryPayment,
    this.createdAt,
    this.updatedAt,
    this.failureReason,
  });

  final String id;
  final String? orderNumber;
  final OrderStatus status;
  final String? statusRaw;
  final PaymentStatus paymentStatus;
  final String? paymentStatusRaw;
  final String currency;
  final List<OrderLine> lines;
  final Money? subtotal;
  final Money? discountTotal;
  final Money? taxTotal;
  final Money? shipping;
  final Money? total;
  final List<TaxLine> taxLines;
  final String? fulfilmentStatus;
  final String? refundStatus;
  final Money? refundedAmount;
  final String? subscriptionId;
  final String? invoiceId;

  /// Server flag; null when not sent.
  final bool? canRetryPayment;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Safe, user-facing failure reason from the server, if any.
  final String? failureReason;

  String get displayNumber => orderNumber ?? (id.length > 8 ? id.substring(id.length - 8) : id);

  String get statusLabel =>
      status == OrderStatus.unknown ? humanize(statusRaw) : status.label;

  String get paymentStatusLabel => paymentStatus == PaymentStatus.unknown
      ? humanize(paymentStatusRaw, fallback: 'Unknown')
      : paymentStatus.label;

  /// Payment state derived only from server-reported status fields.
  PaymentOutcome get paymentOutcome {
    if (paymentStatus == PaymentStatus.refunded ||
        status == OrderStatus.refunded) {
      return PaymentOutcome.refunded;
    }
    if (paymentStatus == PaymentStatus.paid ||
        paymentStatus == PaymentStatus.partiallyRefunded ||
        status == OrderStatus.paid ||
        status == OrderStatus.fulfilled ||
        status == OrderStatus.completed) {
      return PaymentOutcome.paid;
    }
    if (paymentStatus == PaymentStatus.failed ||
        status == OrderStatus.paymentFailed) {
      return PaymentOutcome.failed;
    }
    if (status == OrderStatus.cancelled ||
        paymentStatus == PaymentStatus.cancelled) {
      return PaymentOutcome.cancelled;
    }
    if (status == OrderStatus.expired ||
        paymentStatus == PaymentStatus.expired) {
      return PaymentOutcome.expired;
    }
    if (paymentStatus == PaymentStatus.processing ||
        status == OrderStatus.processing) {
      return PaymentOutcome.processing;
    }
    return PaymentOutcome.pending;
  }

  /// Retry is offered for failed/pending orders unless the server says no.
  bool get retryPaymentAllowed =>
      canRetryPayment ??
      (paymentOutcome == PaymentOutcome.failed ||
          paymentOutcome == PaymentOutcome.pending);

  factory Order.fromJson(Object? raw) {
    var j = asJson(raw);
    if (j['order'] is Map) j = {...j, ...asJson(j['order'])};
    final totals = asJson(j['totals']);
    final currency = Money.normalizeCurrency(j['currency'] ?? totals['currency']);
    final cur = currency.isEmpty ? null : currency;
    Money? total(List<String> keys) =>
        Money.firstField(totals, keys, currency: cur) ??
        Money.firstField(j, keys, currency: cur);
    final payment = asJson(j['payment']);
    final fulfilment = j['fulfilment'] ?? j['fulfillment'];
    final refund = j['refund'];
    final subscription = j['subscription'];
    final invoice = j['invoice'];
    final statusRaw = str(j['status']);
    final payRaw = str(j['paymentStatus'] ?? payment['status']);
    return Order(
      id: idOf(j).isEmpty ? strOr(j['orderId']) : idOf(j),
      orderNumber: str(j['orderNumber'] ?? j['number']),
      status: OrderStatus.parse(statusRaw),
      statusRaw: statusRaw,
      paymentStatus: PaymentStatus.parse(payRaw),
      paymentStatusRaw: payRaw,
      currency: currency,
      lines: asJsonList(j['itemsSnapshot'] ?? j['items'] ?? j['lines'])
          .map((l) => OrderLine.fromJson(l, currency: cur))
          .toList(growable: false),
      subtotal: total(const ['subtotal', 'subTotal']),
      discountTotal: total(const ['discountTotal', 'discount']),
      taxTotal: total(const ['taxTotal', 'tax']),
      shipping: total(const ['shipping', 'shippingTotal']),
      total: total(const ['total', 'grandTotal']),
      taxLines: TaxLine.listFrom(j['taxSnapshot'] ?? j['taxes'], currency: cur),
      fulfilmentStatus: fulfilment is Map
          ? str(asJson(fulfilment)['status'])
          : str(fulfilment ?? j['fulfilmentStatus'] ?? j['fulfillmentStatus']),
      refundStatus: refund is Map
          ? str(asJson(refund)['status'])
          : str(refund ?? j['refundStatus']),
      refundedAmount: refund is Map
          ? Money.firstField(asJson(refund), const ['amount'], currency: cur)
          : Money.field(j, 'refundedAmount', currency: cur),
      subscriptionId: subscription is Map
          ? idOf(asJson(subscription))
          : str(subscription ?? j['subscriptionId']),
      invoiceId: invoice is Map ? idOf(asJson(invoice)) : str(invoice ?? j['invoiceId']),
      canRetryPayment: boolOrNull(j['canRetryPayment'] ?? payment['canRetry']),
      createdAt: dateOrNull(j['createdAt']),
      updatedAt: dateOrNull(j['updatedAt']),
      failureReason: str(j['failureReason'] ?? payment['failureReason']),
    );
  }
}

/// Response of `POST /orders/:id/payment`, `POST /subscriptions/:id/renew`
/// and `POST /organization/billing`: a payment attempt plus, usually, a
/// hosted checkout URL. It is **never** proof of payment.
class PaymentSession {
  const PaymentSession({
    this.checkoutUrl,
    this.orderId,
    this.subscriptionId,
    this.attemptId,
    this.status,
  });

  final String? checkoutUrl;
  final String? orderId;
  final String? subscriptionId;
  final String? attemptId;
  final String? status;

  /// The checkout URL if, and only if, it is an absolute https URL.
  Uri? get safeCheckoutUri => safeHttpsUri(checkoutUrl);

  factory PaymentSession.fromJson(Object? raw) {
    final j = asJson(raw);
    String? url;
    String? attemptId;
    String? status;
    for (final src in [
      j,
      asJson(j['payment']),
      asJson(j['paymentAttempt']),
      asJson(j['checkout']),
      asJson(j['subscription']),
    ]) {
      url ??= str(src['checkoutUrl'] ?? src['paymentUrl'] ?? src['shortUrl'] ??
          src['hostedUrl'] ?? src['url']);
      status ??= str(src['status']);
    }
    final attempt = asJson(j['paymentAttempt'] ?? j['payment']);
    attemptId = str(j['attemptId']) ?? (attempt.isEmpty ? null : str(attempt['id'] ?? attempt['_id']));
    final order = j['order'];
    final sub = j['subscription'];
    return PaymentSession(
      checkoutUrl: url,
      orderId: str(j['orderId']) ?? (order is Map ? idOf(asJson(order)) : str(order)),
      subscriptionId: str(j['subscriptionId']) ??
          (sub is Map ? idOf(asJson(sub)) : str(sub)),
      attemptId: attemptId,
      status: status,
    );
  }
}

/// Returns [raw] as a Uri only when it is absolute `https` with a host.
Uri? safeHttpsUri(String? raw) {
  if (raw == null) return null;
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri;
}

// ---------------------------------------------------------------------------
// Invoices
// ---------------------------------------------------------------------------

class Invoice {
  const Invoice({
    required this.id,
    this.invoiceNumber,
    this.status,
    this.orderId,
    this.subscriptionId,
    this.currency = '',
    this.lines = const [],
    this.subtotal,
    this.discountTotal,
    this.taxTotal,
    this.total,
    this.amountPaid,
    this.taxDetails = const [],
    this.issuedAt,
    this.dueAt,
    this.fileUrl,
    this.taxId,
  });

  final String id;
  final String? invoiceNumber;
  final String? status;
  final String? orderId;
  final String? subscriptionId;
  final String currency;
  final List<OrderLine> lines;
  final Money? subtotal;
  final Money? discountTotal;
  final Money? taxTotal;
  final Money? total;
  final Money? amountPaid;
  final List<TaxLine> taxDetails;
  final DateTime? issuedAt;
  final DateTime? dueAt;
  final String? fileUrl;

  /// Seller/buyer GST/VAT registration shown on the invoice, if any.
  final String? taxId;

  String get displayNumber => invoiceNumber ?? id;
  String get statusLabel => humanize(status, fallback: 'Issued');

  /// The PDF link if, and only if, it is an absolute https URL.
  Uri? get safeFileUri => safeHttpsUri(fileUrl);

  factory Invoice.fromJson(Object? raw) {
    var j = asJson(raw);
    if (j['invoice'] is Map) j = {...j, ...asJson(j['invoice'])};
    final totals = asJson(j['totals']);
    final currency = Money.normalizeCurrency(j['currency'] ?? totals['currency']);
    final cur = currency.isEmpty ? null : currency;
    Money? total(List<String> keys) =>
        Money.firstField(totals, keys, currency: cur) ??
        Money.firstField(j, keys, currency: cur);
    final order = j['order'];
    final sub = j['subscription'];
    return Invoice(
      id: idOf(j),
      invoiceNumber: str(j['invoiceNumber'] ?? j['number']),
      status: str(j['status']),
      orderId: str(j['orderId']) ?? (order is Map ? idOf(asJson(order)) : str(order)),
      subscriptionId:
          str(j['subscriptionId']) ?? (sub is Map ? idOf(asJson(sub)) : str(sub)),
      currency: currency,
      lines: asJsonList(j['lines'] ?? j['items'] ?? j['itemsSnapshot'])
          .map((l) => OrderLine.fromJson(l, currency: cur))
          .toList(growable: false),
      subtotal: total(const ['subtotal', 'subTotal']),
      discountTotal: total(const ['discountTotal', 'discount']),
      taxTotal: total(const ['taxTotal', 'tax']),
      total: total(const ['total', 'grandTotal']),
      amountPaid: total(const ['amountPaid', 'paid']),
      taxDetails: TaxLine.listFrom(j['taxDetails'] ?? j['taxes'], currency: cur),
      issuedAt: dateOrNull(j['issuedAt'] ?? j['createdAt']),
      dueAt: dateOrNull(j['dueAt'] ?? j['dueDate']),
      fileUrl: str(j['fileUrl'] ?? j['pdfUrl'] ?? j['url']),
      taxId: str(j['taxId'] ?? j['gstin']),
    );
  }
}

// ---------------------------------------------------------------------------
// Subscriptions
// ---------------------------------------------------------------------------

enum SubscriptionStatus {
  pending,
  trialing,
  active,
  pastDue,
  gracePeriod,
  cancelled,
  expired,
  unknown;

  static SubscriptionStatus parse(Object? v) => switch (wireKey(str(v))) {
        'pending' || 'incomplete' || 'created' || 'pending_payment' =>
          SubscriptionStatus.pending,
        'trial' || 'trialing' || 'in_trial' => SubscriptionStatus.trialing,
        'active' => SubscriptionStatus.active,
        'past_due' || 'payment_failed' || 'unpaid' => SubscriptionStatus.pastDue,
        'grace_period' || 'grace' || 'in_grace' => SubscriptionStatus.gracePeriod,
        'cancelled' || 'canceled' => SubscriptionStatus.cancelled,
        'expired' || 'ended' => SubscriptionStatus.expired,
        _ => SubscriptionStatus.unknown,
      };

  String get label => switch (this) {
        SubscriptionStatus.pastDue => 'Past due',
        SubscriptionStatus.gracePeriod => 'Grace period',
        SubscriptionStatus.trialing => 'Trial',
        _ => humanize(name),
      };

  /// Plain-language explanation for owners.
  String get explanation => switch (this) {
        SubscriptionStatus.pending =>
          'Waiting for payment confirmation. Seats are added only after the '
              'payment is verified.',
        SubscriptionStatus.trialing =>
          'You are on a free trial. Choose a plan before the trial ends to keep '
              'your cards active.',
        SubscriptionStatus.active => 'Your subscription is active.',
        SubscriptionStatus.pastDue =>
          'The last renewal payment did not go through. Renew now to avoid '
              'interruption to your cards.',
        SubscriptionStatus.gracePeriod =>
          'Your subscription has lapsed but your cards stay active until the '
              'grace period ends. Renew to keep them active.',
        SubscriptionStatus.cancelled =>
          'This subscription has been cancelled.',
        SubscriptionStatus.expired =>
          'This subscription has expired. Cards covered by it may be disabled '
              'until you renew.',
        SubscriptionStatus.unknown =>
          'We could not determine the status of this subscription.',
      };
}

class Subscription {
  const Subscription({
    required this.id,
    required this.status,
    this.statusRaw,
    this.planId,
    this.planName,
    this.planVersion,
    this.billingPeriod,
    this.quantity,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.nextRenewalAt,
    this.graceUntil,
    this.cancelAtPeriodEnd = false,
    this.autoRenew,
    this.canRenew,
    this.renewalBlockedReason,
    this.renewalPrice,
    this.renewalInProgress = false,
    this.lastOrderId,
  });

  final String id;
  final SubscriptionStatus status;
  final String? statusRaw;
  final String? planId;
  final String? planName;
  final String? planVersion;
  final String? billingPeriod;
  final int? quantity;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final DateTime? nextRenewalAt;
  final DateTime? graceUntil;
  final bool cancelAtPeriodEnd;
  final bool? autoRenew;

  /// Explicit server eligibility flag; null when not sent.
  final bool? canRenew;
  final String? renewalBlockedReason;

  /// Server-quoted renewal amount, display only.
  final Money? renewalPrice;

  /// True while the server reports a renewal payment awaiting verification.
  final bool renewalInProgress;
  final String? lastOrderId;

  String get statusLabel =>
      status == SubscriptionStatus.unknown ? humanize(statusRaw) : status.label;

  String get title => planName ?? 'Subscription';

  /// Server flag wins. Without one, only lapsed/at-risk subscriptions are
  /// treated as renewable (the server still validates the request).
  bool get renewable {
    if (renewalInProgress) return false;
    if (canRenew != null) return canRenew!;
    return switch (status) {
      SubscriptionStatus.pastDue ||
      SubscriptionStatus.gracePeriod ||
      SubscriptionStatus.expired =>
        true,
      _ => false,
    };
  }

  factory Subscription.fromJson(Object? raw) {
    var j = asJson(raw);
    if (j['subscription'] is Map) j = {...j, ...asJson(j['subscription'])};
    final plan = j['plan'] ?? j['planVersion'];
    final planJson = asJson(plan);
    final renewal = asJson(j['renewal']);
    final actions = asJson(j['actions']);
    final statusRaw = str(j['status']);
    final renewalState = wireKey(str(renewal['status'] ?? j['renewalStatus']));
    return Subscription(
      id: idOf(j),
      status: SubscriptionStatus.parse(statusRaw),
      statusRaw: statusRaw,
      planId: str(j['planId']) ?? (plan is Map ? str(planJson['planId']) ?? idOf(planJson) : null),
      planName: str(j['planName']) ?? (plan is Map ? str(planJson['name']) : str(plan)),
      planVersion: str(j['planVersionId'] ?? j['planVersionName']) ??
          (plan is Map ? str(planJson['version']) : null),
      billingPeriod: str(j['billingPeriod'] ?? planJson['billingPeriod']),
      quantity: intOrNull(j['quantity'] ?? j['seats']),
      currentPeriodStart: dateOrNull(j['currentPeriodStart']),
      currentPeriodEnd: dateOrNull(j['currentPeriodEnd']),
      nextRenewalAt: dateOrNull(j['nextRenewalAt'] ?? j['renewsAt']),
      graceUntil: dateOrNull(j['graceUntil'] ?? j['gracePeriodEndsAt']),
      cancelAtPeriodEnd: boolOr(j['cancelAtPeriodEnd']),
      autoRenew: boolOrNull(j['autoRenew']),
      canRenew: boolOrNull(j['canRenew'] ?? j['renewable'] ??
          j['renewalEligible'] ?? actions['renew'] ?? renewal['eligible']),
      renewalBlockedReason: str(j['renewalBlockedReason'] ?? renewal['reason']),
      renewalPrice: Money.firstField(j, const ['renewalPrice', 'renewalAmount']) ??
          Money.firstField(renewal, const ['price', 'amount']),
      renewalInProgress: renewalState == 'pending' ||
          renewalState == 'processing' ||
          boolOr(j['renewalPending']),
      lastOrderId: str(j['lastOrderId'] ?? renewal['orderId']),
    );
  }
}
