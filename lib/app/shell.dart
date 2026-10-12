import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/auth/session_controller.dart';
import '../core/config/app_config.dart';
import '../features/cart_checkout/presentation/cart_checkout_providers.dart';
import '../shared/widgets/feedback.dart';
import '../shared/widgets/floating_navigation_menu.dart';
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

/// Floating bottom-navigation shell for owner and staff.
/// Includes 5 tabs: Dashboard/MyCard, Directory, Shop, Cart (with live badge), and More.
class RoleShell extends ConsumerWidget {
  const RoleShell({super.key, required this.shell, required this.owner});

  final StatefulNavigationShell shell;
  final bool owner;

  static const _ownerTabs = [
    _Tab(0, Icons.space_dashboard_outlined, Icons.space_dashboard, 'Dashboard'),
    _Tab(1, Icons.contact_phone_outlined, Icons.contact_phone, 'Directory'),
    _Tab(2, Icons.storefront_outlined, Icons.storefront, 'Shop'),
    _Tab(3, Icons.shopping_cart_outlined, Icons.shopping_cart, 'Cart'),
    _Tab(4, Icons.grid_view_outlined, Icons.grid_view, 'More'),
  ];

  static const _staffTabs = [
    _Tab(0, Icons.badge_outlined, Icons.badge, 'My card'),
    _Tab(1, Icons.contact_phone_outlined, Icons.contact_phone, 'Directory'),
    _Tab(2, Icons.storefront_outlined, Icons.storefront, 'Shop'),
    _Tab(3, Icons.shopping_cart_outlined, Icons.shopping_cart, 'Cart'),
    _Tab(4, Icons.grid_view_outlined, Icons.grid_view, 'More'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = owner ? _ownerTabs : _staffTabs;
    final selected = tabs.indexWhere((t) => t.branch == shell.currentIndex);
    final cartCount = ref.watch(cartCountProvider);

    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: FloatingNavigationMenu(
        selectedIndex: selected < 0 ? 0 : selected,
        onDestinationSelected: (i) {
          final branch = tabs[i].branch;
          shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
        },
        items: [
          for (final t in tabs)
            FloatingNavItem(
              icon: t.icon,
              selectedIcon: t.selectedIcon,
              label: t.label,
              badge: (t.label == 'Cart' && cartCount > 0) ? '$cartCount' : null,
            ),
        ],
      ),
    );
  }
}

