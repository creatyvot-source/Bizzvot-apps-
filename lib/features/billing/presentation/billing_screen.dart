import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../catalog/data/link_launcher.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/formatting.dart';
import '../../catalog/presentation/common/commerce_widgets.dart';
import '../domain/billing_models.dart';
import 'billing_providers.dart';

class BillingScreen extends ConsumerWidget {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(billingProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Billing & seats')),
      body: value.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const _BillingSkeleton(),
        error: (e, _) {
          final ex = AppException.from(e);
          // The billing route is not deployed yet: degrade gracefully.
          if (ex.kind == AppErrorKind.notFound ||
              ex.kind == AppErrorKind.gone) {
            return const _ComingSoon();
          }
          return ErrorView(
            error: ex,
            onRetry: () => ref.invalidate(billingProvider),
          );
        },
        data: (b) => RefreshIndicator(
          onRefresh: () => ref.refresh(billingProvider.future),
          child: ContentWidth(child: _BillingBody(billing: b)),
        ),
      ),
    );
  }
}

class _BillingBody extends StatelessWidget {
  const _BillingBody({required this.billing});
  final BillingSummary billing;

  @override
  Widget build(BuildContext context) {
    final b = billing;
    final theme = Theme.of(context);
    final trial = b.trial;
    final subtitle = b.onTrial
        ? (trial?.endsAt != null
              ? 'Free trial · ends ${formatDate(trial!.endsAt)}'
              : 'Free trial')
        : b.subscriptionStatusLabel;
    final seatsValue = b.unlimitedSeats
        ? 'Unlimited'
        : (b.paidSeats?.toString() ?? '—');

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppSpacing.page,
      children: [
        HeroHeader(
          title: b.planName ?? (b.onTrial ? 'Trial' : 'No plan yet'),
          subtitle: subtitle,
          trailing: const Icon(
            Icons.workspace_premium_outlined,
            color: Colors.white,
            size: 32,
          ),
          child: Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              if (b.nextRenewalAt != null && !b.onTrial)
                Text(
                  b.cancelAtPeriodEnd
                      ? 'Ends ${formatDate(b.nextRenewalAt)}'
                      : 'Renews ${formatDate(b.nextRenewalAt)}',
                ),
              if (b.billingPeriod != null) Text(humanize(b.billingPeriod)),
            ],
          ),
        ),
        for (final alert in b.alerts()) ...[
          const SizedBox(height: AppSpacing.md),
          _AlertBanner(alert: alert, billing: b),
        ],
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, c) {
            final tiles = [
              StatTile(
                label: 'Paid seats',
                value: seatsValue,
                icon: Icons.event_seat_outlined,
              ),
              StatTile(
                label: 'Active cards',
                value: b.activeCards?.toString() ?? '—',
                icon: Icons.badge_outlined,
              ),
              if (b.availableSeats != null)
                StatTile(
                  label: 'Seats available',
                  value: '${b.availableSeats}',
                  icon: Icons.add_card_outlined,
                ),
            ];
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final cols = scale > 1.3
                ? 1
                : (c.maxWidth / 160).floor().clamp(1, 3);
            final w = (c.maxWidth - (cols - 1) * AppSpacing.md) / cols;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [for (final t in tiles) SizedBox(width: w, child: t)],
            );
          },
        ),
        const SectionHeader('Subscription'),
        Card(
          child: Padding(
            padding: AppSpacing.page,
            child: Column(
              children: [
                InfoRow(
                  label: 'Status',
                  value: StatusChip(
                    b.onTrial ? 'Trial' : b.subscriptionStatusLabel,
                    tone: _tone(b),
                  ),
                ),
                if (b.nextRenewalAt != null)
                  InfoRow.text(
                    b.cancelAtPeriodEnd ? 'Ends on' : 'Next renewal',
                    formatDate(b.nextRenewalAt),
                  ),
                if (b.graceUntil != null)
                  InfoRow.text('Grace period until', formatDate(b.graceUntil)),
                if (trial?.endsAt != null)
                  InfoRow.text('Trial ends', formatDate(trial!.endsAt)),
                if (b.lastPaymentStatus != null)
                  InfoRow.text('Last payment', b.lastPaymentStatus!.label),
              ],
            ),
          ),
        ),
        if (b.planFeatures.isNotEmpty) ...[
          const SectionHeader('Plan features'),
          for (final f in b.planFeatures)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(f)),
                ],
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (b.seatPurchaseAllowed) ...[
          FilledButton.icon(
            onPressed: () => context.push(Routes.ownerSeats),
            icon: const Icon(Icons.add),
            label: const Text('Buy more seats'),
          ),
        ] else
          // Store compliance: neutral status copy, no link or purchase CTA.
          Text(
            'Manage your plan from your Bizzvot account.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        _NavTile(
          icon: Icons.autorenew,
          title: 'Subscriptions & renewals',
          route: Routes.ownerSubscriptions,
        ),
        _NavTile(
          icon: Icons.description_outlined,
          title: 'Invoices & receipts',
          route: Routes.ownerInvoices,
        ),
        _NavTile(
          icon: Icons.storefront_outlined,
          title: 'Services & shop',
          route: Routes.ownerShop,
        ),
      ],
    );
  }

  static StatusTone _tone(BillingSummary b) {
    if (b.onTrial) return StatusTone.info;
    return switch (b.subscriptionStatus) {
      SubscriptionStatus.active => StatusTone.success,
      SubscriptionStatus.pastDue ||
      SubscriptionStatus.gracePeriod => StatusTone.warning,
      SubscriptionStatus.expired => StatusTone.danger,
      _ => StatusTone.neutral,
    };
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.alert, required this.billing});
  final BillingAlert alert;
  final BillingSummary billing;

  @override
  Widget build(BuildContext context) {
    final b = billing;
    // Status-only copy (App Store 3.1.1 / Play Payments anti-steering): no
    // purchase or renewal call to action unless the server enables seat
    // purchases for this platform.
    const manage = 'Manage your plan from your Bizzvot account.';
    final (title, message, tone) = switch (alert) {
      BillingAlert.paymentFailed => (
        'Payment failed',
        'Your last payment didn’t go through. $manage',
        StatusTone.danger,
      ),
      BillingAlert.gracePeriod => (
        'Grace period',
        b.graceUntil == null
            ? 'Your plan has lapsed. Cards stay active for a limited time. $manage'
            : 'Your plan has lapsed. Cards stay active until ${formatDate(b.graceUntil)}. $manage',
        StatusTone.warning,
      ),
      BillingAlert.expired => (
        'Plan expired',
        'Your plan has expired. Cards beyond your free allowance may be disabled. $manage',
        StatusTone.danger,
      ),
      BillingAlert.trialEnding => (
        'Trial ending soon',
        b.trial?.endsAt == null
            ? 'Your free trial ends soon. $manage'
            : 'Your free trial ends ${formatDate(b.trial!.endsAt)}. $manage',
        StatusTone.info,
      ),
      BillingAlert.trialEnded => (
        'Trial ended',
        'Your free trial has ended. $manage',
        StatusTone.warning,
      ),
      BillingAlert.cardsDisabled => (
        'Cards disabled by billing',
        '${b.disabledByBilling} card${b.disabledByBilling == 1 ? ' is' : 's are'} disabled until more seats are available.',
        StatusTone.warning,
      ),
    };
    final Widget? action = switch (alert) {
      BillingAlert.paymentFailed ||
      BillingAlert.gracePeriod ||
      BillingAlert.expired when b.subscriptionId != null => TextButton(
        onPressed: () => context.push(Routes.ownerSubscription(b.subscriptionId!)),
        child: const Text('View subscription'),
      ),
      BillingAlert.cardsDisabled ||
      BillingAlert.trialEnded ||
      BillingAlert.trialEnding when b.seatPurchaseAllowed => TextButton(
        onPressed: () => context.push(Routes.ownerSeats),
        child: const Text('Buy seats'),
      ),
      _ => null,
    };
    return NoticeCard(title: title, message: message, tone: tone, action: action);
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.route,
  });
  final IconData icon;
  final String title;
  final String route;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => context.push(route),
  );
}

