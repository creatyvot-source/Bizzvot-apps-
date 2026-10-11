import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Floating search pill capsule inspired by modern discovery interfaces (Airbnb style).
/// Displays a soft shadow, icon, title, subtitle, and right filter button.
class FloatingSearchCapsule extends StatelessWidget {
  const FloatingSearchCapsule({
    super.key,
    this.title = 'Find NFC Cards & Stands',
    this.subtitle = 'Review Stands · Smart Cards · Badges',
    this.onTap,
    this.onFilterTap,
    this.isFilterActive = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onFilterTap;
  final bool isFilterActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: '$title. $subtitle. Tap to search or filter.',
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isDark ? theme.colorScheme.surfaceContainerHigh : Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: isDark
                ? theme.colorScheme.outlineVariant
                : const Color(0xFFE5E7EB),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(32),
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 10,
              ),
              child: Row(
                children: [
                  // Leading Search Icon
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    ),
                    child: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Center Title & Subtitle Stack
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Trailing Filter Button
                  IconButton.outlined(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: isFilterActive
                          ? theme.colorScheme.primaryContainer
                          : Colors.transparent,
                      side: BorderSide(
                        color: isFilterActive
                            ? theme.colorScheme.primary
                            : (isDark
                                ? theme.colorScheme.outlineVariant
                                : const Color(0xFFE5E7EB)),
                      ),
                    ),
                    icon: Icon(
                      Icons.tune_rounded,
                      color: isFilterActive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    tooltip: 'Filters',
                    onPressed: onFilterTap ?? onTap,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
