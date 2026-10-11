import 'package:bizzvot/app/routes.dart';
import 'package:bizzvot/app/theme.dart';
import 'package:bizzvot/core/auth/session_controller.dart';
import 'package:bizzvot/core/config/app_config.dart';
import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/features/dashboard/data/dashboard_repository.dart';
import 'package:bizzvot/features/dashboard/domain/dashboard_overview.dart';
import 'package:bizzvot/features/dashboard/presentation/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class FakeDashboardRepository implements DashboardRepository {
  FakeDashboardRepository(this.result);
  Object result;
  int calls = 0;

  @override
  Future<DashboardOverview> fetchOverview() async {
    calls++;
    final r = result;
    if (r is DashboardOverview) return r;
    throw r;
  }
}

const _overview = DashboardOverview(
  organizationName: 'Acme Realty',
  organizationStatus: 'active',
  totalCards: 3,
  cardsLimit: 3,
  staffCount: 1,
  staffLimit: 2,
  totalReviews: 12,
  averageRating: 4.5,
);

Widget _app(FakeDashboardRepository repo, {AppConfig config = AppConfig.defaults}) {
  final router = GoRouter(
    initialLocation: Routes.ownerDashboard,
    routes: [
      GoRoute(path: Routes.ownerDashboard, builder: (_, _) => const DashboardScreen()),
      GoRoute(
        path: Routes.ownerStaffNew,
        builder: (_, _) => const Scaffold(body: Text('ADD STAFF PAGE')),
      ),
      GoRoute(
        path: Routes.ownerNotifications,
        builder: (_, _) => const Scaffold(body: Text('NOTIFICATIONS PAGE')),
      ),
    ],
  );
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      sessionKeyProvider.overrideWithValue('u1'),
      dashboardRepositoryProvider.overrideWithValue(repo),
      currentConfigProvider.overrideWithValue(config),
    ],
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  );
}

void main() {
  testWidgets('shows organization, counts, limits and quick actions', (tester) async {
    await tester.pumpWidget(_app(FakeDashboardRepository(_overview)));
    await tester.pump();

    expect(find.text('Acme Realty'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('All card slots are in use'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('Browse services'), findsOneWidget);
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  testWidgets('hides Browse services when the shop flag is off', (tester) async {
    await tester.pumpWidget(_app(
      FakeDashboardRepository(_overview),
      config: const AppConfig(features: {Flags.shop: false}),
    ));
    await tester.pump();
    expect(find.text('Browse services'), findsNothing);
    expect(find.text('Purchase seats'), findsWidgets);
  });

  testWidgets('billing warning when cards are disabled by billing', (tester) async {
    await tester.pumpWidget(_app(FakeDashboardRepository(const DashboardOverview(
      organizationName: 'Acme',
      totalCards: 4,
      disabledByBilling: 2,
    ))));
    await tester.pump();
    expect(find.text('2 cards disabled by billing'), findsOneWidget);
  });

  testWidgets('Add staff quick action opens the staff editor', (tester) async {
    await tester.pumpWidget(_app(FakeDashboardRepository(_overview)));
    await tester.pump();
    final add = find.text('Add staff');
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('ADD STAFF PAGE'), findsOneWidget);
  });

  testWidgets('error state offers retry', (tester) async {
    final repo = FakeDashboardRepository(
      const AppException(AppErrorKind.network, 'You appear to be offline.'),
    );
    await tester.pumpWidget(_app(repo));
    await tester.pump();
    expect(find.text('You are offline'), findsOneWidget);

    repo.result = _overview;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Acme Realty'), findsOneWidget);
    expect(repo.calls, 2);
  });
}
