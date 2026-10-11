import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/analytics_models.dart';
import 'analytics_providers.dart';

/// Card analytics. Owners pass [cardId]; staff ([staffMode]) see their
/// assigned card. Only aggregate counts are shown — never visitor
/// identifiers or IP addresses.
class CardAnalyticsScreen extends ConsumerWidget {
  const CardAnalyticsScreen({super.key, this.cardId, this.staffMode = false});

  final String? cardId;
  final bool staffMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = staffMode
        ? ref.watch(currentUserProvider.select((u) => u?.cardId))
        : cardId;
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: (id == null || id.isEmpty)
          ? EmptyView(
              icon: Icons.insights_outlined,
              title: 'No card assigned',
              message: staffMode
                  ? 'Analytics will appear here once your organization assigns you a card.'
                  : 'Select a card to see its analytics.',
            )
          : _AnalyticsBody(cardId: id),
    );
  }
}

class _AnalyticsBody extends ConsumerWidget {
  const _AnalyticsBody({required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsRangeProvider);
    final q = (cardId: cardId, range: range);
    final views = ref.watch(viewsStatsProvider(q));
    final reviews = ref.watch(reviewStatsProvider(q));
    final links = ref.watch(linkClicksProvider(q));

    Future<void> refresh() async {
      ref
        ..invalidate(viewsStatsProvider(q))
        ..invalidate(reviewStatsProvider(q))
        ..invalidate(linkClicksProvider(q));
      try {
        await Future.wait([
          ref.read(viewsStatsProvider(q).future),
          ref.read(reviewStatsProvider(q).future),
          ref.read(linkClicksProvider(q).future),
        ]);
      } catch (_) {}
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: AppSpacing.page,
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<AnalyticsRange>(
                  segments: [
                    for (final r in AnalyticsRange.values)
                      ButtonSegment(value: r, label: Text(r.label)),
                  ],
                  selected: {range},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) =>
                      ref.read(analyticsRangeProvider.notifier).select(s.first),
                ),
                const SizedBox(height: AppSpacing.md),
                _KpiGrid(views: views, reviews: reviews),
                const SizedBox(height: AppSpacing.md),
                _Section(
                  title: 'Views over time',
                  value: views,
                  onRetry: () => ref.invalidate(viewsStatsProvider(q)),
                  builder: (v) => ViewsChart(stats: v, range: range),
                ),
                const SizedBox(height: AppSpacing.md),
                _Section(
                  title: 'Rating breakdown',
                  value: reviews,
                  onRetry: () => ref.invalidate(reviewStatsProvider(q)),
                  builder: (r) => RatingBreakdown(stats: r),
                ),
                const SizedBox(height: AppSpacing.md),
                _Section(
                  title: 'Link clicks',
                  value: links,
                  onRetry: () => ref.invalidate(linkClicksProvider(q)),
                  builder: (l) => LinkBreakdown(clicks: l),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _number = NumberFormat.decimalPattern();

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.views, required this.reviews});

  final AsyncValue<ViewsStats> views;
  final AsyncValue<ReviewStats> reviews;

  String _v<T>(AsyncValue<T> a, String Function(T) f) {
    final value = a.value;
    if (value != null) return f(value);
    return a.hasError ? '—' : '…';
  }

  @override
  Widget build(BuildContext context) {
    final tiles = [
      (
        'Views',
        _v(views, (v) => _number.format(v.total)),
        Icons.visibility_outlined,
        null,
      ),
      (
        'Unique visitors',
        _v(views, (v) => v.unique == null ? '—' : _number.format(v.unique)),
        Icons.person_outline,
        AppColors.accent,
      ),
      (
        'Avg rating',
        _v(
          reviews,
          (r) => r.average == null || r.total == 0
              ? '—'
              : r.average!.toStringAsFixed(1),
        ),
        Icons.star_outline,
        AppColors.warning,
      ),
      (
        'Total reviews',
        _v(reviews, (r) => _number.format(r.total)),
        Icons.reviews_outlined,
        AppColors.success,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 560 ? 4 : 2;
        final w = (c.maxWidth - AppSpacing.sm * (cols - 1)) / cols;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final t in tiles)
              SizedBox(
                width: w,
                child: StatTile(
                  label: t.$1,
                  value: t.$2,
                  icon: t.$3,
                  color: t.$4,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Section<T> extends StatelessWidget {
  const _Section({
    required this.title,
    required this.value,
    required this.builder,
    required this.onRetry,
  });

  final String title;
  final AsyncValue<T> value;
  final Widget Function(T) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value.value;
    final Widget body;
    if (v != null) {
      body = builder(v);
    } else if (value.hasError) {
      final e = AppException.from(value.error!);
      body = Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(e.message)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
    } else {
      body = Semantics(
        label: 'Loading $title',
        child: const SkeletonBox(height: 140, radius: AppRadius.md),
      );
    }
    return Card(
      child: Padding(
        padding: AppSpacing.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: AppSpacing.md),
            body,
          ],
        ),
      ),
    );
  }
}

/// Line chart with a spoken summary and an expandable table fallback.
class ViewsChart extends StatelessWidget {
  const ViewsChart({super.key, required this.stats, required this.range});

  final ViewsStats stats;
  final AnalyticsRange range;

