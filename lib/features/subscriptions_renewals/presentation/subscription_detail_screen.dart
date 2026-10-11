import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/formatting.dart';
import '../../catalog/presentation/common/commerce_widgets.dart';
import '../../catalog/presentation/common/cooldown.dart';
import '../../catalog/presentation/common/feature_gate.dart';
import 'subscriptions_providers.dart';
import 'subscriptions_screen.dart';

class SubscriptionDetailScreen extends ConsumerStatefulWidget {
  const SubscriptionDetailScreen({super.key, required this.subscriptionId});

  final String subscriptionId;

  @override
  ConsumerState<SubscriptionDetailScreen> createState() =>
      _SubscriptionDetailScreenState();
}

class _SubscriptionDetailScreenState
    extends ConsumerState<SubscriptionDetailScreen>
    with CooldownState<SubscriptionDetailScreen> {
  late final AppLifecycleListener _lifecycle;

  String get _id => widget.subscriptionId;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(renewalProvider(_id).notifier).checkNow(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _renew(Subscription s) async {
    final ok = await confirmAction(
      context,
      title: 'Renew subscription?',
      message: s.renewalPrice == null
          ? 'You’ll be taken to a secure payment page. The amount is shown there before you pay.'
          : 'You’ll be taken to a secure payment page to pay ${s.renewalPrice!.format()}.',
      confirmLabel: 'Continue',
    );
    if (!ok || !mounted) return;
    final renewal = ref.read(renewalProvider(_id).notifier);
    try {
      final session = await renewal.renew();
      if (!mounted) return;
      await openHostedCheckout(context, ref, session);
      if (!mounted) return;
      if (session.orderId != null && session.orderId!.isNotEmpty) {
        // Renewal is an order: the payment status screen confirms it.
        context.push(Routes.ownerPayment(session.orderId!));
      } else {
        await renewal.confirm();
      }
    } catch (e) {
      if (!mounted) return;
      final ex = AppException.from(e);
      applyRateLimit(ex);
      showError(context, ex);
      if (ex.kind == AppErrorKind.conflict) {
        ref.invalidate(subscriptionDetailProvider(_id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(subscriptionDetailProvider(_id));
    final renewal = ref.watch(renewalProvider(_id));
    return Scaffold(
      appBar: AppBar(title: Text(value.value?.title ?? 'Subscription')),
      body: AsyncValueView(
        value: value,
        onRetry: () => ref.invalidate(subscriptionDetailProvider(_id)),
        data: (s) => RefreshIndicator(
          onRefresh: () => ref.refresh(subscriptionDetailProvider(_id).future),
          child: ContentWidth(child: _body(s, renewal)),
        ),
      ),
    );
  }

  Widget _body(Subscription s, RenewalState renewal) {
    final theme = Theme.of(context);
    final confirming = renewal.phase == RenewalPhase.confirming;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppSpacing.page,
      children: [
        HeroHeader(
          title: s.title,
          subtitle: [
            if (s.planVersion != null) 'Version ${s.planVersion}',
            if (s.billingPeriod != null) humanize(s.billingPeriod),
          ].join(' · '),
          trailing: StatusChip(
            s.statusLabel,
            tone: toneForSubscription(s.status),
          ),
          child: s.quantity == null
              ? null
              : Text(
                  '${s.quantity} seats',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        NoticeCard(
          title: s.statusLabel,
          message:
              s.status == SubscriptionStatus.gracePeriod && s.graceUntil != null
              ? '${s.status.explanation} Grace period ends ${formatDate(s.graceUntil)}.'
              : s.status.explanation,
          tone: toneForSubscription(s.status),
        ),
        if (s.cancelAtPeriodEnd) ...[
          const SizedBox(height: AppSpacing.md),
          NoticeCard(
            title: 'Cancels at period end',
            message:
                'This subscription will end on ${formatDate(s.currentPeriodEnd)} and won’t renew.',
            tone: StatusTone.warning,
          ),
        ],
        const SectionHeader('Details'),
        Card(
          child: Padding(
            padding: AppSpacing.page,
            child: Column(
              children: [
                InfoRow.text(
                  'Current period',
                  '${formatDate(s.currentPeriodStart)} – ${formatDate(s.currentPeriodEnd)}',
                ),
                InfoRow.text(
                  'Next renewal',
                  s.cancelAtPeriodEnd
                      ? 'Won’t renew'
                      : formatDate(s.nextRenewalAt),
                ),
                if (s.graceUntil != null)
                  InfoRow.text('Grace until', formatDate(s.graceUntil)),
                if (s.autoRenew != null)
                  InfoRow.text('Auto-renew', s.autoRenew! ? 'On' : 'Off'),
                if (s.renewalPrice != null)
                  InfoRow.money('Renewal amount', s.renewalPrice),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ..._renewalSection(s, renewal, confirming),
        if (s.lastOrderId != null) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.ownerOrder(s.lastOrderId!)),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('View latest order'),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => context.push(Routes.ownerInvoices),
          icon: const Icon(Icons.description_outlined),
          label: const Text('Invoices'),
        ),
      ],
    );
  }

  List<Widget> _renewalSection(
    Subscription s,
    RenewalState renewal,
    bool confirming,
  ) {
    switch (renewal.phase) {
      case RenewalPhase.confirming:
        return [
          const NoticeCard(
            title: 'Confirming your renewal',
            message: 'We’re waiting for the payment to be verified. This screen updates automatically.',
            icon: Icons.sync,
          ),
          const SizedBox(height: AppSpacing.md),
          const LinearProgressIndicator(),
        ];
      case RenewalPhase.confirmed:
        return [
          const NoticeCard(
            title: 'Renewal confirmed',
            message: 'Your subscription has been renewed. Billing and cards will refresh.',
            tone: StatusTone.success,
          ),
        ];
      case RenewalPhase.stillProcessing:
        return [
          NoticeCard(
            title: 'Still processing',
            message: 'Your renewal payment is taking longer than usual. We’ll notify you once it’s confirmed.',
            tone: StatusTone.warning,
            action: TextButton(
              onPressed: () =>
                  ref.read(renewalProvider(_id).notifier).confirm(),
              child: const Text('Check again'),
            ),
          ),
        ];
      case RenewalPhase.idle:
        break;
    }
    if (s.renewalInProgress) {
      return [
        const NoticeCard(
          title: 'Renewal in progress',
          message: 'A renewal payment is being verified. Check back shortly.',
          icon: Icons.hourglass_top,
        ),
      ];
    }
    final reason = s.renewable
        ? null
        : s.renewalBlockedReason ??
              (s.status == SubscriptionStatus.active
                  ? 'Renewal opens closer to your renewal date.'
                  : 'Renewal isn’t available for this subscription right now.');
    return [
      BusyButton(
        label: coolingDown ? 'Please wait…' : 'Renew now',
        icon: Icons.autorenew,
        onPressed: s.renewable && !coolingDown ? () => _renew(s) : null,
      ),
      if (reason != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(reason, style: Theme.of(context).textTheme.bodySmall),
        ),
    ];
  }
}
