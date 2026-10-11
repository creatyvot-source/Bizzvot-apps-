import 'package:flutter/material.dart';

import '../../../../shared/models/card.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/staff_draft.dart';

/// Card status pill: Active / Disabled / Disabled by billing / No card.
class StaffCardChip extends StatelessWidget {
  const StaffCardChip({super.key, required this.state});

  final StaffCardState state;

  @override
  Widget build(BuildContext context) {
    final (tone, icon) = switch (state) {
      StaffCardState.active => (StatusTone.success, Icons.check_circle_outline),
      StaffCardState.disabledByBilling => (
        StatusTone.warning,
        Icons.credit_card_off_outlined,
      ),
      StaffCardState.disabled => (
        StatusTone.neutral,
        Icons.pause_circle_outline,
      ),
      StaffCardState.none => (StatusTone.neutral, Icons.remove_circle_outline),
    };
    return Semantics(
      label: 'Card: ${state.label}',
      excludeSemantics: true,
      child: StatusChip(state.label, tone: tone, icon: icon),
    );
  }
}

/// Per-card directory visibility (Inherit / Public / Private).
class CardVisibilityChip extends StatelessWidget {
  const CardVisibilityChip({super.key, required this.visibility});

  final CardVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final (icon, label, tone) = switch (visibility) {
      CardVisibility.public => (Icons.public, 'Public', StatusTone.info),
      CardVisibility.private => (
        Icons.lock_outline,
        'Private',
        StatusTone.neutral,
      ),
      CardVisibility.inherit => (
        Icons.sync_alt,
        'Org default',
        StatusTone.neutral,
      ),
    };
    return Semantics(
      label: 'Directory visibility: ${visibility.label}',
      excludeSemantics: true,
      child: StatusChip(label, tone: tone, icon: icon),
    );
  }
}
