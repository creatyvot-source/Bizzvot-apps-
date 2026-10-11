import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/features/public_card/data/external_actions.dart';
import 'package:bizzvot/features/public_card/data/public_card_repository.dart';
import 'package:bizzvot/features/public_card/domain/public_card.dart';
import 'package:bizzvot/features/public_card/domain/public_review.dart';
import 'package:bizzvot/features/public_card/presentation/public_card_screen.dart';
import 'package:bizzvot/shared/models/paged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'public_card_model_test.dart' show leakyPayload;
import 'test_app.dart';

void main() {
  late FakePublicRepo repo;
  late FakeExternalActions actions;

  setUp(() {
    repo = FakePublicRepo();
    actions = FakeExternalActions();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpTestApp(
      tester,
      const PublicCardScreen(slug: 'jane-doe'),
      overrides: [
        publicCardRepositoryProvider.overrideWithValue(repo),
        externalActionsProvider.overrideWithValue(actions),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders public data only and launches tracked actions', (tester) async {
    repo.onCard = (_) async => PublicCard.fromJson({
          ...leakyPayload(),
          'whatsapp': '+91 98765 43210',
          'bio': 'Helping teams grow.',
        });
    await pump(tester);

    expect(find.text('Jane Doe'), findsWidgets);
    expect(find.text('Head of Sales'), findsOneWidget);
    expect(find.text('Helping teams grow.'), findsOneWidget);
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.textContaining('203.0.113.9'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Call'));
    await tester.pump();
    expect(actions.opened.last.toString(), 'tel:+919876543210');
    expect(repo.tracked.last, TrackType.phone);

    await tester.tap(find.bySemanticsLabel('WhatsApp'));
    await tester.pump();
    expect(actions.opened.last.toString(), 'https://wa.me/919876543210');

    await tester.tap(find.bySemanticsLabel('Email'));
    await tester.pump();
    expect(actions.opened.last.toString(), 'mailto:jane@acme.test');

    await tester.tap(find.text('LinkedIn'));
    await tester.pump();
    expect(actions.opened.last.toString(), 'https://linkedin.com/in/jane');
    expect(repo.tracked.last, TrackType.social);
  });

  testWidgets('save contact downloads the vCard and opens the share sheet', (tester) async {
    repo.onCard = (_) async => PublicCard.fromJson(leakyPayload());
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('save-contact')));
    await tester.pumpAndSettle();
    expect(repo.vcardFetches, 1);
    expect(actions.sharedFiles.single, 'Jane_Doe.vcf');
    expect(repo.tracked, contains(TrackType.vcard));
  });

  testWidgets('share button shares the public link', (tester) async {
    repo.onCard = (_) async => PublicCard.fromJson(leakyPayload());
    await pump(tester);

    await tester.tap(find.byTooltip('Share card'));
    await tester.pump();
    expect(actions.sharedText.single, endsWith('/card/jane-doe'));
  });

  testWidgets('review_card shows Google review; vcard disabled hides save', (tester) async {
    repo.onCard = (_) async => PublicCard.fromJson({
          '_id': 'c1',
          'slug': 'jane-doe',
          'title': 'Jane Doe',
          'template': 'review_card',
          'vcardEnabled': false,
          'googleReviewUrl': 'https://g.page/r/abc/review',
          'averageRating': 4.5,
          'reviewCount': 2,
        });
    await pump(tester);

    expect(find.byKey(const ValueKey('save-contact')), findsNothing);
    await tester.tap(find.text('Review us on Google'));
    await tester.pump();
    expect(actions.opened.single.toString(), 'https://g.page/r/abc/review');
    expect(repo.tracked.single, TrackType.googleReview);
  });

  testWidgets('display toggles hide fields and sections', (tester) async {
    repo.onCard = (_) async => PublicCard.fromJson({
          'slug': 'jane-doe',
          'title': 'Jane Doe',
          'phone': '+1 555 0100',
          'email': 'jane@acme.test',
          'displayToggles': {'showPhone': false, 'showReviews': false},
        });
    await pump(tester);

    expect(find.bySemanticsLabel('Call'), findsNothing);
    expect(find.text('+1 555 0100'), findsNothing);
    expect(find.text('jane@acme.test'), findsOneWidget);
    expect(find.text('Write a review'), findsNothing);
  });

  testWidgets('approved reviews with replies; write-a-review navigates', (tester) async {
    repo.onCard = (_) async => PublicCard.fromJson({'slug': 'jane-doe', 'title': 'Jane Doe'});
    repo.onReviews = (_, _) async => Paged(
          items: [
            PublicReview.fromJson({
              '_id': 'r1',
              'reviewerName': 'Sam Lee',
              'rating': 5,
              'comment': 'Brilliant service',
              'reply': {'text': 'Thank you Sam!'},
              'createdAt': '2026-09-01T10:00:00Z',
            }),
          ],
        );
    await pump(tester);

    expect(find.text('Sam Lee'), findsOneWidget);
    expect(find.text('Brilliant service'), findsOneWidget);
    expect(find.text('Thank you Sam!'), findsOneWidget);
    expect(find.text('Response from the business'), findsOneWidget);

    await tester.ensureVisible(find.text('Write a review'));
    await tester.tap(find.text('Write a review'));
    await tester.pumpAndSettle();
    expect(find.text('route:/card/jane-doe/review'), findsOneWidget);
  });

  for (final status in [403, 404, 410]) {
    testWidgets('$status shows a neutral unavailable state', (tester) async {
      repo.onCard = (_) => Future.error(
            AppException(
              switch (status) {
                403 => AppErrorKind.forbidden,
                404 => AppErrorKind.notFound,
                _ => AppErrorKind.gone,
              },
              'Card disabled by billing', // must not be shown
              statusCode: status,
            ),
          );
      await pump(tester);
      expect(find.text("This card isn't available"), findsOneWidget);
      expect(find.textContaining('billing'), findsNothing);
      expect(find.text('Try again'), findsNothing);
    });
  }

  testWidgets('network error offers retry', (tester) async {
    var calls = 0;
    repo.onCard = (_) {
      calls++;
      if (calls == 1) {
        return Future.error(const AppException(AppErrorKind.network, 'You appear to be offline.'));
      }
      return Future.value(PublicCard.fromJson({'slug': 'jane-doe', 'title': 'Jane Doe'}));
    };
    await pump(tester);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Jane Doe'), findsWidgets);
  });
}
