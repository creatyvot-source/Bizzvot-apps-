import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/auth/session_controller.dart';
import '../../../shared/widgets/ui_kit.dart';
import 'widgets/callout.dart';

/// Entry point for signed-out users: choose owner sign-in, staff sign-in or
/// registration. Shows a notice when the previous session ended on its own
/// (refresh failed / revoked).
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _dismissedExpiry = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final expired =
        session is SignedOut && session.expired && !_dismissedExpiry;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: AppSpacing.page,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - AppSpacing.md * 2,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (expired) ...[
                        Callout(
                          tone: CalloutTone.warning,
                          title: 'You’ve been signed out',
                          message: 'Your session ended for security reasons. Please sign in again to continue.',
                          onDismiss: () =>
                              setState(() => _dismissedExpiry = true),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      const HeroHeader(
                        title: 'Bizzvot',
                        subtitle: 'Digital business cards, reviews and services for your whole team.',
                        trailing: ExcludeSemantics(
                          child: Icon(
                            Icons.contact_page_outlined,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      FilledButton.icon(
                        onPressed: () => context.push(Routes.login),
                        icon: const Icon(Icons.login),
                        label: const Text('Sign in'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton.icon(
                        onPressed: () => context.push(Routes.register),
                        icon: const Icon(Icons.add_business_outlined),
                        label: const Text('Create an organization'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Start with a free trial. No payment needed to sign up.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => context.push(Routes.legal),
                          icon: const Icon(Icons.policy_outlined),
                          label: const Text('Privacy & legal'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
