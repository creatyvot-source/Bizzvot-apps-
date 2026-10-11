import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../shared/models/card.dart';
import '../../domain/card_filters.dart';

/// Small read-only status pill. Uses icon + text so meaning never depends
/// on color alone.
class InfoChip extends StatelessWidget {
  const InfoChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.semanticPrefix,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String? semanticPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: semanticPrefix == null ? label : '$semanticPrefix: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CardStatusChip extends StatelessWidget {
  const CardStatusChip({super.key, required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = card.isActive
        ? (Icons.check_circle_outline, AppColors.success)
        : card.disabledByBilling
            ? (Icons.credit_card_off_outlined, scheme.error)
            : (Icons.pause_circle_outline, scheme.outline);
    return InfoChip(
      label: cardStatusLabel(card),
      icon: icon,
      color: color,
      semanticPrefix: 'Status',
    );
  }
}

class CardVisibilityChip extends StatelessWidget {
  const CardVisibilityChip({super.key, required this.visibility});

  final CardVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (visibility) {
      CardVisibility.inherit => (Icons.account_tree_outlined, scheme.secondary),
      CardVisibility.public => (Icons.public, scheme.primary),
      CardVisibility.private => (Icons.lock_outline, scheme.tertiary),
    };
    return InfoChip(
      label: cardVisibilityShortLabel(visibility),
      icon: icon,
      color: color,
      semanticPrefix: 'Directory visibility',
    );
  }
}
