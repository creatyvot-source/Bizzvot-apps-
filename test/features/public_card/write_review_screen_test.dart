import 'dart:async';

import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/features/public_card/data/public_card_repository.dart';
import 'package:bizzvot/features/public_card/domain/public_card.dart';
import 'package:bizzvot/features/public_card/domain/public_review.dart';
import 'package:bizzvot/features/public_card/presentation/write_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

void main() {
  late FakePublicRepo repo;

  setUp(() {
    repo = FakePublicRepo()
      ..onCard = (_) async =>
          PublicCard.fromJson({'slug': 'jane', 'title': 'Jane Doe'});
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpTestApp(
      tester,
      const WriteReviewScreen(slug: 'jane'),
      overrides: [publicCardRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, {int stars = 4}) async {
    await tester.tap(find.byKey(ValueKey('star-$stars')));
    await tester.enterText(find.byKey(const ValueKey('review-name')), 'Sam');
    await tester.enterText(
      find.byKey(const ValueKey('review-comment')),
      'Great help',
    );
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('submit-review')));
    await tester.pump();
  }

  testWidgets('validates rating and name before submitting', (tester) async {
    await pump(tester);
    expect(find.text('How was your experience with Jane Doe?'), findsOneWidget);
    await submit(tester);
    expect(find.text('Choose a rating from 1 to 5 stars'), findsOneWidget);
    expect(find.text('Please enter your name'), findsOneWidget);
    expect(repo.submissions, isEmpty);
  });

  testWidgets('star selector exposes accessible semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('star-3')));
    await tester.pump();
    expect(
      tester.getSemantics(find.byKey(const ValueKey('star-3'))),
      matchesSemantics(
        tooltip: '3 stars',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(find.bySemanticsLabel('Rating'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('pending result shows the approval message', (tester) async {
    repo.onSubmit = (_) async =>
        ReviewSubmissionResult.fromJson({'status': 'pending'});
    await pump(tester);
    await fill(tester);
    await submit(tester);
    await tester.pumpAndSettle();

    expect(repo.submissions.single.toJson(), {
      'rating': 4,
      'name': 'Sam',
      'comment': 'Great help',
    });
    expect(
      find.text('Thanks! Your review will appear after approval'),
      findsOneWidget,
    );
  });

  testWidgets('approved result thanks the reviewer', (tester) async {
    repo.onSubmit = (_) async =>
        ReviewSubmissionResult.fromJson({'status': 'approved'});
    await pump(tester);
    await fill(tester, stars: 5);
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('Thanks for your review'), findsOneWidget);
  });

  testWidgets('double tap submits only once', (tester) async {
    final completer = Completer<ReviewSubmissionResult>();
    repo.onSubmit = (_) => completer.future;
    await pump(tester);
    await fill(tester);
    await tester.tap(find.byKey(const ValueKey('submit-review')));
    await tester.tap(
      find.byKey(const ValueKey('submit-review')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(repo.submissions, hasLength(1));
    completer.complete(ReviewSubmissionResult.fromJson({'status': 'pending'}));
    await tester.pumpAndSettle();
  });

  testWidgets('409 disables re-submit', (tester) async {
    repo.onSubmit = (_) => Future.error(
      const AppException(AppErrorKind.conflict, 'Duplicate', statusCode: 409),
    );
    await pump(tester);
    await fill(tester);
    await submit(tester);
    await tester.pumpAndSettle();

    expect(find.text('You have already reviewed this person.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('submit-review')),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    await submit(tester);
    expect(repo.submissions, hasLength(1));
  });

  testWidgets('429 starts a cooldown countdown using retryAfter', (
    tester,
  ) async {
    repo.onSubmit = (_) => Future.error(
      const AppException(
        AppErrorKind.rateLimited,
        'Too many',
        statusCode: 429,
        retryAfter: Duration(seconds: 3),
      ),
    );
    await pump(tester);
    await fill(tester);
    await submit(tester);
    await tester.pump();

    expect(find.textContaining('You can try again in 0:0'), findsOneWidget);
    expect(find.textContaining('Try again in 0:0'), findsOneWidget);
    await submit(tester);
    expect(repo.submissions, hasLength(1));

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.textContaining('You can try again in'), findsNothing);
    expect(find.text('Submit review'), findsOneWidget);
  });
}
