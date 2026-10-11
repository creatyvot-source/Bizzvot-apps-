import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_user.dart';
import '../core/auth/session_controller.dart';
import '../features/account/presentation/delete_account_screen.dart';
import '../features/account/presentation/legal_screen.dart';
import '../features/analytics/presentation/card_analytics_screen.dart';
import '../features/auth/presentation/change_password_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/owner_login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/auth/presentation/staff_login_screen.dart';
import '../features/auth/presentation/welcome_screen.dart';
import '../features/billing/presentation/billing_screen.dart';
import '../features/billing/presentation/seat_purchase_screen.dart';
import '../features/cards/presentation/card_detail_screen.dart';
import '../features/cards/presentation/card_editor_screen.dart';
import '../features/cards/presentation/card_share_screen.dart';
import '../features/cards/presentation/cards_list_screen.dart';
import '../features/cards/presentation/my_card_screen.dart';
import '../features/cart_checkout/presentation/cart_screen.dart';
import '../features/cart_checkout/presentation/checkout_screen.dart';
import '../features/cart_checkout/presentation/payment_status_screen.dart';
import '../features/catalog/presentation/catalog_item_screen.dart';
import '../features/catalog/presentation/shop_home_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/directory_visibility/presentation/directory_visibility_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/orders/presentation/invoice_detail_screen.dart';
import '../features/orders/presentation/invoices_screen.dart';
import '../features/orders/presentation/order_detail_screen.dart';
import '../features/orders/presentation/orders_screen.dart';
import '../features/organization_profile/presentation/organization_profile_screen.dart';
import '../features/public_card/presentation/public_card_screen.dart';
import '../features/public_card/presentation/public_directory_screen.dart';
import '../features/public_card/presentation/write_review_screen.dart';
import '../features/reviews/presentation/reviews_screen.dart';
import '../features/staff/presentation/staff_editor_screen.dart';
import '../features/staff/presentation/staff_list_screen.dart';
import '../features/subscriptions_renewals/presentation/subscription_detail_screen.dart';
import '../features/subscriptions_renewals/presentation/subscriptions_screen.dart';
import 'routes.dart';
import 'shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Pure redirect logic, unit-tested in `test/app/router_redirect_test.dart`.
///
/// UI guards are a convenience only — the backend enforces every rule.
String? resolveRedirect(SessionState session, Uri uri) {
  final path = uri.path;

  // Public cards and directories never require a session.
  if (Routes.isPublic(path)) return null;

  switch (session) {
    case SessionRestoring():
      return path == Routes.splash ? null : Routes.splash;

    case SignedOut():
      if (Routes.isAuth(path)) return null;
      return Routes.welcome;

    case SignedIn(:final user):
      final home = homeFor(user);
      if (home == null) {
        return path == Routes.unsupported ? null : Routes.unsupported;
      }
      if (path == Routes.splash ||
          path == Routes.unsupported ||
          Routes.isAuth(path) ||
          path == '/') {
        return home;
      }
      if (user.isOwner && path.startsWith('/s/')) return home;
      if (user.isStaff) {
        if (path.startsWith('/o/')) return home;
        final p = user.permissions;
        if (path == Routes.staffCardEdit && !(p.editCard || p.manageLinks)) {
          return home;
        }
        if (path == Routes.staffReviews && !p.viewReviews) return home;
      }
      return null;
  }
}

String? homeFor(AuthUser user) => switch (user.role) {
      UserRole.owner => Routes.ownerDashboard,
      UserRole.staff => Routes.staffCard,
      _ => null,
    };

