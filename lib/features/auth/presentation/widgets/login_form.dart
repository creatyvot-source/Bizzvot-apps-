import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/utilities/validators.dart';
import '../../data/auth_flow_repository.dart';
import '../../domain/auth_errors.dart';
import 'auth_page.dart';
import 'callout.dart';
import 'cooldown.dart';
import 'password_field.dart';

/// Single sign-in form for the mobile app. Staff accounts sign in via the web
/// portal; the mobile app is for organization accounts.
class LoginForm extends ConsumerStatefulWidget {
  const LoginForm({super.key, this.portal});

  final LoginPortal? portal;

  @override
  ConsumerState<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  final _cooldown = Cooldown();
  bool _dismissedExpiry = false;
  LoginFailure? _failure;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    _cooldown.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_cooldown.active) return;
    setState(() => _failure = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final repo = ref.read(authFlowRepositoryProvider);
    try {
      await repo.login(_email.text, _password.text);
      TextInput.finishAutofillContext();
    } catch (error) {
      if (!mounted) return;
      final failure = classifyLoginError(
        error,
        portal: LoginPortal.owner,
      );
      if (failure.kind == LoginFailureKind.rateLimited) {
        _cooldown.start(failure.retryAfter ?? _cooldown.fallback);
      }
      if (failure.kind == LoginFailureKind.invalidCredentials) {
        _password.clear();
      }
      setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    final session = ref.watch(sessionControllerProvider);
    final expired =
        session is SignedOut && session.expired && !_dismissedExpiry;

    return AuthPage(
      title: 'Sign in',
      automaticallyImplyLeading: false,
      heading: 'Welcome back',
      subheading: 'Sign in to manage your organization, people and cards.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (expired) ...[
              Callout(
                tone: CalloutTone.warning,
                title: 'You’ve been signed out',
                message:
                    'Your session ended for security reasons. Please sign in again to continue.',
                onDismiss: () => setState(() => _dismissedExpiry = true),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (failure != null &&
                failure.kind != LoginFailureKind.rateLimited) ...[
              Callout(
                tone: failure.kind == LoginFailureKind.wrongPortal
                    ? CalloutTone.info
                    : CalloutTone.error,
                title: switch (failure.kind) {
                  LoginFailureKind.wrongPortal => 'Staff account',
                  LoginFailureKind.adminAccount => 'Admin account',
                  LoginFailureKind.invalidCredentials => 'Couldn’t sign you in',
                  _ => null,
                },
                message: failure.message,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            EmailField(
              controller: _email,
              validator: Validators.email,
              onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
            ),
            const SizedBox(height: AppSpacing.md),
            PasswordField(
              controller: _password,
              focusNode: _passwordFocus,
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Password is required' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => context.push(Routes.forgotPassword),
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            CooldownSubmitButton(
              label: 'Sign in',
              cooldown: _cooldown,
              onPressed: _submit,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            _FooterLink(
              prompt: 'New to Bizzvot?',
              label: 'Create an organization',
              onPressed: () => context.push(Routes.register),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({
    required this.prompt,
    required this.label,
    required this.onPressed,
  });

  final String prompt;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(prompt, style: Theme.of(context).textTheme.bodyMedium),
        TextButton(onPressed: onPressed, child: Text(label)),
      ],
    );
  }
}
