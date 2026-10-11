import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/models/organization.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../auth/presentation/widgets/callout.dart';
import 'dashboard_providers.dart';
import 'widgets/stat_tile.dart';

/// Owner home: organization status, trial, seats, card and review totals,
/// billing warnings and quick actions.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardSummaryProvider);
    final shopEnabled = ref.watch(currentConfigProvider).isEnabled(Flags.shop);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push(Routes.ownerNotifications),
          ),
        ],
      ),
      body: summary.isLoading && !summary.hasValue
          ? const _DashboardSkeleton()
          : AsyncValueView<DashboardSummary>(
              value: summary,
              onRetry: () => ref.invalidate(dashboardSummaryProvider),
              data: (s) => RefreshIndicator(
                onRefresh: () => ref.refresh(dashboardSummaryProvider.future),
                child: _DashboardBody(summary: s, shopEnabled: shopEnabled),
              ),
            ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.summary, required this.shopEnabled});

  final DashboardSummary summary;
  final bool shopEnabled;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final trial = s.trial;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        ContentWidth(
          child: Padding(
            padding: AppSpacing.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OrganizationHero(summary: s),
                if (s.disabledByBilling > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  Callout(
                    tone: CalloutTone.warning,
                    title: s.disabledByBilling == 1
                        ? '1 card disabled by billing'
                        : '${s.disabledByBilling} cards disabled by billing',
                    message:
                        'These cards are hidden from the public until a paid seat '
                        'is available. Purchase seats or renew your plan to '
                        'reactivate them.',
                    action: FilledButton.tonal(
                      onPressed: () => context.push(Routes.ownerSeats),
                      child: const Text('Purchase seats'),
                    ),
                  ),
                ],
                if (trial != null && !trial.active) ...[
                  const SizedBox(height: AppSpacing.md),
                  _TrialEndedCallout(trial: trial),
                ],
                const SectionHeader('Overview'),
                _Stats(summary: s),
                const SectionHeader('Quick actions'),
                _QuickActions(shopEnabled: shopEnabled),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String? _formatDate(DateTime? d) =>
    d == null ? null : DateFormat.yMMMd().format(d);

class _OrganizationHero extends StatelessWidget {
  const _OrganizationHero({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final status = summary.organizationStatus;
    final trial = summary.trial;
    final trialActive = trial?.active ?? false;
    final ends = _formatDate(trial?.endsAt);
    final days = trial?.daysRemaining;
    final trialLine = !trialActive
        ? null
        : switch (days) {
            null =>
              ends == null ? 'Free trial active' : 'Free trial · ends $ends',
            0 => 'Your trial ends today',
            1 => '1 day left in your trial',
            _ => '$days days left in your trial',
          };

    return HeroHeader(
      title: summary.organizationName,
      subtitle: trialLine ?? 'Here’s how your team is doing.',
      trailing: status == null ? null : OrganizationStatusChip(status: status),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (trialActive)
            Text(
              [
                if (days != null && ends != null) 'Ends $ends.',
                'Unlimited cards during the trial.',
              ].join(' '),
            ),
          _HeroButton(
            icon: Icons.edit_outlined,
            label: 'Edit profile',
            onPressed: () => context.push(Routes.ownerProfile),
          ),
          if (trialActive)
            _HeroButton(
              icon: Icons.event_seat_outlined,
              label: 'Purchase seats',
              onPressed: () => context.push(Routes.ownerSeats),
            ),
        ],
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white70),
    ),
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label),
  );
}

/// Organization status (`active`, `trial`, `suspended`, …) as a pill.
class OrganizationStatusChip extends StatelessWidget {
  const OrganizationStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final (tone, icon) = switch (normalized) {
      'active' => (StatusTone.success, Icons.check_circle_outline),
      'trial' || 'trialing' => (StatusTone.info, Icons.hourglass_top),
      'suspended' ||
      'inactive' ||
      'disabled' ||
      'cancelled' ||
      'canceled' ||
      'past_due' => (StatusTone.danger, Icons.error_outline),
      _ => (StatusTone.neutral, Icons.info_outline),
    };
    final label = humanizeStatus(normalized);
    return Semantics(
      label: 'Organization status: $label',
      excludeSemantics: true,
      // Solid surface so the pill stays legible on the hero gradient.
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: StatusChip(label, tone: tone, icon: icon),
      ),
    );
  }
}

