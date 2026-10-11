import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utilities/validators.dart';
import '../data/auth_flow_repository.dart';
import '../domain/auth_errors.dart';
import 'widgets/auth_page.dart';
import 'widgets/callout.dart';
import 'widgets/cooldown.dart';
import 'widgets/password_field.dart';

/// Reset password from an emailed link (`/reset-password?token=…`,
/// `POST /auth/reset-password`). The token is never displayed or logged.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.token});

  final String? token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _cooldown = Cooldown();
  bool _done = false;
  bool _invalidLink = false;
  String? _error;
  String? _passwordError;

  bool get _hasToken => (widget.token?.trim().isNotEmpty ?? false);

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _cooldown.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_cooldown.active) return;
    setState(() {
      _error = null;
      _passwordError = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    try {
      await ref
          .read(authFlowRepositoryProvider)
          .resetPassword(token: widget.token!.trim(), password: _password.text);
      TextInput.finishAutofillContext();
      if (mounted) setState(() => _done = true);
    } catch (error) {
      if (!mounted) return;
      final e = AppException.from(error);
      setState(() {
        if (e.kind == AppErrorKind.rateLimited) {
          _cooldown.startFrom(e);
        } else if (isInvalidResetToken(e)) {
          _invalidLink = true;
        } else if (e.fieldErrors['password'] != null) {
          _passwordError = e.fieldErrors['password'];
        } else {
          _error = e.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_hasToken || _invalidLink) {
      return AuthPage(
        title: 'Reset password',
        child: _Outcome(
          icon: Icons.link_off,
          iconColor: theme.colorScheme.error,
          title: 'Link not valid',
          message: AuthMessages.invalidResetLink,
          primaryLabel: 'Request a new link',
          onPrimary: () => context.go(Routes.forgotPassword),
          secondaryLabel: 'Back to sign in',
          onSecondary: () => context.go(Routes.login),
        ),
      );
    }

    if (_done) {
      return AuthPage(
        title: 'Reset password',
        child: _Outcome(
          icon: Icons.check_circle_outline,
          iconColor: theme.colorScheme.primary,
          title: 'Password updated',
          message: 'You can now sign in with your new password.',
          primaryLabel: 'Go to sign in',
          onPrimary: () => context.go(Routes.login),
        ),
      );
    }

    return AuthPage(
      title: 'Reset password',
      heading: 'Choose a new password',
      subheading: 'Use at least 8 characters. Avoid reusing an old password.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Callout(tone: CalloutTone.error, message: _error!),
              const SizedBox(height: AppSpacing.md),
            ],
            PasswordField(
              controller: _password,
              label: 'New password',
              isNewPassword: true,
              textInputAction: TextInputAction.next,
              validator: Validators.password,
              errorText: _passwordError,
              onChanged: (_) {
                if (_passwordError != null) {
                  setState(() => _passwordError = null);
                }
              },
            ),
            const SizedBox(height: AppSpacing.md),
            PasswordField(
              controller: _confirm,
              label: 'Confirm new password',
              isNewPassword: true,
              validator: (v) =>
                  v != _password.text ? 'Passwords don’t match' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.lg),
            CooldownSubmitButton(
              label: 'Update password',
              cooldown: _cooldown,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        ExcludeSemantics(child: Icon(icon, size: 64, color: iconColor)),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
        if (secondaryLabel != null && onSecondary != null) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
        ],
      ],
    );
  }
}
