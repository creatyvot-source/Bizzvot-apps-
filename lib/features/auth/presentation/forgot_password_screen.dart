import 'package:flutter/material.dart';
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

/// Forgot password (`POST /auth/forgot-password`).
///
/// Always shows the same neutral confirmation whether or not the account
/// exists, so the form can't be used to discover accounts. Only connectivity,
/// server failures and rate limits are surfaced as errors.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _cooldown = Cooldown(fallback: const Duration(seconds: 60));
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _cooldown.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_cooldown.active) return;
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    try {
      await ref.read(authFlowRepositoryProvider).forgotPassword(_email.text);
      _onSent();
    } catch (error) {
      if (!mounted) return;
      final e = AppException.from(error);
      switch (e.kind) {
        case AppErrorKind.rateLimited:
          _cooldown.startFrom(e);
          setState(() {});
        case AppErrorKind.network:
        case AppErrorKind.server:
          setState(() => _error = e.message);
        case AppErrorKind.cancelled:
          break;
        default:
          // 400/404/403 etc. must look identical to success.
          _onSent();
      }
    }
  }

  void _onSent() {
    if (!mounted) return;
    // Throttle resends regardless of outcome.
    _cooldown.start(const Duration(seconds: 60));
    setState(() => _sent = true);
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.welcome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_sent) {
      return AuthPage(
        title: 'Reset password',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.lg),
            ExcludeSemantics(
              child: Icon(
                Icons.mark_email_read_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                'Check your email',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AuthMessages.forgotNeutral,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Team members: if you don’t receive an email, ask your '
              'organization owner to reset your password.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _close,
              child: const Text('Back to sign in'),
            ),
            const SizedBox(height: AppSpacing.sm),
            ListenableBuilder(
              listenable: _cooldown,
              builder: (context, _) => TextButton(
                onPressed: _cooldown.active
                    ? null
                    : () => setState(() => _sent = false),
                child: Text(
                  _cooldown.active
                      ? 'Send again in ${formatCooldown(_cooldown.secondsLeft)}'
                      : 'Use a different email or send again',
                ),
              ),
            ),
          ],
        ),
      );
    }

    return AuthPage(
      title: 'Reset password',
      heading: 'Forgot your password?',
      subheading: 'Enter the email you sign in with and we’ll send you a link to choose a new password.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Callout(tone: CalloutTone.error, message: _error!),
              const SizedBox(height: AppSpacing.md),
            ],
            EmailField(
              controller: _email,
              autofocus: true,
              validator: Validators.email,
              textInputAction: TextInputAction.send,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.lg),
            CooldownSubmitButton(
              label: 'Send reset link',
              cooldown: _cooldown,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
