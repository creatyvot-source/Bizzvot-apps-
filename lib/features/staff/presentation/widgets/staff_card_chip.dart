import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../shared/models/card.dart';
import '../../domain/staff_draft.dart';

/// Card status chip: Active / Disabled / Disabled by billing / No card.
class StaffCardChip extends StatelessWidget {
  const StaffCardChip({super.key, required this.state});

  final StaffCardState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, icon) = switch (state) {
      StaffCardState.active => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.check_circle_outline,
        ),
      StaffCardState.disabledByBilling => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          Icons.credit_card_off_outlined,
        ),
      StaffCardState.disabled => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Icons.pause_circle_outline,
        ),
      StaffCardState.none => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Icons.remove_circle_outline,
        ),
    };
    return Semantics(
      label: 'Card: ${state.label}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  state.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Per-card directory visibility (Inherit / Public / Private).
class CardVisibilityChip extends StatelessWidget {
  const CardVisibilityChip({super.key, required this.visibility});

  final CardVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label) = switch (visibility) {
      CardVisibility.public => (Icons.public, 'Public'),
      CardVisibility.private => (Icons.lock_outline, 'Private'),
      CardVisibility.inherit => (Icons.sync_alt, 'Org default'),
    };
    return Semantics(
      label: 'Directory visibility: ${visibility.label}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
