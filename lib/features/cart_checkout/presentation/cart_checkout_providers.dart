import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../billing/presentation/billing_providers.dart';
import '../../catalog/data/commerce_runtime.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/idempotency.dart';
import '../../catalog/domain/polling.dart';
import '../../orders/presentation/orders_providers.dart';
import '../../subscriptions_renewals/presentation/subscriptions_providers.dart';
import '../../catalog/domain/physical_models.dart';
import '../data/address_store.dart';
import '../data/cart_checkout_repository.dart';
import '../data/personalization_repository.dart';

// ---------------------------------------------------------------------------
// Cart
// ---------------------------------------------------------------------------

/// Client-side cart: identifiers + quantities + display titles only.
/// Session-scoped, so it is emptied on logout or account switch.
class CartController extends Notifier<List<CartLine>> {
  @override
  List<CartLine> build() {
    ref.watch(sessionKeyProvider);
    return const [];
  }

  /// Adds [line], merging with an identical configuration.
  void add(CartLine line) {
    final i = state.indexWhere((l) => l.key == line.key);
    if (i < 0) {
      state = [
        ...state,
        line.copyWith(quantity: line.quantity.clamp(1, CartLine.maxQuantity)),
      ];
    } else {
      final merged = (state[i].quantity + line.quantity).clamp(
        1,
        CartLine.maxQuantity,
      );
      state = [
        for (var j = 0; j < state.length; j++)
          j == i ? state[j].copyWith(quantity: merged) : state[j],
      ];
    }
  }

  void setQuantity(String key, int quantity) {
    if (quantity < 1) return remove(key);
    final q = quantity.clamp(1, CartLine.maxQuantity);
    state = [for (final l in state) l.key == key ? l.copyWith(quantity: q) : l];
  }

  /// Stores NFC/print details for a line (kept in step with quantity).
  void setPersonalization(String key, LinePersonalization p) {
    state = [
      for (final l in state) l.key == key ? l.copyWith(personalization: p) : l,
    ];
  }

  void remove(String key) => state = [
    for (final l in state)
      if (l.key != key) l,
  ];

  /// Removes lines the server reported as unavailable.
  void removeInvalid(Quote quote) {
    bool bad(CartLine c) =>
        quote.invalidLines.any(
          (i) => c.matches(
            itemId: i.itemId,
            itemType: i.itemType,
            variantId: i.variantId,
          ),
        ) ||
        quote.lines.any(
          (q) =>
              !q.available &&
              c.matches(
                itemId: q.itemId,
                itemType: q.itemType.name,
                variantId: q.variantId,
              ),
        );
    state = [
      for (final l in state)
        if (!bad(l)) l,
    ];
  }

  void clear() => state = const [];
}

final cartProvider = NotifierProvider<CartController, List<CartLine>>(
  CartController.new,
);

/// Number of lines, for the app-bar badge.
final cartCountProvider = Provider<int>(
  (ref) => ref.watch(cartProvider).length,
);

/// On-demand quote for the cart screen. Any cart change discards it, so a
/// stale quote can never be shown next to edited lines.
class CartQuoteController extends AsyncNotifier<Quote?> {
  @override
  Future<Quote?> build() async {
    ref.watch(sessionKeyProvider);
    final lines = ref.watch(cartProvider);
    if (lines.isEmpty) return null;
    return ref.read(cartCheckoutRepositoryProvider).quote(lines);
  }

  Future<void> fetch() async {
    final lines = ref.read(cartProvider);
    if (lines.isEmpty) {
      state = const AsyncData(null);
      return;
    }
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => ref.read(cartCheckoutRepositoryProvider).quote(lines),
    );
    if (ref.mounted) state = result;
  }
}

final cartQuoteProvider = AsyncNotifierProvider<CartQuoteController, Quote?>(
  CartQuoteController.new,
);

