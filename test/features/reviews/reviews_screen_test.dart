import 'package:bizzvot/core/auth/auth_user.dart';
import 'package:bizzvot/core/auth/session_controller.dart';
import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/features/reviews/data/reviews_repository.dart';
import 'package:bizzvot/features/reviews/presentation/reviews_screen.dart';
import 'package:bizzvot/shared/models/paged.dart';
import 'package:bizzvot/shared/models/review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../public_card/test_app.dart';
import 'reviews_repository_test.dart' show reviewJson;

class FakeReviewsRepo extends ReviewsRepository {
  FakeReviewsRepo() : super(FakeApi().client);

  List<Review> data = [
    Review.fromJson(reviewJson('1')),
    Review.fromJson(reviewJson('2', status: 'approved', reply: {'text': 'Thanks!'})),
    Review.fromJson(reviewJson('3', status: 'hidden')),
  ];
  final fetches = <(ReviewScope, ReviewStatus?)>[];
  final statusCalls = <(String, ReviewStatus)>[];
  final replies = <(String, String)>[];
  Object? failWith;

  @override
  Future<Paged<Review>> fetch(ReviewScope scope, {ReviewStatus? status, int page = 1}) async {
    fetches.add((scope, status));
    // Simulate a server that ignores the filter: the screen filters locally.
    return Paged(items: data);
  }

  @override
  Future<Review?> setStatus(ReviewScope scope, String id, ReviewStatus status) async {
    statusCalls.add((id, status));
    if (failWith != null) throw failWith!;
    return null;
  }

  @override
  Future<ReviewReply?> reply(ReviewScope scope, String id, String text) async {
    replies.add((id, text));
    if (failWith != null) throw failWith!;
    return ReviewReply(text: text);
  }
}

const owner = AuthUser(id: 'o1', email: 'o@x.test', role: UserRole.owner);

AuthUser staff({bool view = true, bool reply = true}) => AuthUser(
      id: 's1',
      email: 's@x.test',
      role: UserRole.staff,
      cardId: 'c1',
      permissions: StaffPermissions(viewReviews: view, replyReviews: reply),
    );

void main() {
  late FakeReviewsRepo repo;

  setUp(() => repo = FakeReviewsRepo());

  Future<void> pump(WidgetTester tester, Widget screen, AuthUser user) async {
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpTestApp(
      tester,
      screen,
      overrides: [
        currentUserProvider.overrideWithValue(user),
        reviewsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('owner sees reviews with card, reviewer, status and reply', (tester) async {
    await pump(tester, const ReviewsScreen(), owner);
    expect(repo.fetches.single, (ReviewScope.owner, null));
    expect(find.text('Reviewer 1'), findsOneWidget);
    expect(find.text('Jane Doe'), findsNWidgets(3));
    expect(find.text('Thanks!'), findsOneWidget);
    expect(find.text('Pending'), findsWidgets);
    expect(find.textContaining('secret-'), findsNothing);
    expect(find.textContaining('10.0.0.'), findsNothing);
  });

  testWidgets('filter chips refetch and filter locally', (tester) async {
    await pump(tester, const ReviewsScreen(), owner);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Hidden'));
    await tester.pumpAndSettle();
    expect(repo.fetches.last, (ReviewScope.owner, ReviewStatus.hidden));
    expect(find.text('Reviewer 3'), findsOneWidget);
    expect(find.text('Reviewer 1'), findsNothing);
    expect(find.text('Unhide'), findsOneWidget);
  });

  testWidgets('approve updates the status optimistically', (tester) async {
    await pump(tester, const ReviewsScreen(), owner);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(repo.statusCalls.single, ('1', ReviewStatus.approved));
    expect(find.text('Pending'), findsOneWidget); // only the filter chip remains
    expect(find.text('Review approved'), findsOneWidget);
  });

  testWidgets('failed action rolls back and shows the error', (tester) async {
    repo.failWith = const AppException(AppErrorKind.server, 'Server problem');
    await pump(tester, const ReviewsScreen(), owner);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(find.text('Server problem'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
  });

  testWidgets('reply composer validates and posts', (tester) async {
    await pump(tester, const ReviewsScreen(), owner);
    await tester.tap(find.text('Reply').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reply-submit')));
    await tester.pump();
    expect(find.text('Write a reply first'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('reply-text')), '  Much appreciated  ');
    await tester.tap(find.byKey(const ValueKey('reply-submit')));
    await tester.pumpAndSettle();
    expect(repo.replies.single, ('1', 'Much appreciated'));
    expect(find.text('Much appreciated'), findsOneWidget);
  });

  testWidgets('empty state per filter', (tester) async {
    repo.data = [];
    await pump(tester, const ReviewsScreen(), owner);
    expect(find.text('No reviews yet'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pending'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing waiting for approval'), findsOneWidget);
  });

  testWidgets('staff without viewReviews gets a no-permission state', (tester) async {
    await pump(tester, const ReviewsScreen(staffMode: true), staff(view: false));
    expect(find.text("You don't have access to reviews"), findsOneWidget);
    expect(repo.fetches, isEmpty);
  });

  testWidgets('staff without replyReviews can read but not act', (tester) async {
    await pump(tester, const ReviewsScreen(staffMode: true), staff(reply: false));
    expect(repo.fetches.single.$1, ReviewScope.staff);
    expect(find.text('Reviewer 1'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reply'), findsNothing);
  });
}
