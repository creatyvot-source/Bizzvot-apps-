import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/models/organization.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../auth/presentation/widgets/callout.dart';
import '../domain/dashboard_overview.dart';
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
          const ThemeToggleActionButton(),
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push(Routes.ownerNotifications),
          ),
        ],
      ),
      body: summary.isLoading && !summary.hasValue
          ? const _DashboardSkeleton()
          : AsyncValueView<DashboardOverview>(
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

  final DashboardOverview summary;
  final bool shopEnabled;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final trial = s.trial;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 100),
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
                if (s.cardSlotsFull && s.disabledByBilling == 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  Callout(
                    tone: CalloutTone.info,
                    title: 'All card slots are in use',
                    message: 'Purchase more seats to add cards for new team members.',
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
                const SizedBox(height: AppSpacing.sm),
                const SectionHeader('NFC Tap & Conversion Insights'),
                _TapInsightsSection(summary: s),
                const SizedBox(height: AppSpacing.md),
                const _ResellerInsightCard(),
                const SizedBox(height: AppSpacing.sm),
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

  final DashboardOverview summary;

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
      subtitle:
          trialLine ??
          (summary.planExpiry != null
              ? 'Plan renews or expires on ${_formatDate(summary.planExpiry)}'
              : 'Here’s how your team is doing.'),
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

  final DashboardOverview summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final rating = s.totalReviews == 0
        ? '—'
        : s.averageRating.toStringAsFixed(1);
    final cardsCaption = s.unlimitedCards
        ? ((s.trial?.active ?? false)
              ? 'Unlimited during trial'
              : 'No card limit')
        : s.cardSlotsFull
        ? 'All card slots in use'
        : '${s.cardsLimit! - s.totalCards} of ${s.cardsLimit} slots free';
    final staffLimit = s.staffLimit;
    final tiles = [
      StatTile(
        icon: Icons.badge_outlined,
        label: 'Cards',
        value: s.unlimitedCards
            ? '${s.totalCards}'
            : '${s.totalCards} / ${s.cardsLimit}',
        caption: s.activeCards == null
            ? cardsCaption
            : '${s.activeCards} active · $cardsCaption',
        color: s.cardSlotsFull ? AppColors.warning : null,
        onTap: () => context.go(Routes.ownerCards),
      ),
      StatTile(
        icon: Icons.group_outlined,
        label: 'Staff',
        value: staffLimit == null
            ? '${s.staffCount}'
            : '${s.staffCount} / $staffLimit',
        caption: s.staffSlotsFull ? 'Staff limit reached' : null,
        color: s.staffSlotsFull ? AppColors.warning : null,
        onTap: () => context.go(Routes.ownerStaff),
      ),
      StatTile(
        icon: Icons.reviews_outlined,
        label: 'Reviews',
        value: '${s.totalReviews}',
        color: AppColors.accent,
        onTap: () => context.go(Routes.ownerReviews),
      ),
      StatTile(
        icon: Icons.star_rate_rounded,
        color: AppColors.star,
        label: 'Average rating',
        value: rating,
        caption: s.totalReviews == 0 ? 'No reviews yet' : 'out of 5 (approved)',
      ),
    ];
    return ResponsiveGrid(minTileWidth: 150, children: tiles);
  }
}

class _TapInsightsSection extends StatelessWidget {
  const _TapInsightsSection({required this.summary});

  final DashboardOverview summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.3)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      color: isDark ? theme.colorScheme.surfaceContainerHigh : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.insights_rounded,
                        color: theme.colorScheme.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Live Tap & Review Engagement',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '+28% this month',
                    style: TextStyle(
                      color: Color(0xFF15803D),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 3 Column Metrics
            Row(
              children: [
                _InsightMetricCol(
                  label: 'NFC Taps',
                  value: '1,280',
                  subtext: 'Contactless scans',
                  color: theme.colorScheme.primary,
                ),
                Container(height: 36, width: 1, color: theme.dividerColor),
                _InsightMetricCol(
                  label: 'vCard Saves',
                  value: '492',
                  subtext: 'Direct downloads',
                  color: const Color(0xFF3B82F6),
                ),
                Container(height: 36, width: 1, color: theme.dividerColor),
                _InsightMetricCol(
                  label: 'Review Rate',
                  value: '34.8%',
                  subtext: 'From NFC stands',
                  color: const Color(0xFFF59E0B),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Progress engagement bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: 0.82,
                minHeight: 6,
                backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '82% of customers tap via NFC on iOS & Android devices.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightMetricCol extends StatelessWidget {
  const _InsightMetricCol({
    required this.label,
    required this.value,
    required this.subtext,
    required this.color,
  });

  final String label;
  final String value;
  final String subtext;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            subtext,
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResellerInsightCard extends StatelessWidget {
  const _ResellerInsightCard();

  static const _supportPhone = '918921504090';

  Future<void> _openWhatsApp() async {
    final msg = Uri.encodeComponent(
      'Hi BizzVcard team, I want to learn more about the Reseller Program and earning 30% commission!',
    );
    final uri = Uri.parse('https://wa.me/$_supportPhone?text=$msg');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFFEA580C), Color(0xFFC2410C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEA580C).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  '⭐ 30% COMMISSION',
                  style: TextStyle(
                    color: Color(0xFFC2410C),
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
              const Text(
                'bizzVcard.com',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Become a BizzVcard Reseller',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Earn 30% commission on every Google Review Stand (₹499) and Digital Card (₹350/₹999) sold in your region. Full marketing support included.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFC2410C),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _openWhatsApp,
            icon: const Icon(Icons.chat_bubble_outline, size: 16),
            label: const Text(
              'Enquire on WhatsApp (+91 89215 04090)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );
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
