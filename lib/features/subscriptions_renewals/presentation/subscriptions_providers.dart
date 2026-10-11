import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../shared/models/paged.dart';
import '../../catalog/data/commerce_runtime.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/idempotency.dart';
import '../../catalog/domain/polling.dart';
import '../../catalog/presentation/common/paged_list.dart';
import '../data/subscriptions_repository.dart';

class SubscriptionsListController extends PagedNotifier<Subscription> {
  @override
  Future<Paged<Subscription>> fetchPage(int page) =>
      ref.read(subscriptionsRepositoryProvider).subscriptions(page: page);
}

final subscriptionsListProvider = AsyncNotifierProvider.autoDispose<
    SubscriptionsListController, PagedList<Subscription>>(
  SubscriptionsListController.new,
);

final subscriptionDetailProvider =
    FutureProvider.autoDispose.family<Subscription, String>((ref, id) {
  ref.watch(sessionKeyProvider);
  return ref.watch(subscriptionsRepositoryProvider).subscription(id);
});

/// True once the server shows the renewal took effect.
bool renewalConfirmed(Subscription before, Subscription now) {
  if (now.renewalInProgress) return false;
  bool advanced(DateTime? a, DateTime? b) => a != null && b != null && b.isAfter(a);
  return advanced(before.currentPeriodEnd, now.currentPeriodEnd) ||
      advanced(before.nextRenewalAt, now.nextRenewalAt) ||
      (now.status == SubscriptionStatus.active &&
          before.status != SubscriptionStatus.active);
}

enum RenewalPhase { idle, confirming, confirmed, stillProcessing }

class RenewalState {
  const RenewalState({this.phase = RenewalPhase.idle, this.checkoutUri, this.error});
  final RenewalPhase phase;
  final Uri? checkoutUri;
  final Object? error;
}

/// "Renew now": POST /subscriptions/:id/renew with an idempotency key reused
/// across retries of the same attempt, then confirm against the server.
class RenewalController extends Notifier<RenewalState> {
  RenewalController(this.subscriptionId);

  final String subscriptionId;
  late AttemptKey _key;
  Subscription? _baseline;
  int _generation = 0;

  @override
  RenewalState build() {
    ref.watch(sessionKeyProvider);
    _key = AttemptKey(ref.watch(idempotencyKeyFactoryProvider));
    ref.onDispose(() => _generation++);
    return const RenewalState();
  }

  String? get currentKey => _key.current;

  Future<PaymentSession> renew() async {
    final repo = ref.read(subscriptionsRepositoryProvider);
    final key = _key.keyFor(subscriptionId);
    _baseline = await repo.subscription(subscriptionId);
    final session = await repo.renew(subscriptionId, idempotencyKey: key);
    if (ref.mounted) {
      state = RenewalState(phase: state.phase, checkoutUri: session.safeCheckoutUri);
    }
    return session;
  }

  /// Polls the subscription until the server reflects the renewal.
  Future<void> confirm() async {
    if (!ref.mounted) return;
    final gen = ++_generation;
    bool stale() => gen != _generation || !ref.mounted;
    final repo = ref.read(subscriptionsRepositoryProvider);
    final before = _baseline ?? await repo.subscription(subscriptionId);
    if (stale()) return;
    _baseline = before;
    state = RenewalState(phase: RenewalPhase.confirming, checkoutUri: state.checkoutUri);
    final result = await pollUntil<Subscription>(
      fetch: () => repo.subscription(subscriptionId),
      isDone: (s) => renewalConfirmed(before, s),
      sleep: ref.read(pollSleepProvider),
      schedule: ref.read(pollScheduleProvider),
      isCancelled: stale,
    );
    if (stale()) return;
    switch (result.end) {
      case PollEnd.done:
        _key.reset();
        _baseline = null;
        state = const RenewalState(phase: RenewalPhase.confirmed);
        ref.invalidate(subscriptionDetailProvider(subscriptionId));
        ref.invalidate(subscriptionsListProvider);
      case PollEnd.timedOut || PollEnd.failed:
        state = RenewalState(
          phase: RenewalPhase.stillProcessing,
          checkoutUri: state.checkoutUri,
          error: result.error,
        );
      case PollEnd.cancelled:
        break;
    }
  }

  void checkNow() {
    if (state.phase == RenewalPhase.confirming ||
        state.phase == RenewalPhase.stillProcessing) {
      unawaited(confirm());
    }
  }

  void reset() {
    _generation++;
    state = const RenewalState();
  }
}

final renewalProvider = NotifierProvider.autoDispose
    .family<RenewalController, RenewalState, String>(RenewalController.new);
