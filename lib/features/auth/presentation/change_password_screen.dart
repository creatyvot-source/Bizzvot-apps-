import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utilities/validators.dart';
import '../../../shared/widgets/feedback.dart';
import '../data/auth_flow_repository.dart';
import 'widgets/auth_page.dart';
import 'widgets/callout.dart';
import 'widgets/cooldown.dart';
import 'widgets/password_field.dart';

/// Change password for the signed-in owner or staff member
/// (`POST /auth/change-password`).
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final _cooldown = Cooldown();
  Map<String, String> _fieldErrors = const {};
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
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
    try {
      await ref
          .read(authFlowRepositoryProvider)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      TextInput.finishAutofillContext();
      if (!mounted) return;
      showMessage(context, 'Password changed');
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop();
      } else {
        _formKey.currentState?.reset();
        _current.clear();
        _next.clear();
        _confirm.clear();
      }
    } catch (error) {
      if (!mounted) return;
      final e = AppException.from(error);
      final stillSignedIn = ref.read(sessionControllerProvider) is SignedIn;
      setState(() {
        switch (e.kind) {
          case AppErrorKind.rateLimited:
            _cooldown.startFrom(e);
          case AppErrorKind.validation || AppErrorKind.forbidden
              when e.fieldErrors.isNotEmpty:
            _fieldErrors = e.fieldErrors;
          case AppErrorKind.unauthenticated when stillSignedIn:
            // Some backends answer a wrong current password with 401.
            _fieldErrors = const {
              'currentPassword': 'Current password is incorrect',
            };
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
      title: 'Change password',
      subheading:
          'Use at least 8 characters. You’ll stay signed in on this device.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Callout(tone: CalloutTone.error, message: _error!),
              gap,
            ],
            PasswordField(
              controller: _current,
              label: 'Current password',
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.isEmpty)
                  ? 'Current password is required'
                  : null,
              errorText:
                  _fieldErrors['currentPassword'] ??
                  _fieldErrors['oldPassword'],
              onChanged: (_) {
                _clearFieldError('currentPassword');
                _clearFieldError('oldPassword');
              },
            ),
            gap,
            PasswordField(
              controller: _next,
              label: 'New password',
              isNewPassword: true,
              textInputAction: TextInputAction.next,
              validator: (v) {
                final base = Validators.password(v);
                if (base != null) return base;
                if (v == _current.text) {
                  return 'Choose a password different from your current one';
                }
                return null;
              },
              errorText:
                  _fieldErrors['newPassword'] ?? _fieldErrors['password'],
              onChanged: (_) {
                _clearFieldError('newPassword');
                _clearFieldError('password');
              },
            ),
            gap,
            PasswordField(
              controller: _confirm,
              label: 'Confirm new password',
              isNewPassword: true,
              validator: (v) =>
                  v != _next.text ? 'Passwords don’t match' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.lg),
            CooldownSubmitButton(
              label: 'Change password',
              cooldown: _cooldown,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