/// Whether any cart line is a physical item needing delivery.
final cartNeedsShippingProvider = Provider<bool>(
  (ref) => ref.watch(cartProvider).any((l) => l.requiresShipping),
);

// ---------------------------------------------------------------------------
// Delivery address & GST details
// ---------------------------------------------------------------------------

/// Saved delivery addresses for the signed-in user (device-local, secure).
class AddressBookController extends AsyncNotifier<List<ShippingAddress>> {
  static const maxSaved = 5;

  @override
  Future<List<ShippingAddress>> build() async {
    final key = ref.watch(sessionKeyProvider);
    if (key == null) return const [];
    return ref.watch(addressStoreProvider).load(key);
  }

  /// Saves (or moves to the top) [address].
  Future<void> save(ShippingAddress address) async {
    final key = ref.read(sessionKeyProvider);
    if (key == null) return;
    final current = state.value ?? await future;
    final next = [
      address,
      for (final a in current)
        if (a.dedupeKey != address.dedupeKey) a,
    ].take(maxSaved).toList(growable: false);
    state = AsyncData(next);
    await ref.read(addressStoreProvider).save(key, next);
  }

  Future<void> remove(ShippingAddress address) async {
    final key = ref.read(sessionKeyProvider);
    if (key == null) return;
    final next = [
      for (final a in state.value ?? const <ShippingAddress>[])
        if (a.dedupeKey != address.dedupeKey) a,
    ];
    state = AsyncData(next);
    await ref.read(addressStoreProvider).save(key, next);
  }
}

final addressBookProvider =
    AsyncNotifierProvider<AddressBookController, List<ShippingAddress>>(
      AddressBookController.new,
    );

class CheckoutDetails {
  const CheckoutDetails({this.address, this.gst = const GstDetails()});
  final ShippingAddress? address;
  final GstDetails gst;
}

/// Delivery address + GST details chosen for this checkout (session-scoped).
class CheckoutDetailsController extends Notifier<CheckoutDetails> {
  @override
  CheckoutDetails build() {
    ref.watch(sessionKeyProvider);
    return const CheckoutDetails();
  }

  void setAddress(ShippingAddress? a) =>
      state = CheckoutDetails(address: a, gst: state.gst);

  void setGst(GstDetails g) =>
      state = CheckoutDetails(address: state.address, gst: g);
}

final checkoutDetailsProvider =
    NotifierProvider<CheckoutDetailsController, CheckoutDetails>(
      CheckoutDetailsController.new,
    );

/// Org cards an NFC product can open.
final linkableCardsProvider = FutureProvider.autoDispose<List<LinkableCard>>((
  ref,
) {
  ref.watch(sessionKeyProvider);
  return ref.watch(personalizationRepositoryProvider).cards();
});

/// Fresh quote whenever checkout opens (auto-disposed when it closes) and
/// whenever the delivery address / GST details change — shipping and tax
/// come only from this server quote.
final checkoutQuoteProvider = FutureProvider.autoDispose<Quote?>((ref) {
  ref.watch(sessionKeyProvider);
  final lines = ref.watch(cartProvider);
  if (lines.isEmpty) return null;
  final details = ref.watch(checkoutDetailsProvider);
  return ref
      .watch(cartCheckoutRepositoryProvider)
      .quote(lines, shippingAddress: details.address, gst: details.gst);
});

// ---------------------------------------------------------------------------
// Checkout (order + payment attempt, idempotent)
// ---------------------------------------------------------------------------

class CheckoutResult {
  const CheckoutResult(this.orderId, this.session);
  final String orderId;
  final PaymentSession session;
}

/// State visible to screens: the last approved checkout page per order, so
/// the status screen can offer "Open payment page" again.
class CheckoutState {
  const CheckoutState({this.checkoutUris = const {}});
  final Map<String, Uri> checkoutUris;
}

