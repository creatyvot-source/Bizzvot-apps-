import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Read-only star row. Announced as a single "Rated N out of 5" label.
class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.rating, this.size = 18});

  /// 0–5; fractions render as half stars.
  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final r = rating.clamp(0, 5).toDouble();
    final label = r == r.roundToDouble()
        ? r.toInt().toString()
        : r.toStringAsFixed(1);
    return Semantics(
      container: true,
      label: 'Rated $label out of 5',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              r >= i
                  ? Icons.star_rounded
                  : (r >= i - 0.5
                        ? Icons.star_half_rounded
                        : Icons.star_outline_rounded),
              size: size,
              color: AppColors.star,
            ),
        ],
      ),
    );
  }
}

/// Accessible 1–5 star selector. Each star is a 48dp button with a tooltip;
/// the group exposes its current value and supports increase/decrease
/// gestures for screen readers.
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.errorText,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final String? errorText;

  static String describe(int v) => switch (v) {
    1 => 'Poor',
    2 => 'Fair',
    3 => 'Good',
    4 => 'Very good',
    5 => 'Excellent',
    _ => 'Not rated',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          label: 'Rating',
          value: value == 0
              ? 'Not rated'
              : '$value of 5 stars, ${describe(value)}',
          increasedValue: value < 5 ? '${value + 1} of 5 stars' : null,
          decreasedValue: value > 1 ? '${value - 1} of 5 stars' : null,
          onIncrease: enabled && value < 5 ? () => onChanged(value + 1) : null,
          onDecrease: enabled && value > 1 ? () => onChanged(value - 1) : null,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  key: ValueKey('star-$i'),
                  tooltip: '$i ${i == 1 ? 'star' : 'stars'}',
                  isSelected: i <= value,
                  iconSize: 36,
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTap,
                    minHeight: AppSpacing.minTap,
                  ),
                  onPressed: enabled ? () => onChanged(i) : null,
                  icon: const Icon(Icons.star_outline_rounded),
                  selectedIcon: const Icon(
                    Icons.star_rounded,
                    color: AppColors.star,
                  ),
                ),
              if (value > 0)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: ExcludeSemantics(
                    child: Text(
                      describe(value),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.sm,
              top: AppSpacing.xs,
            ),
            child: Text(
              errorText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
