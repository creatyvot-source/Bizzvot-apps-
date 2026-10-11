import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

enum CalloutTone { info, warning, error, success }

/// Inline, announced message block (errors, guidance, warnings). Used in
/// forms instead of transient snackbars when the user needs to act on it.
class Callout extends StatelessWidget {
  const Callout({
    super.key,
    required this.message,
    this.title,
    this.tone = CalloutTone.info,
    this.action,
    this.onDismiss,
  });

  final String? title;
  final String message;
  final CalloutTone tone;
  final Widget? action;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (bg, fg, icon) = switch (tone) {
      CalloutTone.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.info_outline,
      ),
      CalloutTone.warning => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.warning_amber_rounded,
      ),
      CalloutTone.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
      CalloutTone.success => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Icon(icon, color: fg)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        style: theme.textTheme.titleSmall?.copyWith(color: fg),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
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
              if (onDismiss != null)
                IconButton(
                  tooltip: 'Dismiss',
                  color: fg,
                  icon: const Icon(Icons.close),
                  onPressed: onDismiss,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
