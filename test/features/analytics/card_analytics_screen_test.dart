import 'package:bizzvot/core/auth/auth_user.dart';
import 'package:bizzvot/core/auth/session_controller.dart';
import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/features/analytics/data/analytics_repository.dart';
import 'package:bizzvot/features/analytics/domain/analytics_models.dart';
import 'package:bizzvot/features/analytics/presentation/card_analytics_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../public_card/test_app.dart';

class FakeAnalyticsRepo extends AnalyticsRepository {
  FakeAnalyticsRepo() : super(FakeApi().client);

  final calls = <(String, String, AnalyticsRange)>[];
  bool failLinks = false;

  @override
  Future<ViewsStats> fetchViews(String cardId, AnalyticsRange range) async {
    calls.add(('views', cardId, range));
    return ViewsStats.fromJson({
      'total': 1234,
      'unique': 567,
      'series': [
        {'date': '2026-10-01', 'count': 10, 'unique': 6, 'ip': '203.0.113.7'},
        {'date': '2026-10-02', 'count': 25, 'unique': 12},
        {'date': '2026-10-03', 'count': 15, 'unique': 9},
      ],
    });
  }

  @override
  Future<ReviewStats> fetchReviews(String cardId, AnalyticsRange range) async {
    calls.add(('reviews', cardId, range));
    return ReviewStats.fromJson({
      'total': 8,
      'average': 4.25,
      'breakdown': {'5': 4, '4': 3, '2': 1},
    });
  }

  @override
  Future<LinkClicks> fetchLinks(String cardId, AnalyticsRange range) async {
    calls.add(('links', cardId, range));
    if (failLinks) {
      throw const AppException(
        AppErrorKind.server,
        'Links are unavailable right now.',
      );
    }
    return LinkClicks.fromJson({'whatsapp': 9, 'phone': 3, 'instagram': 5});
  }
}

void main() {
  late FakeAnalyticsRepo repo;

  setUp(() => repo = FakeAnalyticsRepo());

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    AuthUser? user,
  }) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpTestApp(
      tester,
      screen,
      overrides: [
        currentUserProvider.overrideWithValue(
          user ??
              const AuthUser(id: 'o1', email: 'o@x.test', role: UserRole.owner),
        ),
        analyticsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('owner sees KPIs, chart with summary, breakdowns', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const CardAnalyticsScreen(cardId: 'c1'));

    expect(repo.calls.map((c) => c.$2).toSet(), {'c1'});
    expect(find.text('1,234'), findsOneWidget);
    expect(find.text('567'), findsOneWidget);
    expect(find.text('4.3'), findsOneWidget); // 4.25 → 1 decimal
    expect(find.text('8'), findsWidgets);
    expect(find.byType(LineChart), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Views over the last 30 days: 1234 total, 567 unique'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('5 stars: 4 reviews'), findsOneWidget);

    // Link clicks sorted desc: WhatsApp (9), Social (5), Phone (3).
    final labels = ['WhatsApp', 'Social', 'Phone'];
    final ys = [for (final l in labels) tester.getTopLeft(find.text(l)).dy];
    expect(ys, orderedEquals([...ys]..sort()));
    expect(find.textContaining('203.0.113'), findsNothing);
    handle.dispose();
  });

  testWidgets('table fallback lists every day', (tester) async {
    await pump(tester, const CardAnalyticsScreen(cardId: 'c1'));
    await tester.ensureVisible(find.text('View as table'));
    await tester.tap(find.text('View as table'));
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Table), matching: find.text('25')),
      findsOneWidget,
    );
  });

  testWidgets('range selector refetches with the new range', (tester) async {
    await pump(tester, const CardAnalyticsScreen(cardId: 'c1'));
    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.$3 == AnalyticsRange.week), hasLength(3));
  });

  testWidgets('one failing section does not hide the others', (tester) async {
    repo.failLinks = true;
    await pump(tester, const CardAnalyticsScreen(cardId: 'c1'));
    expect(find.text('Links are unavailable right now.'), findsOneWidget);
    expect(find.text('1,234'), findsOneWidget);
  });

  testWidgets('staff mode uses the assigned card', (tester) async {
    await pump(
      tester,
      const CardAnalyticsScreen(staffMode: true),
      user: const AuthUser(
        id: 's1',
        email: 's@x.test',
        role: UserRole.staff,
        cardId: 'mine',
      ),
    );
    expect(repo.calls.map((c) => c.$2).toSet(), {'mine'});
  });

  testWidgets('staff without a card sees an empty state', (tester) async {
    await pump(
      tester,
      const CardAnalyticsScreen(staffMode: true),
      user: const AuthUser(id: 's1', email: 's@x.test', role: UserRole.staff),
    );
    expect(find.text('No card assigned'), findsOneWidget);
    expect(repo.calls, isEmpty);
  });
}
