import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FloatingNavItem {
  const FloatingNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String? badge;
}

/// Modern floating navigation capsule pill docking at the bottom of the screen.
/// Provides smooth animations, haptic feedback, subtle depth, and clear selection states.
class FloatingNavigationMenu extends StatelessWidget {
  const FloatingNavigationMenu({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<FloatingNavItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final background = isDark
        ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.90)
        : Colors.white.withValues(alpha: 0.92);

    final borderColor = isDark
        ? colorScheme.outlineVariant.withValues(alpha: 0.40)
        : colorScheme.outlineVariant.withValues(alpha: 0.60);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: 68,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: borderColor, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < items.length; i++)
                    _FloatingNavItemWidget(
                      item: items[i],
                      isSelected: i == selectedIndex,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onDestinationSelected(i);
                      },
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

class _FloatingNavItemWidget extends StatelessWidget {
  const _FloatingNavItemWidget({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final FloatingNavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final activeColor = colorScheme.primary;
    final inactiveColor = colorScheme.onSurfaceVariant;

    return Expanded(
      child: Semantics(
        selected: isSelected,
        button: true,
        label: item.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          splashColor: activeColor.withValues(alpha: 0.12),
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      isSelected ? item.selectedIcon : item.icon,
                      size: 22,
                      color: isSelected ? activeColor : inactiveColor,
                    ),
                    if (item.badge != null)
                      Positioned(
                        right: item.badge!.isNotEmpty ? -10 : -6,
                        top: -4,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: item.badge!.isNotEmpty ? 5 : 3,
                            vertical: item.badge!.isNotEmpty ? 1.5 : 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.error,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: BoxConstraints(
                            minWidth: item.badge!.isNotEmpty ? 16 : 8,
                            minHeight: item.badge!.isNotEmpty ? 16 : 8,
                          ),
                          child: item.badge!.isNotEmpty
                              ? Text(
                                  item.badge!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                  ),
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: theme.textTheme.labelSmall!.copyWith(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? activeColor : inactiveColor,
                    letterSpacing: 0.1,
                  ),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
