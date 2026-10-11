import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../shared/models/organization.dart';
import '../../../shared/widgets/state_views.dart';
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
      body: AsyncValueView<DashboardSummary>(
        value: summary,
        loadingLabel: 'Loading dashboard…',
        onRetry: () => ref.invalidate(dashboardSummaryProvider),
        data: (s) => RefreshIndicator(
          onRefresh: () => ref.refresh(dashboardSummaryProvider.future),
          child: _DashboardBody(summary: s),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final trial = s.trial;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        ContentWidth(
          child: Padding(
            padding: AppSpacing.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OrganizationHeader(summary: s),
                if (trial != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _TrialCallout(trial: trial),
                ],
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
                const SizedBox(height: AppSpacing.lg),
                const _SectionTitle('Overview'),
                const SizedBox(height: AppSpacing.sm),
                _Stats(summary: s),
                const SizedBox(height: AppSpacing.lg),
                const _SectionTitle('Quick actions'),
                const SizedBox(height: AppSpacing.sm),
                const _QuickActions(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _OrganizationHeader extends StatelessWidget {
  const _OrganizationHeader({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = summary.organizationStatus;
    return Card(
      child: Padding(
        padding: AppSpacing.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.organizationName,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (status != null) OrganizationStatusChip(status: status),
                TextButton.icon(
                  onPressed: () => context.push(Routes.ownerProfile),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit profile'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Organization status (`active`, `trial`, `suspended`, …) as a chip.
class OrganizationStatusChip extends StatelessWidget {
  const OrganizationStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final normalized = status.toLowerCase();
    final (bg, fg, icon) = switch (normalized) {
      'active' => (scheme.primaryContainer, scheme.onPrimaryContainer, Icons.check_circle_outline),
      'trial' || 'trialing' => (scheme.secondaryContainer, scheme.onSecondaryContainer, Icons.hourglass_top),
      'suspended' || 'inactive' || 'disabled' || 'cancelled' || 'canceled' || 'past_due' =>
        (scheme.errorContainer, scheme.onErrorContainer, Icons.error_outline),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant, Icons.info_outline),
    };
    final label = _humanize(normalized);
    return Semantics(
      label: 'Organization status: $label',
      excludeSemantics: true,
      child: Chip(
        avatar: Icon(icon, size: 18, color: fg),
        label: Text(label),
        labelStyle: TextStyle(color: fg),
        backgroundColor: bg,
        side: BorderSide.none,
      ),
    );
  }

  static String _humanize(String s) {
    final words = s.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (words.isEmpty) return 'Unknown';
    return words[0].toUpperCase() + words.substring(1);
  }
}

class _TrialCallout extends StatelessWidget {
  const _TrialCallout({required this.trial});

  final TrialInfo trial;

  @override
  Widget build(BuildContext context) {
    final ends = trial.endsAt == null ? null : DateFormat.yMMMd().format(trial.endsAt!);
    if (!trial.active) {
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
    final days = trial.daysRemaining;
    final remaining = switch (days) {
      null => null,
      0 => 'Your trial ends today',
      1 => '1 day left in your trial',
      _ => '$days days left in your trial',
    };
    final title = remaining ?? 'Free trial active';
    return Callout(
      tone: CalloutTone.info,
      title: title,
      message: [
        if (ends != null) 'Trial ends on $ends.',
        'You can activate unlimited cards during the trial.',
      ].join(' '),
      action: TextButton(
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
    final seats = s.unlimitedSeats
        ? StatTile(
            icon: Icons.badge_outlined,
            label: 'Active cards',
            value: '${s.activeCards}',
            caption: 'Unlimited during trial',
            semanticsLabel:
                'Active cards: ${s.activeCards}. Unlimited during trial.',
          )
        : StatTile(
            icon: Icons.badge_outlined,
            label: 'Active cards',
            value: '${s.activeCards} / ${s.paidSeats}',
            caption: s.paidSeats == 1 ? 'of 1 paid seat' : 'of ${s.paidSeats} paid seats',
            semanticsLabel:
                'Active cards: ${s.activeCards} of ${s.paidSeats} paid seats.',
            highlight: s.paidSeats > 0 && s.activeCards >= s.paidSeats,
          );
    final rating = s.totalReviews == 0 ? '—' : s.averageRating.toStringAsFixed(1);
    final tiles = [
      seats,
      StatTile(
        icon: Icons.style_outlined,
        label: 'Total cards',
        value: '${s.totalCards}',
      ),
      StatTile(
        icon: Icons.reviews_outlined,
        label: 'Total reviews',
        value: '${s.totalReviews}',
      ),
      StatTile(
        icon: Icons.star_rate_rounded,
        iconColor: AppColors.star,
        label: 'Average rating',
        value: rating,
        caption: s.totalReviews == 0 ? 'No reviews yet' : 'out of 5',
        semanticsLabel: s.totalReviews == 0
            ? 'Average rating: no reviews yet.'
            : 'Average rating: $rating out of 5.',
      ),
    ];
    return ResponsiveGrid(minTileWidth: 150, children: tiles);
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

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
      QuickActionTile(
        icon: Icons.storefront_outlined,
        label: 'Browse services',
        onTap: () => context.push(Routes.ownerShop),
      ),
    ];
    return ResponsiveGrid(minTileWidth: 140, children: actions);
  }
}
