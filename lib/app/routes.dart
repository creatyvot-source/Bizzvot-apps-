/// Route paths. Build locations with these helpers — never inline strings.
abstract final class Routes {
  static String _e(String s) => Uri.encodeComponent(s);

  // System
  static const splash = '/splash';
  static const unsupported = '/unsupported';

  // Auth (signed-out only)
  static const welcome = '/welcome';
  static const login = '/login';
  static const staffLogin = '/staff-login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';

  // Public (no login required, deep-linkable)
  static String publicCard(String slug) => '/card/${_e(slug)}';
  static String publicReview(String slug) => '/card/${_e(slug)}/review';
  static String publicDirectory(String orgSlug) => '/directory/${_e(orgSlug)}';

  // Owner tabs
  static const ownerDashboard = '/o/dashboard';
  static const ownerCards = '/o/cards';
  static const ownerStaff = '/o/staff';
  static const ownerReviews = '/o/reviews';
  static const ownerMore = '/o/more';

  // Owner screens
  static String ownerCard(String id) => '/o/cards/${_e(id)}';
  static String ownerCardEdit(String id) => '/o/cards/${_e(id)}/edit';
  static String ownerCardShare(String id) => '/o/cards/${_e(id)}/share';
  static String ownerCardAnalytics(String id) => '/o/cards/${_e(id)}/analytics';
  static const ownerStaffNew = '/o/staff/new';
  static String ownerStaffEdit(String id) => '/o/staff/${_e(id)}';
  static const ownerProfile = '/o/profile';
  static const ownerVisibility = '/o/visibility';
  static const ownerBilling = '/o/billing';
  static const ownerSeats = '/o/billing/seats';
  static const ownerShop = '/o/shop';
  static String ownerShopItem(String type, String id) => '/o/shop/${_e(type)}/${_e(id)}';
  static const ownerCart = '/o/cart';
  static const ownerCheckout = '/o/checkout';
  static String ownerPayment(String orderId) => '/o/payment/${_e(orderId)}';
  static const ownerOrders = '/o/orders';
  static String ownerOrder(String id) => '/o/orders/${_e(id)}';
  static const ownerInvoices = '/o/invoices';
  static String ownerInvoice(String id) => '/o/invoices/${_e(id)}';
  static const ownerSubscriptions = '/o/subscriptions';
  static String ownerSubscription(String id) => '/o/subscriptions/${_e(id)}';
  static const ownerNotifications = '/o/notifications';
  static const ownerSecurity = '/o/security';

  // Staff tabs
  static const staffCard = '/s/card';
  static const staffReviews = '/s/reviews';
  static const staffAnalytics = '/s/analytics';
  static const staffMore = '/s/more';

  // Staff screens
  static const staffCardEdit = '/s/card/edit';
  static const staffCardShare = '/s/card/share';
  static const staffSecurity = '/s/security';

  static bool isPublic(String location) =>
      location.startsWith('/card/') || location.startsWith('/directory/');

  static bool isAuth(String location) => const {
        welcome,
        login,
        staffLogin,
        register,
        forgotPassword,
        resetPassword,
      }.contains(Uri.parse(location).path);
}
