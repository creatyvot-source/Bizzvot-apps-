import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/auth/session_controller.dart';
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
    final expired = session is SignedOut && session.expired && !_dismissedExpiry;
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
                          message:
                              'Your session ended for security reasons. Please sign in again to continue.',
                          onDismiss: () =>
                              setState(() => _dismissedExpiry = true),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      ExcludeSemantics(
                        child: Icon(
                          Icons.contact_page_outlined,
                          size: 72,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Semantics(
                        header: true,
                        child: Text(
                          'Bizzvot',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Digital business cards, reviews and services for your team.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _RoleChoice(
                        icon: Icons.business_center_outlined,
                        title: 'I manage an organization',
                        subtitle: 'Owner sign-in',
                        onTap: () => context.push(Routes.login),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _RoleChoice(
                        icon: Icons.badge_outlined,
                        title: 'I’m a team member',
                        subtitle: 'Staff sign-in',
                        onTap: () => context.push(Routes.staffLogin),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      OutlinedButton.icon(
                        onPressed: () => context.push(Routes.register),
                        icon: const Icon(Icons.add_business_outlined),
                        label: const Text('Create an organization'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Start with a free trial. No payment needed to sign up.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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

class _RoleChoice extends StatelessWidget {
  const _RoleChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: Icon(icon),
          ),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
