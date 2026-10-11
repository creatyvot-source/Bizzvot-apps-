import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/session_controller.dart';
import '../shared/widgets/feedback.dart';
import '../shared/widgets/state_views.dart';
import 'routes.dart';
import 'theme.dart';

class _Tab {
  const _Tab(this.branch, this.icon, this.selectedIcon, this.label);
  final int branch;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Bottom-navigation shell for owner and staff. Staff tabs that their
/// permissions do not allow are not shown (the router also blocks them).
class RoleShell extends ConsumerWidget {
  const RoleShell({super.key, required this.shell, required this.owner});

  final StatefulNavigationShell shell;
  final bool owner;

  static const _ownerTabs = [
    _Tab(0, Icons.space_dashboard_outlined, Icons.space_dashboard, 'Dashboard'),
    _Tab(1, Icons.badge_outlined, Icons.badge, 'Cards'),
    _Tab(2, Icons.group_outlined, Icons.group, 'People'),
    _Tab(3, Icons.reviews_outlined, Icons.reviews, 'Reviews'),
    _Tab(4, Icons.menu, Icons.menu_open, 'More'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final tabs = owner
        ? _ownerTabs
        : [
            const _Tab(0, Icons.badge_outlined, Icons.badge, 'My card'),
            if (user?.permissions.viewReviews ?? false)
              const _Tab(1, Icons.reviews_outlined, Icons.reviews, 'Reviews'),
            const _Tab(2, Icons.insights_outlined, Icons.insights, 'Analytics'),
            const _Tab(3, Icons.menu, Icons.menu_open, 'More'),
          ];
    final selected = tabs.indexWhere((t) => t.branch == shell.currentIndex);

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected < 0 ? 0 : selected,
        onDestinationSelected: (i) {
          final branch = tabs[i].branch;
          shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
        },
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

/// "More" tab: secondary navigation, account and sign-out.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key, required this.owner});

  final bool owner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final theme = Theme.of(context);

    Widget tile(IconData icon, String title, String route, {String? subtitle}) =>
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(route),
        );

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.sm,
          ),
          child: Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ContentWidth(
        child: ListView(
          children: [
            if (user != null)
              ListTile(
                leading: CircleAvatar(
                  child: Text(
                    user.displayName.characters.first.toUpperCase(),
                  ),
                ),
                title: Text(user.displayName),
                subtitle: Text(
                  [user.organizationName, owner ? 'Owner' : 'Staff']
                      .whereType<String>()
                      .join(' · '),
                ),
              ),
            if (owner) ...[
              header('Organization'),
              tile(Icons.business_outlined, 'Organization profile', Routes.ownerProfile),
              tile(Icons.visibility_outlined, 'Public presence & visibility',
                  Routes.ownerVisibility),
              tile(Icons.notifications_outlined, 'Notifications',
                  Routes.ownerNotifications),
              header('Billing & shop'),
              tile(Icons.credit_card_outlined, 'Billing & seats', Routes.ownerBilling),
              tile(Icons.storefront_outlined, 'Services & Shop', Routes.ownerShop),
              tile(Icons.shopping_cart_outlined, 'Cart', Routes.ownerCart),
              tile(Icons.receipt_long_outlined, 'Orders', Routes.ownerOrders),
              tile(Icons.description_outlined, 'Invoices', Routes.ownerInvoices),
              tile(Icons.autorenew, 'Subscriptions & renewals',
                  Routes.ownerSubscriptions),
              header('Account'),
              tile(Icons.lock_outline, 'Security & password', Routes.ownerSecurity),
            ] else ...[
              header('My card'),
              tile(Icons.qr_code_2, 'QR & sharing', Routes.staffCardShare),
              header('Account'),
              tile(Icons.lock_outline, 'Change password', Routes.staffSecurity),
            ],
            const Divider(height: AppSpacing.xl),
            ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text('Sign out', style: TextStyle(color: theme.colorScheme.error)),
              onTap: () async {
                final ok = await confirmAction(
                  context,
                  title: 'Sign out?',
                  message: 'You will need to sign in again to manage your cards.',
                  confirmLabel: 'Sign out',
                );
                if (ok) await ref.read(sessionControllerProvider.notifier).logout();
              },
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(body: LoadingView(label: 'Starting Bizzvot…'));
  }
}

class UnsupportedRoleScreen extends ConsumerWidget {
  const UnsupportedRoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: EmptyView(
          icon: Icons.no_accounts_outlined,
          title: 'This account can’t use the app',
          message:
              'Sign in with an organization owner or staff account to continue.',
          action: OutlinedButton(
            onPressed: () => ref.read(sessionControllerProvider.notifier).logout(),
            child: const Text('Sign out'),
          ),
        ),
      ),
    );
  }
}

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: EmptyView(
        icon: Icons.explore_off_outlined,
        title: 'Page not found',
        message: 'This link may be broken or the page was removed.',
        action: FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Go home'),
        ),
      ),
    );
  }
}
