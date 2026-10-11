import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utilities/validators.dart';
import '../data/auth_flow_repository.dart';
import 'widgets/auth_page.dart';
import 'widgets/callout.dart';
import 'widgets/cooldown.dart';
import 'widgets/password_field.dart';

/// Organization registration (`POST /auth/register`). Signs the new owner in
/// on success; the router then redirects to the dashboard.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _org = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _cooldown = Cooldown(fallback: const Duration(seconds: 60));

  Map<String, String> _fieldErrors = const {};
  String? _error;

  @override
  void dispose() {
    for (final c in [_org, _name, _email, _phone, _password, _confirm]) {
      c.dispose();
    }
    _cooldown.dispose();
    super.dispose();
  }

  void _clearFieldError(String key) {
    if (_fieldErrors.containsKey(key)) {
      setState(() => _fieldErrors = Map.of(_fieldErrors)..remove(key));
    }
  }

  Future<void> _submit() async {
    if (_cooldown.active) return;
    setState(() {
      _error = null;
      _fieldErrors = const {};
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final phone = _phone.text.trim();
    try {
      await ref.read(authFlowRepositoryProvider).register(
            RegisterRequest(
              organizationName: _org.text.trim(),
              name: _name.text.trim(),
              email: _email.text,
              password: _password.text,
              phone: phone.isEmpty ? null : phone,
            ),
          );
      TextInput.finishAutofillContext();
    } catch (error) {
      if (!mounted) return;
      final e = AppException.from(error);
      setState(() {
        switch (e.kind) {
          case AppErrorKind.rateLimited:
            _cooldown.startFrom(e);
          case AppErrorKind.conflict:
            // Neutral wording: does not confirm the email is registered.
            _error = 'We couldn’t create an account with these details. If you '
                'already have an account, sign in or reset your password.';
          case AppErrorKind.validation when e.fieldErrors.isNotEmpty:
            _fieldErrors = e.fieldErrors;
            _error = 'Please fix the highlighted fields.';
          default:
            _error = e.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.md);
    return AuthPage(
      title: 'Create organization',
      heading: 'Set up your organization',
      subheading:
          'You’ll be the owner. Add your team and their digital cards next.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Callout(tone: CalloutTone.error, message: _error!),
              gap,
            ],
            TextFormField(
              controller: _org,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.organizationName],
              validator: (v) => Validators.required(v, 'Organization name'),
              forceErrorText: _fieldErrors['organizationName'],
              onChanged: (_) => _clearFieldError('organizationName'),
              decoration: const InputDecoration(
                labelText: 'Organization name',
                prefixIcon: Icon(Icons.business_outlined),
              ),
            ),
            gap,
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              validator: (v) => Validators.required(v, 'Your name'),
              forceErrorText: _fieldErrors['name'],
              onChanged: (_) => _clearFieldError('name'),
              decoration: const InputDecoration(
                labelText: 'Your name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            gap,
            EmailField(
              controller: _email,
              label: 'Work email',
              validator: Validators.email,
              errorText: _fieldErrors['email'],
              onChanged: (_) => _clearFieldError('email'),
            ),
            gap,
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
              validator: Validators.optionalPhone,
              forceErrorText: _fieldErrors['phone'],
              onChanged: (_) => _clearFieldError('phone'),
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            gap,
            PasswordField(
              controller: _password,
              isNewPassword: true,
              textInputAction: TextInputAction.next,
              helperText: 'At least 8 characters.',
              validator: Validators.password,
              errorText: _fieldErrors['password'],
              onChanged: (_) => _clearFieldError('password'),
            ),
            gap,
            PasswordField(
              controller: _confirm,
              label: 'Confirm password',
              isNewPassword: true,
              validator: (v) =>
                  v != _password.text ? 'Passwords don’t match' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.lg),
            CooldownSubmitButton(
              label: 'Create organization',
              cooldown: _cooldown,
              onPressed: _submit,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Already have an account?'),
                TextButton(
                  onPressed: () => context.pushReplacement(Routes.login),
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