/// Owns idempotency keys for order creation and payment attempts.
///
/// * `POST /orders` uses one key per checkout attempt, tied to the quote /
///   cart fingerprint. Retrying after a timeout reuses it, so the server
///   returns the same order instead of creating a duplicate.
/// * `POST /orders/:id/payment` uses one key per payment attempt for that
///   order; a deliberate "retry payment" after a failure mints a new one.
class CheckoutController extends Notifier<CheckoutState> {
  late AttemptKey _orderKey;
  final Map<String, AttemptKey> _paymentKeys = {};
  final Set<String> _cartOrders = {};
  String? _createdFingerprint;
  String? _createdOrderId;

  @override
  CheckoutState build() {
    ref.watch(sessionKeyProvider);
    _orderKey = AttemptKey(ref.watch(idempotencyKeyFactoryProvider));
    _paymentKeys.clear();
    _cartOrders.clear();
    _createdFingerprint = null;
    _createdOrderId = null;
    return const CheckoutState();
  }

  /// Identity of what is being bought. Any change (lines, personalisation,
  /// address, GST) makes the next order a new attempt with a new key.
  static String fingerprintOf(
    Quote quote,
    List<CartLine> lines, {
    ShippingAddress? address,
    GstDetails? gst,
  }) {
    final cart = [for (final l in lines) jsonEncode(l.toRequestJson())]..sort();
    return [
      quote.id ?? '',
      cart.join(';'),
      if (address != null) jsonEncode(address.toJson()),
      if (gst != null) jsonEncode(gst.toJson()),
    ].join('#');
  }

  /// Current order key (for tests/diagnostics; never logged).
  String? get currentOrderKey => _orderKey.current;

  String? paymentKeyFor(String orderId) => _paymentKeys[orderId]?.current;

  /// Creates the order (once per attempt) and starts its payment.
  Future<CheckoutResult> placeOrder({
    required Quote quote,
    required List<CartLine> lines,
    ShippingAddress? shippingAddress,
    GstDetails? gst,
  }) async {
    final repo = ref.read(cartCheckoutRepositoryProvider);
    final fp = fingerprintOf(quote, lines, address: shippingAddress, gst: gst);
    String orderId;
    if (_createdOrderId != null && _createdFingerprint == fp) {
      // Order exists from an earlier try of this attempt; only payment failed.
      orderId = _createdOrderId!;
    } else {
      final order = await repo.createOrder(
        lines: lines,
        quoteId: quote.id,
        shippingAddress: shippingAddress,
        gst: gst,
        idempotencyKey: _orderKey.keyFor(fp),
      );
      if (order.id.isEmpty) {
        throw StateError('Order response missing id');
      }
      orderId = order.id;
      _createdOrderId = orderId;
      _createdFingerprint = fp;
      _cartOrders.add(orderId);
    }
    final session = await startPayment(orderId);
    return CheckoutResult(orderId, session);
  }

  /// Starts (or retries) payment for [orderId]. [newAttempt] mints a new
  /// idempotency key — use it only for a deliberate retry after a failure.
  Future<PaymentSession> startPayment(
    String orderId, {
    bool newAttempt = false,
  }) async {
    final keys = _paymentKeys.putIfAbsent(
      orderId,
      () => AttemptKey(ref.read(idempotencyKeyFactoryProvider)),
    );
    if (newAttempt) keys.reset();
    final session = await ref
        .read(cartCheckoutRepositoryProvider)
        .startPayment(orderId, idempotencyKey: keys.keyFor(orderId));
    final uri = session.safeCheckoutUri;
    if (uri != null) {
      state = CheckoutState(
        checkoutUris: {...state.checkoutUris, orderId: uri},
      );
    }
    return session;
  }

  /// Called when an order reaches a terminal state: the next checkout of the
  /// same cart is a new attempt with a new key.
  void finishAttempt(String orderId) {
    if (_createdOrderId == orderId) {
      _createdOrderId = null;
      _createdFingerprint = null;
      _orderKey.reset();
    }
    _paymentKeys[orderId]?.reset();
  }

