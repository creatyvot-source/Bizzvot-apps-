import 'package:flutter/material.dart';

/// Password input with a show/hide toggle, platform autofill hints and
/// keyboard settings that avoid suggestions and autocorrect.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.isNewPassword = false,
    this.textInputAction = TextInputAction.done,
    this.onFieldSubmitted,
    this.validator,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.focusNode,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;

  /// Uses the `newPassword` autofill hint so password managers offer to
  /// generate and save a password.
  final bool isNewPassword;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;
  final String? helperText;

  /// Server-side error to display (e.g. from `AppException.fieldErrors`).
  final String? errorText;
  final bool enabled;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      obscureText: _obscured,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      autofillHints: [
        widget.isNewPassword
            ? AutofillHints.newPassword
            : AutofillHints.password,
      ],
      onFieldSubmitted: widget.onFieldSubmitted,
      onChanged: widget.onChanged,
      validator: widget.validator,
      forceErrorText: widget.errorText,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        helperMaxLines: 3,
        errorMaxLines: 3,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _obscured ? 'Show password' : 'Hide password',
          icon: Icon(
            _obscured
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      ),
    );
  }
}
