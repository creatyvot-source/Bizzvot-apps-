import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../cart_checkout/presentation/widgets/quote_summary.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/presentation/common/commerce_widgets.dart';
import '../../catalog/presentation/common/cooldown.dart';
import '../../catalog/presentation/common/feature_gate.dart';
import '../../catalog/presentation/widgets/catalog_item_card.dart';
import 'billing_providers.dart';

/// Choose a plan and additional seats, see the server price, pay on the
/// hosted checkout, then wait for the server to confirm the new seats.
class SeatPurchaseScreen extends ConsumerStatefulWidget {
  const SeatPurchaseScreen({super.key});

  @override
  ConsumerState<SeatPurchaseScreen> createState() => _SeatPurchaseScreenState();
}

class _SeatPurchaseScreenState extends ConsumerState<SeatPurchaseScreen>
    with CooldownState<SeatPurchaseScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(seatPurchaseProvider.notifier).checkNow(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _continue(Plan plan, SeatPurchaseState s) async {
    final quote = s.quote?.value;
    final ok = await confirmAction(
      context,
      title: 'Continue to payment?',
      message: quote?.total != null
          ? 'Add ${s.quantity} seat${s.quantity == 1 ? '' : 's'} on ${plan.name} for ${quote!.total!.format()}. '
              'You’ll pay on a secure payment page.'
          : 'Add ${s.quantity} seat${s.quantity == 1 ? '' : 's'} on ${plan.name}. '
              'The final amount is shown on the secure payment page before you pay.',
      confirmLabel: 'Continue',
    );
    if (!ok || !mounted) return;
    final c = ref.read(seatPurchaseProvider.notifier);
    try {
      final session = await c.startCheckout();
      if (!mounted) return;
      await openHostedCheckout(context, ref, session);
      if (!mounted) return;
      await c.confirm();
    } catch (e) {
      if (!mounted) return;
      final ex = AppException.from(e);
      applyRateLimit(ex);
      showError(context, ex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(purchasePlansProvider);
    final s = ref.watch(seatPurchaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Buy seats')),
      body: switch (s.phase) {
        SeatPhase.selecting => plans.when(
            skipLoadingOnRefresh: true,
            loading: () => const SkeletonList(count: 3, leadingAvatar: false),
            error: (e, _) {
              final ex = AppException.from(e);
              if (ex.kind == AppErrorKind.notFound || ex.kind == AppErrorKind.gone) {
                return const EmptyView(
                  icon: Icons.credit_card_outlined,
                  title: 'Seat purchases are coming soon',
                  message: 'Please contact support to add seats for now.',
                );
              }
              return ErrorView(error: ex, onRetry: () => ref.invalidate(purchasePlansProvider));
            },
            data: (list) => list.isEmpty
                ? const EmptyView(
                    icon: Icons.workspace_premium_outlined,
                    title: 'No plans available',
                    message: 'Please contact support to add seats.',
                  )
                : _Selection(plans: list, state: s, onContinue: _continue, coolingDown: coolingDown),
          ),
        _ => ContentWidth(child: _Outcome(state: s)),
      },
    );
  }
}

class _Selection extends ConsumerWidget {
  const _Selection({
    required this.plans,
    required this.state,
    required this.onContinue,
    required this.coolingDown,
  });

  final List<Plan> plans;
  final SeatPurchaseState state;
  final Future<void> Function(Plan, SeatPurchaseState) onContinue;
  final bool coolingDown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(seatPurchaseProvider.notifier);
    final selected = plans.where((p) => p.id == state.planId).firstOrNull;
    if (selected == null && plans.length == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.selectPlan(plans.first.id));
    }
    final quote = state.quote;
    final blocked = selected?.paymentPolicy.blocksCheckout ?? false;
    final canContinue = selected != null &&
        !blocked &&
        !coolingDown &&
        (state.hasQuote || state.quoteUnsupported);

    return Column(
      children: [
        Expanded(
          child: ContentWidth(
            child: ListView(
              padding: AppSpacing.page,
              children: [
                const SectionHeader('Choose a plan', subtitle: 'Seats add active-card slots to your organization'),
                for (final p in plans) ...[
                  _PlanCard(
                    plan: p,
                    selected: p.id == state.planId,
                    onTap: () => c.selectPlan(p.id),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                const SectionHeader('Additional seats'),
                Row(
                  children: [
                    QuantityStepper(
                      value: state.quantity,
                      min: selected?.minQuantity ?? 1,
                      max: selected?.maxQuantity ?? 999,
                      label: 'Seats',
                      onChanged: (v) => c.setQuantity(v, max: selected?.maxQuantity ?? 999),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'Seats are added on top of your current seats once payment is confirmed.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                if (blocked)
                  const NoticeCard(
                    title: 'Purchase not available in app yet',
                    message: 'This plan can’t be bought in the app yet. Please contact support.',
                    tone: StatusTone.warning,
                  )
                else if (selected != null)
                  switch (quote) {
                    null => OutlinedButton.icon(
                        onPressed: c.fetchQuote,
                        icon: const Icon(Icons.request_quote_outlined),
                        label: const Text('Get price'),
                      ),
                    AsyncLoading() => const LoadingView(label: 'Getting price…'),
                    AsyncError() when state.quoteUnsupported => NoticeCard(
                        title: 'Price shown at payment',
                        message: 'We couldn’t preview the price here. The exact amount, tax and total '
                            'are shown on the secure payment page before you pay.',
                        action: TextButton(onPressed: c.fetchQuote, child: const Text('Try again')),
                      ),
                    AsyncError(:final error) => ErrorView(error: error, onRetry: c.fetchQuote),
                    AsyncData(:final value) => QuoteSummary(quote: value),
                  },
              ],
            ),
          ),
        ),
        TotalBar(
          total: state.quote?.value?.total,
          caption: selected == null ? 'Choose a plan' : null,
          action: FilledButton.icon(
            onPressed: canContinue ? () => onContinue(selected, state) : null,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Continue to payment'),
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.selected, required this.onTap});
  final Plan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = priceText(plan.price, label: plan.priceLabel, billingPeriod: plan.billingPeriod);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(
            color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: AppSpacing.page,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? theme.colorScheme.primary : theme.colorScheme.outline,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(plan.name, style: theme.textTheme.titleMedium),
                          if (plan.recommended) const StatusChip('Popular', tone: StatusTone.info),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '$price${plan.price != null ? ' per seat' : ''}',
                        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
                      ),
                      if (plan.description != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(plan.description!, style: theme.textTheme.bodySmall),
                      ],
                      for (final f in plan.features.take(4))
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text('• $f', style: theme.textTheme.bodySmall),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Outcome extends ConsumerWidget {
  const _Outcome({required this.state});
  final SeatPurchaseState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = ref.read(seatPurchaseProvider.notifier);
    final (icon, color, title, message) = switch (state.phase) {
      SeatPhase.confirming => (
          null,
          theme.colorScheme.primary,
          'Confirming payment',
          'Complete the payment on the secure page. We’ll add your seats as soon as the payment is verified.',
        ),
      SeatPhase.confirmed => (
          Icons.check_circle,
          AppColors.success,
          'Seats added',
          'Payment confirmed. Your dashboard and cards will refresh with the new seats.',
        ),
      SeatPhase.failed => (
          Icons.error,
          theme.colorScheme.error,
          'Payment failed',
          'The payment didn’t go through and no seats were added. You can try again.',
        ),
      _ => (
          Icons.schedule,
          AppColors.warning,
          'Still processing',
          'Your payment is taking longer than usual to confirm. We’ll notify you when your seats are added.',
        ),
    };
    return ListView(
      padding: AppSpacing.page,
      children: [
        const SizedBox(height: AppSpacing.xl),
        Semantics(
          liveRegion: true,
          child: Column(
            children: [
              if (icon == null)
                const SizedBox.square(dimension: 72, child: CircularProgressIndicator(strokeWidth: 5))
              else
                Icon(icon, size: 72, color: color),
              const SizedBox(height: AppSpacing.md),
              Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (state.phase != SeatPhase.confirmed && state.phase != SeatPhase.failed && state.checkoutUri != null)
          OutlinedButton.icon(
            onPressed: () => openHostedCheckout(
              context,
              ref,
              PaymentSession(checkoutUrl: state.checkoutUri.toString()),
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open payment page'),
          ),
        if (state.phase == SeatPhase.stillProcessing) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: c.confirm,
            icon: const Icon(Icons.refresh),
            label: const Text('Check again'),
          ),
        ],
        if (state.phase == SeatPhase.failed) ...[
          FilledButton(onPressed: c.startOver, child: const Text('Try again')),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (state.phase != SeatPhase.confirming)
          OutlinedButton(
            onPressed: () => context.go(Routes.ownerBilling),
            child: const Text('Back to billing'),
          ),
      ],
    );
  }
}