/// "More" tab: secondary navigation, account, subscription pricing and sign-out.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key, required this.owner});

  final bool owner;

  static const _supportPhone = '+91 89215 04090';

  Future<void> _openWhatsApp() async {
    final cleaned = _supportPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final msg = Uri.encodeComponent(
      'Hi BizzVcard Support, I need help with my digital card and subscription.',
    );
    final uri = Uri.parse('https://wa.me/$cleaned?text=$msg');
    HapticFeedback.lightImpact();
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _makeCall() async {
    final cleaned = _supportPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    HapticFeedback.lightImpact();
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final config = ref.watch(currentConfigProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget tile(
      IconData icon,
      String title,
      String route, {
      String? subtitle,
      Widget? trailing,
    }) =>
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: trailing ?? const Icon(Icons.chevron_right),
          onTap: () => context.push(route),
        );

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Text(
            text,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
        actions: const [
          ThemeToggleActionButton(),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 110),
          children: [
            if (user != null)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  child: Text(
                    user.displayName.characters.first.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                title: Text(
                  user.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [user.organizationName, owner ? 'Organization Owner' : 'Staff Card Member']
                      .whereType<String>()
                      .join(' · '),
                ),
              ),

            // Subscription & Pricing Banner (First time 499 + yearly 199)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                        : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white12 : const Color(0xFF93C5FD),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.card_membership, color: Color(0xFF2563EB), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Staff & Card Subscription Plan',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : const Color(0xFF1E40AF),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '₹499 first-time activation · ₹199/year renewal per card & staff seat. Manage all team cards anytime.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : const Color(0xFF1E3A8A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => context.push(Routes.ownerSeats),
                          child: const Text('Add Staff Seats', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => context.push(Routes.ownerSubscriptions),
                          child: const Text('View Plan', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            header('Appearance'),
            const ThemeModeSelector(),

            if (owner) ...[
              header('Team & Cards Management'),
              tile(Icons.badge_outlined, 'Digital Cards', Routes.ownerCards,
                  subtitle: 'Manage all organization business cards'),
              tile(Icons.people_alt_outlined, 'Staff Members', Routes.ownerStaff,
                  subtitle: 'Add staff, assign cards and permissions'),
              tile(Icons.reviews_outlined, 'Reviews & Feedback', Routes.ownerReviews,
                  subtitle: 'Google reviews & incoming feedback'),

              header('Organization'),
              tile(Icons.business_outlined, 'Organization profile', Routes.ownerProfile),
              tile(Icons.visibility_outlined, 'Public presence & visibility',
                  Routes.ownerVisibility),
              if (config.isEnabled(Flags.notifications))
                tile(Icons.notifications_outlined, 'Notifications',
                    Routes.ownerNotifications),

              header('Billing, Shop & Reseller'),
              tile(Icons.credit_card_outlined, 'Billing & seats', Routes.ownerBilling,
                  subtitle: '₹499 setup · ₹199/yr renewal plan'),
              if (config.isEnabled(Flags.shop)) ...[
                tile(Icons.storefront_outlined, 'Store & Products', Routes.ownerShop),
                tile(Icons.shopping_cart_outlined, 'Cart', Routes.ownerCart),
                tile(Icons.receipt_long_outlined, 'Orders', Routes.ownerOrders),
              ],
              tile(Icons.description_outlined, 'Invoices', Routes.ownerInvoices),
              tile(Icons.autorenew, 'Subscriptions & renewals',
                  Routes.ownerSubscriptions),

              header('Support & Helpline (+91 89215 04090)'),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: Color(0xFF25D366)),
                title: const Text('WhatsApp Helpline'),
                subtitle: const Text('+91 89215 04090 (Reseller & Orders)'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: _openWhatsApp,
              ),
              ListTile(
                leading: const Icon(Icons.call, color: Colors.blue),
                title: const Text('Direct Phone Call'),
                subtitle: const Text('+91 89215 04090'),
                trailing: const Icon(Icons.phone_forwarded, size: 18),
                onTap: _makeCall,
              ),

              header('Account & Security'),
              tile(Icons.lock_outline, 'Security & password', Routes.ownerSecurity),
              tile(Icons.policy_outlined, 'Privacy & legal', Routes.legal),
              tile(Icons.person_remove_outlined, 'Delete account',
                  Routes.ownerDeleteAccount),
            ] else ...[
              header('My Card Details'),
              tile(Icons.badge_outlined, 'View My Card', Routes.staffCard),
              tile(Icons.edit_outlined, 'Edit Card Details', Routes.staffCardEdit,
                  subtitle: 'Update your links, phone, and profile photo'),
              tile(Icons.qr_code_2, 'QR & Sharing', Routes.staffCardShare),
              tile(Icons.reviews_outlined, 'My Reviews', Routes.staffReviews),

              header('Support & Helpline (+91 89215 04090)'),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: Color(0xFF25D366)),
                title: const Text('WhatsApp Helpline'),
                subtitle: const Text('+91 89215 04090'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: _openWhatsApp,
              ),

              header('Account'),
              tile(Icons.lock_outline, 'Change password', Routes.staffSecurity),
              tile(Icons.policy_outlined, 'Privacy & legal', Routes.legal),
              tile(Icons.person_remove_outlined, 'Delete account',
                  Routes.staffDeleteAccount),
            ],

            const Divider(height: AppSpacing.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
                onPressed: () async {
                  final ok = await confirmAction(
                    context,
                    title: 'Sign out?',
                    message: 'You’ll need to sign back in with your password.',
                    confirmLabel: 'Sign out',
                  );
                  if (ok && context.mounted) {
                    await ref.read(sessionControllerProvider.notifier).logout();
                  }
                },
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
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