/// Bridges Riverpod session changes to go_router's refreshListenable.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    ref.listen(sessionControllerProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionListenable(ref);
  ref.onDispose(refresh.dispose);

  GoRoute r(String path, Widget Function(GoRouterState s) build) => GoRoute(
        path: path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, s) => build(s),
      );

  String p(GoRouterState s, String name) => s.pathParameters[name]!;

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) =>
        resolveRedirect(ref.read(sessionControllerProvider), state.uri),
    errorBuilder: (_, _) => const NotFoundScreen(),
    routes: [
      r(Routes.splash, (_) => const SplashScreen()),
      r(Routes.unsupported, (_) => const UnsupportedRoleScreen()),
      r(Routes.legal, (_) => const LegalScreen()),

      // Auth
      r(Routes.welcome, (_) => const WelcomeScreen()),
      r(Routes.login, (_) => const OwnerLoginScreen()),
      r(Routes.staffLogin, (_) => const StaffLoginScreen()),
      r(Routes.register, (_) => const RegisterScreen()),
      r(Routes.forgotPassword, (_) => const ForgotPasswordScreen()),
      r(Routes.resetPassword,
          (s) => ResetPasswordScreen(token: s.uri.queryParameters['token'])),

      // Public
      r('/card/:slug', (s) => PublicCardScreen(slug: p(s, 'slug'))),
      r('/card/:slug/review', (s) => WriteReviewScreen(slug: p(s, 'slug'))),
      r('/directory/:orgSlug',
          (s) => PublicDirectoryScreen(orgSlug: p(s, 'orgSlug'))),

      // Owner tabs
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _, shell) => RoleShell(shell: shell, owner: true),
        branches: [
          _branch(Routes.ownerDashboard, (_) => const DashboardScreen()),
          _branch(Routes.ownerCards, (_) => const CardsListScreen()),
          _branch(Routes.ownerStaff, (_) => const StaffListScreen()),
          _branch(Routes.ownerReviews, (_) => const ReviewsScreen()),
          _branch(Routes.ownerMore, (_) => const MoreScreen(owner: true)),
        ],
      ),

      // Owner screens. Static paths are declared before `:id` patterns.
      r(Routes.ownerStaffNew, (_) => const StaffEditorScreen()),
      r('/o/staff/:id', (s) => StaffEditorScreen(staffId: p(s, 'id'))),
      r('/o/cards/:id', (s) => CardDetailScreen(cardId: p(s, 'id'))),
      r('/o/cards/:id/edit', (s) => CardEditorScreen(cardId: p(s, 'id'))),
      r('/o/cards/:id/share', (s) => CardShareScreen(cardId: p(s, 'id'))),
      r('/o/cards/:id/analytics',
          (s) => CardAnalyticsScreen(cardId: p(s, 'id'))),
      r(Routes.ownerProfile, (_) => const OrganizationProfileScreen()),
      r(Routes.ownerVisibility, (_) => const DirectoryVisibilityScreen()),
      r(Routes.ownerBilling, (_) => const BillingScreen()),
      r(Routes.ownerSeats, (_) => const SeatPurchaseScreen()),
      r(Routes.ownerShop, (_) => const ShopHomeScreen()),
      r('/o/shop/:type/:id',
          (s) => CatalogItemScreen(type: p(s, 'type'), id: p(s, 'id'))),
      r(Routes.ownerCart, (_) => const CartScreen()),
      r(Routes.ownerCheckout, (_) => const CheckoutScreen()),
      r('/o/payment/:orderId',
          (s) => PaymentStatusScreen(orderId: p(s, 'orderId'))),
      r(Routes.ownerOrders, (_) => const OrdersScreen()),
      r('/o/orders/:id', (s) => OrderDetailScreen(orderId: p(s, 'id'))),
      r(Routes.ownerInvoices, (_) => const InvoicesScreen()),
      r('/o/invoices/:id',
          (s) => InvoiceDetailScreen(invoiceId: p(s, 'id'))),
      r(Routes.ownerSubscriptions, (_) => const SubscriptionsScreen()),
      r('/o/subscriptions/:id',
          (s) => SubscriptionDetailScreen(subscriptionId: p(s, 'id'))),
      r(Routes.ownerNotifications, (_) => const NotificationsScreen()),
      r(Routes.ownerSecurity, (_) => const ChangePasswordScreen()),
      r(Routes.ownerDeleteAccount, (_) => const DeleteAccountScreen()),

      // Staff tabs
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _, shell) => RoleShell(shell: shell, owner: false),
        branches: [
          _branch(Routes.staffCard, (_) => const MyCardScreen()),
          _branch(Routes.staffReviews,
              (_) => const ReviewsScreen(staffMode: true)),
          _branch(Routes.staffAnalytics,
              (_) => const CardAnalyticsScreen(staffMode: true)),
          _branch(Routes.staffMore, (_) => const MoreScreen(owner: false)),
        ],
      ),

      // Staff screens
      r(Routes.staffCardEdit, (_) => const CardEditorScreen(staffMode: true)),
      r(Routes.staffCardShare, (_) => const CardShareScreen(staffMode: true)),
      r(Routes.staffSecurity, (_) => const ChangePasswordScreen()),
      r(Routes.staffDeleteAccount, (_) => const DeleteAccountScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _branch(
  String path,
  Widget Function(GoRouterState s) build,
) =>
    StatefulShellBranch(
      routes: [GoRoute(path: path, builder: (_, s) => build(s))],
    );
