import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/errors/app_exception.dart';
import '../../catalog/data/commerce_runtime.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/idempotency.dart';
import '../../catalog/domain/polling.dart';
import '../data/billing_repository.dart';
import '../domain/billing_models.dart';

/// Current organization billing (session-scoped).
final billingProvider = FutureProvider.autoDispose<BillingSummary>((ref) {
  ref.watch(sessionKeyProvider);
  return ref.watch(billingRepositoryProvider).billing();
});

/// Plans available for seat purchase.
final purchasePlansProvider = FutureProvider.autoDispose<List<Plan>>((ref) {
  ref.watch(sessionKeyProvider);
  return ref.watch(billingRepositoryProvider).plans();
});

enum SeatPhase { selecting, confirming, confirmed, failed, stillProcessing }

class SeatPurchaseState {
  const SeatPurchaseState({
    this.planId,
    this.quantity = 1,
    this.quote,
    this.quoteUnsupported = false,
    this.phase = SeatPhase.selecting,
    this.checkoutUri,
    this.error,
  });

  final String? planId;
  final int quantity;

  /// Server quote for the current selection; null until requested.
  final AsyncValue<Quote>? quote;

  /// The quote route is not deployed: the price is shown on the secure
  /// payment page instead.
  final bool quoteUnsupported;
  final SeatPhase phase;
  final Uri? checkoutUri;
  final Object? error;

  bool get hasQuote => quote?.value != null;

  SeatPurchaseState copyWith({
    String? planId,
    int? quantity,
    AsyncValue<Quote>? quote,
    bool clearQuote = false,
    bool? quoteUnsupported,
    SeatPhase? phase,
    Uri? checkoutUri,
    Object? error,
    bool clearError = false,
  }) => SeatPurchaseState(
    planId: planId ?? this.planId,
    quantity: quantity ?? this.quantity,
    quote: clearQuote ? null : (quote ?? this.quote),
    quoteUnsupported: quoteUnsupported ?? this.quoteUnsupported,
    phase: phase ?? this.phase,
    checkoutUri: checkoutUri ?? this.checkoutUri,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Seat purchase flow: select → server quote → POST /organization/billing
/// (idempotent) → hosted checkout → poll billing until the server confirms.
class SeatPurchaseController extends Notifier<SeatPurchaseState> {
  late AttemptKey _key;
  BillingSummary? _baseline;
  int _generation = 0;

  @override
  SeatPurchaseState build() {
    ref.watch(sessionKeyProvider);
    _key = AttemptKey(ref.watch(idempotencyKeyFactoryProvider));
    ref.onDispose(() => _generation++);
    return const SeatPurchaseState();
  }

  BillingRepository get _repo => ref.read(billingRepositoryProvider);

  String get _fingerprint => '${state.planId}|${state.quantity}';

  /// Idempotency key of the current attempt (tests only; never logged).
  String? get currentKey => _key.current;

  void selectPlan(String planId) {
    if (planId == state.planId) return;
    state = state.copyWith(planId: planId, clearQuote: true, clearError: true);
  }

  void setQuantity(int quantity, {int max = 9999}) {
    final q = quantity.clamp(1, max);
    if (q == state.quantity) return;
    state = state.copyWith(quantity: q, clearQuote: true, clearError: true);
  }

  Future<void> fetchQuote() async {
    final planId = state.planId;
    if (planId == null) return;
    final qty = state.quantity;
    state = state.copyWith(
      quote: const AsyncLoading<Quote>(),
      clearError: true,
    );
    try {
      final q = await _repo.quoteSeats(planId: planId, quantity: qty);
      if (!ref.mounted || state.planId != planId || state.quantity != qty) {
        return;
      }
      state = state.copyWith(quote: AsyncData(q), quoteUnsupported: false);
    } catch (e, st) {
      if (!ref.mounted || state.planId != planId || state.quantity != qty) {
        return;
      }
      final ex = AppException.from(e);
      final unsupported =
          ex.kind == AppErrorKind.notFound || ex.kind == AppErrorKind.gone;
      state = state.copyWith(
        quote: AsyncError<Quote>(ex, st),
        quoteUnsupported: unsupported,
      );
    }
  }

  /// Starts the subscription and returns the payment session. The same
  /// idempotency key is reused if this is retried for the same selection.
  Future<PaymentSession> startCheckout() async {
    final planId = state.planId;
    if (planId == null) throw StateError('No plan selected');
    final key = _key.keyFor(_fingerprint);
    _baseline = await _repo.billing();
    final session = await _repo.startSubscription(
      quantity: state.quantity,
      planId: planId,
      idempotencyKey: key,
    );
    if (ref.mounted) {
      state = state.copyWith(
        checkoutUri: session.safeCheckoutUri,
        clearError: true,
      );
    }
    return session;
  }

  /// Polls billing until the server shows the seats (or a failure).
  Future<void> confirm() async {
    if (!ref.mounted) return;
    final gen = ++_generation;
    bool stale() => gen != _generation || !ref.mounted;
    final before = _baseline ?? await _repo.billing();
    if (stale()) return;
    _baseline = before;
    state = state.copyWith(phase: SeatPhase.confirming, clearError: true);
    final result = await pollUntil<BillingSummary>(
      fetch: _repo.billing,
      isDone: (b) => evaluateSeatPurchase(before, b) != null,
      sleep: ref.read(pollSleepProvider),
      schedule: ref.read(pollScheduleProvider),
      isCancelled: stale,
    );
    if (stale()) return;
    switch (result.end) {
      case PollEnd.done:
        final outcome = evaluateSeatPurchase(before, result.last!);
        final ok = outcome == SeatConfirmation.confirmed;
        state = state.copyWith(
          phase: ok ? SeatPhase.confirmed : SeatPhase.failed,
        );
        _key.reset();
        _baseline = null;
        ref.invalidate(billingProvider);
        ref.invalidate(purchasePlansProvider);
      case PollEnd.timedOut:
        state = state.copyWith(phase: SeatPhase.stillProcessing);
      case PollEnd.failed:
        state = state.copyWith(
          phase: SeatPhase.stillProcessing,
          error: result.error,
        );
      case PollEnd.cancelled:
        break;
    }
  }

  /// Back to selection for a deliberate new attempt.
  void startOver() {
    _generation++;
    _key.reset();
    _baseline = null;
    state = SeatPurchaseState(planId: state.planId, quantity: state.quantity);
  }

  void checkNow() {
    if (state.phase == SeatPhase.confirming ||
        state.phase == SeatPhase.stillProcessing) {
      unawaited(confirm());
    }
  }
}

final seatPurchaseProvider =
    NotifierProvider.autoDispose<SeatPurchaseController, SeatPurchaseState>(
      SeatPurchaseController.new,
    );
