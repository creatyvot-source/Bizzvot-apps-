/// Every REST path used by the app, relative to `Env.apiBaseUrl` (`/api/v1`).
///
/// Paths marked `PROPOSED` are not in the current backend contract; they are
/// listed in `docs/API_GAP_REGISTER.md` and must be approved by the backend
/// team before release. Screens must never build raw paths themselves.
abstract final class Endpoints {
  static String _id(String id) => Uri.encodeComponent(id);

  // ---- Auth (existing) ----
  static const register = '/auth/register';
  static const login = '/auth/login';
  static const staffLogin = '/auth/staff-login';
  static const me = '/auth/me';
  static const refresh = '/auth/refresh';
  static const logout = '/auth/logout';
  static const forgotPassword = '/auth/forgot-password';
  static const resetPassword = '/auth/reset-password';
  static const changePassword = '/auth/change-password';
  static const sessionStatus = '/auth/session-status';

  // ---- Organization (existing) ----
  static const dashboard = '/organization/dashboard';
  static const profile = '/organization/profile';
  static const staff = '/organization/staff';
  static String staffMember(String id) => '/organization/staff/${_id(id)}';
  static const cards = '/organization/cards';
  static String card(String id) => '/organization/cards/${_id(id)}';
  static const cardStatus = '/organization/cards/status';
  static const allQrCodes = '/organization/cards/qrcodes';
  static const orgReviews = '/organization/reviews';
  static String orgReviewStatus(String id) =>
      '/organization/reviews/${_id(id)}/status';
  static String orgReviewReply(String id) =>
      '/organization/reviews/${_id(id)}/reply';
  static const billing = '/organization/billing';

  // ---- Cards (existing) ----
  static String cardQr(String id) => '/cards/${_id(id)}/qrcode';
  static String cardVcard(String id) => '/cards/${_id(id)}/vcard';
  static String cardMedia(String id) => '/cards/${_id(id)}/media';
  static String cardLibrary(String id) => '/cards/${_id(id)}/library';
  static const mediaUpload = '/media/upload';

  // ---- Staff (existing review routes) ----
  static const staffReviews = '/staff/reviews';
  static String staffReviewReply(String id) =>
      '/staff/reviews/${_id(id)}/reply';
  static String staffReviewStatus(String id) =>
      '/staff/reviews/${_id(id)}/status';

  /// PROPOSED: staff member's own assigned card (read + permitted update).
  static const staffCard = '/staff/card';

  // ---- Public (existing) ----
  static String publicCard(String slug) => '/public/card/${_id(slug)}';
  static String publicCardReviews(String slug) =>
      '/public/card/${_id(slug)}/reviews';
  static String publicCardReview(String slug) =>
      '/public/card/${_id(slug)}/review';
  static const trackClick = '/public/track-click';

  /// PROPOSED: server-filtered public people directory.
  static String publicDirectory(String orgSlug) =>
      '/public/organizations/${_id(orgSlug)}/directory';

  // ---- Analytics (existing) ----
  static String analyticsViews(String cardId) =>
      '/analytics/card/${_id(cardId)}/views';
  static String analyticsReviews(String cardId) =>
      '/analytics/card/${_id(cardId)}/reviews';
  static String analyticsLinks(String cardId) =>
      '/analytics/card/${_id(cardId)}/links';

  // ---- Commerce (ALL PROPOSED) ----
  static const catalogCategories = '/catalog/categories';
  static const catalogServices = '/catalog/services';
  static const catalogProducts = '/catalog/products';
  static const catalogPlans = '/catalog/plans';
  static String catalogItem(String type, String id) =>
      '/catalog/${_id(type)}/${_id(id)}';
  static const cartQuote = '/cart/quote';
  static const orders = '/orders';
  static String order(String id) => '/orders/${_id(id)}';
  static String orderPayment(String id) => '/orders/${_id(id)}/payment';
  static const subscriptions = '/subscriptions';
  static String subscription(String id) => '/subscriptions/${_id(id)}';
  static String subscriptionRenew(String id) =>
      '/subscriptions/${_id(id)}/renew';
  static const invoices = '/invoices';
  static String invoice(String id) => '/invoices/${_id(id)}';

  // ---- Notifications (PROPOSED) ----
  static const notifications = '/notifications';
  static String notificationRead(String id) =>
      '/notifications/${_id(id)}/read';
}