/// `past_due` → `Past due`.
String humanizeStatus(String s) {
  final words = s.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (words.isEmpty) return 'Unknown';
  return words[0].toUpperCase() + words.substring(1);
}

class _TrialEndedCallout extends StatelessWidget {
  const _TrialEndedCallout({required this.trial});

  final TrialInfo trial;

  @override
  Widget build(BuildContext context) {
    final ends = _formatDate(trial.endsAt);
    return Callout(
      tone: CalloutTone.warning,
      title: 'Your free trial has ended',
      message: [
        if (ends != null) 'It ended on $ends.',
        'Purchase seats to keep your team’s cards active.',
      ].join(' '),
      action: FilledButton.tonal(
        onPressed: () => context.push(Routes.ownerSeats),
        child: const Text('Purchase seats'),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final full =
        !s.unlimitedSeats && s.paidSeats > 0 && s.activeCards >= s.paidSeats;
    final rating = s.totalReviews == 0
        ? '—'
        : s.averageRating.toStringAsFixed(1);
    final tiles = [
      StatTile(
        icon: Icons.badge_outlined,
        label: 'Active cards',
        value: s.unlimitedSeats
            ? '${s.activeCards}'
            : '${s.activeCards} / ${s.paidSeats}',
        caption: s.unlimitedSeats
            ? 'Unlimited during trial'
            : full
            ? 'All paid seats in use'
            : (s.paidSeats == 1
                  ? 'of 1 paid seat'
                  : 'of ${s.paidSeats} paid seats'),
        color: full ? AppColors.warning : null,
        onTap: () => context.go(Routes.ownerCards),
      ),
      StatTile(
        icon: Icons.style_outlined,
        label: 'Total cards',
        value: '${s.totalCards}',
        onTap: () => context.go(Routes.ownerCards),
      ),
      StatTile(
        icon: Icons.reviews_outlined,
        label: 'Total reviews',
        value: '${s.totalReviews}',
        color: AppColors.accent,
        onTap: () => context.go(Routes.ownerReviews),
      ),
      StatTile(
        icon: Icons.star_rate_rounded,
        color: AppColors.star,
        label: 'Average rating',
        value: rating,
        caption: s.totalReviews == 0 ? 'No reviews yet' : 'out of 5',
      ),
    ];
    return ResponsiveGrid(minTileWidth: 150, children: tiles);
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.shopEnabled});

  final bool shopEnabled;

  @override
  Widget build(BuildContext context) {
    final actions = [
      QuickActionTile(
        icon: Icons.person_add_alt_1_outlined,
        label: 'Add staff',
        onTap: () => context.push(Routes.ownerStaffNew),
      ),
      QuickActionTile(
        icon: Icons.badge_outlined,
        label: 'Cards',
        onTap: () => context.go(Routes.ownerCards),
      ),
      QuickActionTile(
        icon: Icons.qr_code_2,
        label: 'Share QR',
        onTap: () => context.go(Routes.ownerCards),
      ),
      QuickActionTile(
        icon: Icons.reviews_outlined,
        label: 'Reviews',
        onTap: () => context.go(Routes.ownerReviews),
      ),
      QuickActionTile(
        icon: Icons.event_seat_outlined,
        label: 'Purchase seats',
        onTap: () => context.push(Routes.ownerSeats),
      ),
      if (shopEnabled)
        QuickActionTile(
          icon: Icons.storefront_outlined,
          label: 'Browse services',
          onTap: () => context.push(Routes.ownerShop),
        ),
    ];
    return ResponsiveGrid(minTileWidth: 140, children: actions);
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading dashboard',
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: AppSpacing.page,
          children: [
            const SkeletonBox(height: 140, radius: AppRadius.xl),
            const SizedBox(height: AppSpacing.lg),
            const SkeletonBox(height: 18, width: 120),
            const SizedBox(height: AppSpacing.md),
            ResponsiveGrid(
              minTileWidth: 150,
              children: [
                for (var i = 0; i < 4; i++)
                  const SkeletonBox(height: 120, radius: AppRadius.lg),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
