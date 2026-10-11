import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Item specification for a modern icon category tab.
class CategoryTabItem {
  const CategoryTabItem({
    required this.id,
    required this.label,
    required this.icon,
    this.selectedIcon,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
}

/// Horizontal scrolling category tab bar with icons and text labels (Airbnb style).
/// Displays an active bottom underline and bold state for the selected item.
class CategoryIconTabBar extends StatelessWidget {
  const CategoryIconTabBar({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelected,
  });

  final List<CategoryTabItem> items;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.lg),
        itemBuilder: (context, index) {
          final item = items[index];
          final isSelected = item.id == (selectedId ?? '');
          final activeColor = isDark ? Colors.white : Colors.black;
          final inactiveColor = isDark
              ? theme.colorScheme.onSurfaceVariant
              : const Color(0xFF71717A);

          return InkWell(
            onTap: () => onSelected(item.id.isEmpty ? null : item.id),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? activeColor : Colors.transparent,
                    width: 2.2,
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isSelected
                        ? (item.selectedIcon ?? item.icon)
                        : item.icon,
                    size: 24,
                    color: isSelected ? activeColor : inactiveColor,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? activeColor : inactiveColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