  String summary() {
    final s = stats.series;
    final buf = StringBuffer(
      'Views over the last ${range.days} days: ${stats.total} total',
    );
    if (stats.unique != null) buf.write(', ${stats.unique} unique visitors');
    if (s.isNotEmpty) {
      final peak = s.reduce((a, b) => b.count > a.count ? b : a);
      buf.write(
        '. Busiest day ${DateFormat.yMMMd().format(peak.date)} with ${peak.count} views',
      );
    }
    return '$buf.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final series = stats.series;
    if (series.isEmpty) {
      return Text(
        stats.total == 0 ? 'No views in this period yet.' : summary(),
        style: theme.textTheme.bodyMedium,
      );
    }
    final hasUnique = series.any((p) => p.unique != null);
    final maxY = series
        .map((p) => math.max(p.count, p.unique ?? 0))
        .fold<int>(0, math.max)
        .toDouble();
    final step = math.max(1, (series.length / 4).ceil());
    final primary = theme.colorScheme.primary;
    final secondary = theme.colorScheme.tertiary;

    final chart = SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.15,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: theme.colorScheme.outlineVariant, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: true),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(
                    meta.formattedValue,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: step.toDouble(),
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (i < 0 || i >= series.length || v != i.toDouble()) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      DateFormat.MMMd().format(series[i].date),
                      style: theme.textTheme.labelSmall,
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < series.length; i++)
                  FlSpot(i.toDouble(), series[i].count.toDouble()),
              ],
              color: primary,
              barWidth: 3,
              isCurved: true,
              preventCurveOverShooting: true,
              dotData: FlDotData(show: series.length <= 14),
              belowBarData: BarAreaData(
                show: true,
                color: primary.withValues(alpha: 0.12),
              ),
            ),
            if (hasUnique)
              LineChartBarData(
                spots: [
                  for (var i = 0; i < series.length; i++)
                    FlSpot(i.toDouble(), (series[i].unique ?? 0).toDouble()),
                ],
                color: secondary,
                barWidth: 2,
                isCurved: true,
                preventCurveOverShooting: true,
                dashArray: const [6, 4],
                dotData: const FlDotData(show: false),
              ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: summary(),
          image: true,
          excludeSemantics: true,
          child: chart,
        ),
        const SizedBox(height: AppSpacing.sm),
        ExcludeSemantics(
          child: Wrap(
            spacing: AppSpacing.md,
            children: [
              _Legend(color: primary, label: 'Views'),
              if (hasUnique)
                _Legend(color: secondary, label: 'Unique visitors'),
            ],
          ),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('View as table'),
          children: [
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(),
                2: FlexColumnWidth(),
              },
              children: [
                TableRow(
                  children: [
                    _cell(context, 'Date', header: true),
                    _cell(context, 'Views', header: true, end: true),
                    if (hasUnique)
                      _cell(context, 'Unique', header: true, end: true)
                    else
                      const SizedBox(),
                  ],
                ),
                for (final p in series.reversed)
                  TableRow(
                    children: [
                      _cell(context, DateFormat.yMMMd().format(p.date)),
                      _cell(context, _number.format(p.count), end: true),
                      if (hasUnique)
                        _cell(
                          context,
                          p.unique == null ? '—' : _number.format(p.unique),
                          end: true,
                        )
                      else
                        const SizedBox(),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    String text, {
    bool header = false,
    bool end = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Text(
      text,
      textAlign: end ? TextAlign.end : TextAlign.start,
      style: header
          ? Theme.of(context).textTheme.labelLarge
          : Theme.of(context).textTheme.bodyMedium,
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 12, color: color),
      const SizedBox(width: AppSpacing.xs),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

/// Horizontal bar row: label, proportional bar, count. Announced as text,
/// so the rows double as the accessible table.
class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.count,
    required this.max,
    required this.spoken,
  });

  final String label;
  final int count;
  final int max;
  final String spoken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: spoken,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Flexible(
              flex: 3,
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: max == 0 ? 0 : count / max,
                  minHeight: 10,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(_number.format(count), style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}

class RatingBreakdown extends StatelessWidget {
  const RatingBreakdown({super.key, required this.stats});

  final ReviewStats stats;

  @override
  Widget build(BuildContext context) {
    final sum = stats.breakdown.values.fold(0, (a, b) => a + b);
    if (stats.total == 0 && sum == 0) {
      return const Text('No reviews yet.');
    }
    final max = stats.breakdown.values.fold(0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stats.series.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text('${stats.newInPeriod} new in this period'),
          ),
        for (var star = 5; star >= 1; star--)
          _BarRow(
            label: '$star ${star == 1 ? 'star' : 'stars'}',
            count: stats.breakdown[star] ?? 0,
            max: max,
            spoken:
                '$star ${star == 1 ? 'star' : 'stars'}: ${stats.breakdown[star] ?? 0} ${(stats.breakdown[star] ?? 0) == 1 ? 'review' : 'reviews'}',
          ),
      ],
    );
  }
}

class LinkBreakdown extends StatelessWidget {
  const LinkBreakdown({super.key, required this.clicks});

  final LinkClicks clicks;

  @override
  Widget build(BuildContext context) {
    if (clicks.counts.isEmpty) {
      return const Text('No link clicks in this period.');
    }
    final max = clicks.counts.first.$2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (cat, count) in clicks.counts)
          _BarRow(
            label: cat.label,
            count: count,
            max: max,
            spoken: '${cat.label}: $count ${count == 1 ? 'click' : 'clicks'}',
          ),
      ],
    );
  }
}
