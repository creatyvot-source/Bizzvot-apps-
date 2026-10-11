import 'package:flutter/material.dart';

import '../../../../shared/models/card.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/card_filters.dart';

/// Active / Disabled / Disabled by billing. Icon + text so meaning never
/// depends on color alone.
class CardStatusChip extends StatelessWidget {
  const CardStatusChip({super.key, required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = card.isActive
        ? (Icons.check_circle_outline, StatusTone.success)
        : card.disabledByBilling
        ? (Icons.credit_card_off_outlined, StatusTone.danger)
        : (Icons.pause_circle_outline, StatusTone.neutral);
    final label = cardStatusLabel(card);
    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: StatusChip(label, tone: tone, icon: icon),
    );
  }
}

/// Inherit / Public / Private directory visibility.
class CardVisibilityChip extends StatelessWidget {
  const CardVisibilityChip({super.key, required this.visibility});

  final CardVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = switch (visibility) {
      CardVisibility.inherit => (
        Icons.account_tree_outlined,
        StatusTone.neutral,
      ),
      CardVisibility.public => (Icons.public, StatusTone.info),
      CardVisibility.private => (Icons.lock_outline, StatusTone.warning),
    };
    final label = cardVisibilityShortLabel(visibility);
    return Semantics(
      label: 'Directory visibility: $label',
      excludeSemantics: true,
      child: StatusChip(label, tone: tone, icon: icon),
    );
  }
}