  bool isCartOrder(String orderId) => _cartOrders.contains(orderId);
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(CheckoutController.new);

// ---------------------------------------------------------------------------
// Payment status (bounded polling of GET /orders/:id)
// ---------------------------------------------------------------------------

class PaymentStatusState {
  const PaymentStatusState({
    this.order,
    this.polling = false,
    this.timedOut = false,
    this.error,
  });

  final Order? order;
  final bool polling;

  /// Budget spent without a terminal state ("still processing").
  final bool timedOut;
  final Object? error;

  PaymentOutcome? get outcome => order?.paymentOutcome;

  PaymentStatusState copyWith({
    Order? order,
    bool? polling,
    bool? timedOut,
    Object? error,
    bool clearError = false,
  }) => PaymentStatusState(
    order: order ?? this.order,
    polling: polling ?? this.polling,
    timedOut: timedOut ?? this.timedOut,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Polls the order until the **server** reports a terminal payment state.
/// Nothing on the client marks an order paid.
class PaymentStatusController extends Notifier<PaymentStatusState> {
  PaymentStatusController(this.orderId);

  final String orderId;
  int _generation = 0;

  @override
  PaymentStatusState build() {
    ref.watch(sessionKeyProvider);
    ref.onDispose(() => _generation++);
    Future.microtask(poll);
    return const PaymentStatusState(polling: true);
  }

  /// (Re)starts bounded polling. Any running loop is superseded.
  Future<void> poll() async {
    if (!ref.mounted) return;
    final gen = ++_generation;
    bool stale() => gen != _generation || !ref.mounted;
    state = state.copyWith(polling: true, timedOut: false, clearError: true);
    final repo = ref.read(cartCheckoutRepositoryProvider);
    final result = await pollUntil<Order>(
      fetch: () => repo.order(orderId),
      isDone: (o) => o.paymentOutcome.isTerminal,
      sleep: ref.read(pollSleepProvider),
      schedule: ref.read(pollScheduleProvider),
      isCancelled: stale,
      onUpdate: (o) {
        if (!stale()) state = state.copyWith(order: o);
      },
    );
    if (stale()) return;
    switch (result.end) {
      case PollEnd.done:
        state = state.copyWith(polling: false);
        _onTerminal(result.last!);
      case PollEnd.timedOut:
        state = state.copyWith(polling: false, timedOut: true);
      case PollEnd.failed:
        state = state.copyWith(polling: false, error: result.error);
      case PollEnd.cancelled:
        break;
    }
  }

  /// Re-checks immediately (e.g. when the app returns from the browser).
  void checkNow() {
    final outcome = state.outcome;
    if (outcome != null && outcome.isTerminal) return;
    poll();
  }

  /// Starts a **new** payment attempt for a failed/pending order.
  Future<PaymentSession> retryPayment() async {
    final session = await ref
        .read(checkoutControllerProvider.notifier)
        .startPayment(orderId, newAttempt: true);
    if (ref.mounted) unawaited(poll());
    return session;
  }

  void _onTerminal(Order order) {
    final checkout = ref.read(checkoutControllerProvider.notifier);
    if (order.paymentOutcome == PaymentOutcome.paid &&
        checkout.isCartOrder(orderId)) {
      ref.read(cartProvider.notifier).clear();
    }
    checkout.finishAttempt(orderId);
    invalidateOrderCaches(ref, orderId: orderId);
    if (order.paymentOutcome == PaymentOutcome.paid) {
      // Seats/entitlements may have changed server-side.
      ref.invalidate(billingProvider);
      ref.invalidate(subscriptionsListProvider);
      if (order.subscriptionId != null) {
        ref.invalidate(subscriptionDetailProvider(order.subscriptionId!));
      }
    }
  }
}

final paymentStatusProvider = NotifierProvider.autoDispose
    .family<PaymentStatusController, PaymentStatusState, String>(
      PaymentStatusController.new,
    );
