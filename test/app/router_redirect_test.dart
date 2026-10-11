import 'package:bizzvot/app/router.dart';
import 'package:bizzvot/app/routes.dart';
import 'package:bizzvot/core/auth/auth_user.dart';
import 'package:bizzvot/core/auth/session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AuthUser _user(UserRole role, [StaffPermissions p = StaffPermissions.none]) =>
    AuthUser(id: 'u', email: 'u@x.co', role: role, permissions: p);

String? go(SessionState s, String path) => resolveRedirect(s, Uri.parse(path));

void main() {
  final owner = SignedIn(_user(UserRole.owner));
  final staff = SignedIn(_user(UserRole.staff));
  final staffAll = SignedIn(_user(
    UserRole.staff,
    const StaffPermissions(editCard: true, viewReviews: true, replyReviews: true, manageLinks: true),
  ));

  test('public card is reachable in every state', () {
    for (final s in [const SessionRestoring(), const SignedOut(), owner, staff]) {
      expect(go(s, '/card/jane-doe'), isNull);
      expect(go(s, '/card/jane-doe/review'), isNull);
      expect(go(s, '/directory/acme'), isNull);
    }
  });

  test('restoring holds on splash', () {
    expect(go(const SessionRestoring(), Routes.ownerDashboard), Routes.splash);
    expect(go(const SessionRestoring(), Routes.splash), isNull);
  });

  test('signed out can only see auth screens', () {
    expect(go(const SignedOut(), Routes.ownerDashboard), Routes.welcome);
    expect(go(const SignedOut(), Routes.staffCard), Routes.welcome);
    expect(go(const SignedOut(), '/reset-password?token=t'), isNull);
    expect(go(const SignedOut(), Routes.login), isNull);
  });

  test('owner lands on dashboard and cannot open staff area', () {
    expect(go(owner, Routes.login), Routes.ownerDashboard);
    expect(go(owner, Routes.splash), Routes.ownerDashboard);
    expect(go(owner, Routes.staffCard), Routes.ownerDashboard);
    expect(go(owner, Routes.ownerBilling), isNull);
  });

  test('staff cannot reach owner area or billing', () {
    expect(go(staff, Routes.ownerDashboard), Routes.staffCard);
    expect(go(staff, Routes.ownerBilling), Routes.staffCard);
    expect(go(staff, Routes.ownerCard('other')), Routes.staffCard);
  });

  test('staff permission gates', () {
    expect(go(staff, Routes.staffCardEdit), Routes.staffCard);
    expect(go(staff, Routes.staffReviews), Routes.staffCard);
    expect(go(staffAll, Routes.staffCardEdit), isNull);
    expect(go(staffAll, Routes.staffReviews), isNull);
    expect(go(staff, Routes.staffAnalytics), isNull);
  });

  test('unsupported roles go to the unsupported screen', () {
    final customer = SignedIn(_user(UserRole.customer));
    expect(go(customer, Routes.ownerDashboard), Routes.unsupported);
    expect(go(customer, Routes.unsupported), isNull);
  });

  test('every declared route path matches the intended route', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    String matched(String location) {
      final m = router.configuration.findMatch(Uri.parse(location));
      return m.last.route.path;
    }

    expect(matched(Routes.ownerCards), Routes.ownerCards);
    expect(matched(Routes.ownerCard('abc')), '/o/cards/:id');
    expect(matched(Routes.ownerCardEdit('abc')), '/o/cards/:id/edit');
    expect(matched(Routes.ownerStaffNew), Routes.ownerStaffNew);
    expect(matched(Routes.ownerStaffEdit('s1')), '/o/staff/:id');
    expect(matched(Routes.staffCard), Routes.staffCard);
    expect(matched(Routes.staffCardEdit), Routes.staffCardEdit);
    expect(matched(Routes.ownerSeats), Routes.ownerSeats);
    expect(matched(Routes.ownerShopItem('services', 'x')), '/o/shop/:type/:id');
    expect(matched(Routes.publicReview('jane')), '/card/:slug/review');
  });
}
