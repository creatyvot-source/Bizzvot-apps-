import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/money.dart';

export '../../../../shared/widgets/ui_kit.dart'
    show
        SectionHeader,
        StatusChip,
        StatusTone,
        SkeletonBox,
        SkeletonList,
        HeroHeader,
        StatTile;

/// Displays a server amount. Shows [fallback] when the server sent none —
/// the app never derives a price itself.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.money, {
    super.key,
    this.fallback = '—',
    this.style,
    this.prefix,
    this.textAlign,
  });

  final Money? money;
  final String fallback;
  final TextStyle? style;
  final String? prefix;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final text = money == null ? fallback : '${prefix ?? ''}${money!.format()}';
    return Text(text, style: style, textAlign: textAlign);
  }
}

(Color, Color) toneColors(BuildContext context, StatusTone tone) {
  final s = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  Color tint(Color c) => dark ? Color.lerp(c, Colors.white, 0.45)! : c;
  return switch (tone) {
    StatusTone.neutral => (s.surfaceContainerHighest, s.onSurfaceVariant),
    StatusTone.info => (s.primaryContainer, s.onPrimaryContainer),
    StatusTone.success => (
      AppColors.success.withValues(alpha: dark ? 0.25 : 0.12),
      tint(AppColors.success),
    ),
    StatusTone.warning => (
      AppColors.warning.withValues(alpha: dark ? 0.25 : 0.12),
      tint(AppColors.warning),
    ),
    StatusTone.danger => (s.errorContainer, s.onErrorContainer),
  };
}

/// Banner for billing / payment states (failed payment, grace period…).
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.title,
    required this.message,
    this.tone = StatusTone.info,
    this.icon,
    this.action,
  });

  final String title;
  final String message;
  final StatusTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = toneColors(context, tone);
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: tone == StatusTone.danger || tone == StatusTone.warning,
      child: Container(
        width: double.infinity,
        padding: AppSpacing.page,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon ??
                  switch (tone) {
                    StatusTone.danger => Icons.error_outline,
                    StatusTone.warning => Icons.warning_amber_outlined,
                    StatusTone.success => Icons.check_circle_outline,
                    _ => Icons.info_outline,
                  },
              color: fg,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(color: fg),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                  ),
                  if (action != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    action!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Label / value row that wraps instead of overflowing at large text sizes.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final Widget value;
  final bool emphasize;

  factory InfoRow.text(String label, String value, {bool emphasize = false}) =>
      InfoRow(label: label, value: Text(value), emphasize: emphasize);

  factory InfoRow.money(
    String label,
    Money? money, {
    bool emphasize = false,
    String fallback = '—',
    bool negative = false,
  }) => InfoRow(
    label: label,
    emphasize: emphasize,
    value: MoneyText(
      money,
      fallback: fallback,
      prefix: negative && money != null && !money.isNegative ? '−' : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = emphasize
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          );
    final valueStyle = emphasize
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: MergeSemantics(
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            Text(label, style: labelStyle),
            DefaultTextStyle.merge(
              style: valueStyle,
              textAlign: TextAlign.end,
              child: value,
            ),
          ],
        ),
      ),
    );
  }
}

/// Accessible − / value / + control with 48dp targets.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 99,
    this.label = 'Quantity',
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final int min;
  final int max;
  final String label;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      label: label,
      value: '$value',
      increasedValue: value < max ? '${value + 1}' : null,
      decreasedValue: value > min ? '${value - 1}' : null,
      onIncrease: enabled && value < max ? () => onChanged!(value + 1) : null,
      onDecrease: enabled && value > min ? () => onChanged!(value - 1) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.outlined(
            tooltip: 'Decrease $label',
            onPressed: enabled && value > min
                ? () => onChanged!(value - 1)
                : null,
            icon: const Icon(Icons.remove),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40),
            child: ExcludeSemantics(
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          IconButton.outlined(
            tooltip: 'Increase $label',
            onPressed: enabled && value < max
                ? () => onChanged!(value + 1)
                : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// Network image restricted to http(s) with a neutral placeholder.
class SafeNetworkImage extends StatelessWidget {
  const SafeNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.semanticLabel,
    this.placeholderIcon = Icons.image_outlined,
  });

  final String? url;
  final BoxFit fit;
  final String? semanticLabel;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          placeholderIcon,
          color: scheme.outline,
          semanticLabel: semanticLabel,
        ),
      ),
    );
    final u = url;
    if (u == null || !(u.startsWith('https://') || u.startsWith('http://'))) {
      return placeholder;
    }
    return Image.network(
      u,
      fit: fit,
      semanticLabel: semanticLabel,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder,
    );
  }
}
