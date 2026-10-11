import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/utilities/validators.dart';
import '../../data/auth_flow_repository.dart';
import '../../domain/auth_errors.dart';
import '../auth_providers.dart';
import 'auth_page.dart';
import 'callout.dart';
import 'cooldown.dart';
import 'password_field.dart';

/// Sign-in form shared by owner and staff portals. On success the session
/// becomes `SignedIn` and the router redirects to the role's home.
class LoginForm extends ConsumerStatefulWidget {
  const LoginForm({super.key, required this.portal});

  final LoginPortal portal;

  @override
  ConsumerState<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  final _cooldown = Cooldown();
  LoginFailure? _failure;

  bool get _isOwner => widget.portal == LoginPortal.owner;

  @override
  void initState() {
    super.initState();
    // Prefill when guided here from the other portal.
    final hint = ref.read(loginEmailHintProvider);
    if (hint != null) {
      _email.text = hint;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(loginEmailHintProvider.notifier).take();
      });
    }
  }

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
      if (_isOwner) {
        await repo.loginOwner(_email.text, _password.text);
      } else {
        await repo.loginStaff(_email.text, _password.text);
      }
      TextInput.finishAutofillContext();
    } catch (error) {
      if (!mounted) return;
      final failure = classifyLoginError(error, portal: widget.portal);
      if (failure.kind == LoginFailureKind.rateLimited) {
        _cooldown.start(failure.retryAfter ?? _cooldown.fallback);
      }
      if (failure.kind == LoginFailureKind.invalidCredentials) {
        _password.clear();
      }
      setState(() => _failure = failure);
    }
  }

  void _switchPortal() {
    ref.read(loginEmailHintProvider.notifier).set(
          _email.text.trim().isEmpty ? null : _email.text.trim(),
        );
    context.pushReplacement(_isOwner ? Routes.staffLogin : Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    final otherPortalLabel = _isOwner ? 'Go to staff sign-in' : 'Go to owner sign-in';

    return AuthPage(
      title: _isOwner ? 'Owner sign-in' : 'Staff sign-in',
      heading: _isOwner ? 'Welcome back' : 'Sign in to your card',
      subheading: _isOwner
          ? 'Sign in to manage your organization, people and cards.'
          : 'Use the login email and password your organization gave you.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (failure != null &&
                failure.kind != LoginFailureKind.rateLimited) ...[
              Callout(
                tone: failure.kind == LoginFailureKind.wrongPortal
                    ? CalloutTone.info
                    : CalloutTone.error,
                title: switch (failure.kind) {
                  LoginFailureKind.wrongPortal => 'Try the other sign-in',
                  LoginFailureKind.adminAccount => 'Admin account',
                  LoginFailureKind.invalidCredentials => 'Couldn’t sign you in',
                  _ => null,
                },
                message: failure.message,
                action: failure.kind == LoginFailureKind.wrongPortal
                    ? FilledButton.tonal(
                        onPressed: _switchPortal,
                        child: Text(otherPortalLabel),
                      )
                    : null,
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
            if (_isOwner) ...[
              _FooterLink(
                prompt: 'Added by your organization?',
                label: 'Staff sign-in',
                onPressed: _switchPortal,
              ),
              _FooterLink(
                prompt: 'New to Bizzvot?',
                label: 'Create an organization',
                onPressed: () => context.pushReplacement(Routes.register),
              ),
            ] else ...[
              _FooterLink(
                prompt: 'Manage an organization?',
                label: 'Owner sign-in',
                onPressed: _switchPortal,
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'Can’t sign in? Your organization owner can update your '
                  'login email or reset your password.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
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
