import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';

/// Snackbar helpers. Always pass errors through [showError] so messages are
/// mapped and never expose raw server output.
void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showError(BuildContext context, Object error) {
  final e = AppException.from(error);
  if (e.kind == AppErrorKind.cancelled) return;
  final theme = Theme.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: theme.colorScheme.errorContainer,
        content: Text(
          e.message,
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
      ),
    );
}

/// Destructive / consequential action confirmation. Returns true on confirm.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final theme = Theme.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Button that shows a spinner and disables itself while [onPressed] runs.
class BusyButton extends StatefulWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _busy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(widget.label);
    final button = widget.icon == null || _busy
        ? FilledButton(
            onPressed: widget.onPressed == null || _busy ? null : _run,
            child: child,
          )
        : FilledButton.icon(
            onPressed: widget.onPressed == null ? null : _run,
            icon: Icon(widget.icon),
            label: child,
          );
    return widget.expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
