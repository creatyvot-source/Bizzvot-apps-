import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Shared layout for signed-out forms: scrollable, keyboard-safe,
/// width-constrained on tablets and wrapped in an [AutofillGroup] so
/// password managers can save credentials on success.
class AuthPage extends StatelessWidget {
  const AuthPage({
    super.key,
    required this.title,
    required this.child,
    this.heading,
    this.subheading,
  });

  /// App bar title.
  final String title;

  /// Large in-page heading (defaults to none).
  final String? heading;
  final String? subheading;
  final Widget child;

  static const maxWidth = 480.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxWidth),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (heading != null) ...[
                      Semantics(
                        header: true,
                        child: Text(
                          heading!,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    if (subheading != null) ...[
                      Text(
                        subheading!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Email field with the right keyboard, autofill hints and no autocorrect.
class EmailField extends StatelessWidget {
  const EmailField({
    super.key,
    required this.controller,
    this.label = 'Email',
    this.validator,
    this.errorText,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.asUsername = true,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final String? errorText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  /// Adds the `username` hint so password managers pair it with a password.
  final bool asUsername;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.emailAddress,
      textInputAction: textInputAction,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      autofillHints: [
        if (asUsername) AutofillHints.username,
        AutofillHints.email,
      ],
      validator: validator,
      forceErrorText: errorText,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.mail_outline),
        errorMaxLines: 3,
      ),
    );
  }
}