class _ComingSoon extends ConsumerWidget {
  const _ComingSoon();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(currentConfigProvider).supportEmail;
    return EmptyView(
      icon: Icons.credit_card_outlined,
      title: 'Billing is coming soon',
      // Neutral copy only — no purchase steering (store compliance). The
      // support button is for billing questions, not purchases.
      message: 'Your plan and seat details will appear here soon. '
          'Manage your plan from your Bizzvot account.',
      action: email == null
          ? null
          : FilledButton.icon(
              onPressed: () async {
                final ok = await ref
                    .read(linkLauncherProvider)
                    .email(email, subject: 'Billing question');
                if (!ok && context.mounted) {
                  showMessage(context, 'Couldn’t open your email app.');
                }
              },
              icon: const Icon(Icons.mail_outline),
              label: const Text('Billing questions? Contact support'),
            ),
    );
  }
}

class _BillingSkeleton extends StatelessWidget {
  const _BillingSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading billing',
    child: ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: AppSpacing.page,
      children: const [
        SkeletonBox(height: 140, radius: AppRadius.xl),
        SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 110, radius: AppRadius.lg)),
            SizedBox(width: AppSpacing.md),
            Expanded(child: SkeletonBox(height: 110, radius: AppRadius.lg)),
          ],
        ),
        SizedBox(height: AppSpacing.lg),
        SkeletonBox(height: 160, radius: AppRadius.lg),
      ],
    ),
  );
}
