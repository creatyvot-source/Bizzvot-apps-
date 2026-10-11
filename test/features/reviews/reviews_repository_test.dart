import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/features/reviews/data/reviews_repository.dart';
import 'package:bizzvot/shared/models/review.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';

Map<String, dynamic> reviewJson(
  String id, {
  String status = 'pending',
  Object? reply,
}) => {
  '_id': id,
  'reviewerName': 'Reviewer $id',
  'email': 'secret-$id@x.test',
  'ip': '10.0.0.$id',
  'rating': 4,
  'comment': 'Comment $id',
  'status': status,
  'card': {'_id': 'c1', 'title': 'Jane Doe'},
  'reply': ?reply,
  'createdAt': '2026-09-01T10:00:00Z',
};

void main() {
  late FakeApi fake;
  late ReviewsRepository repo;

  setUp(() {
    fake = FakeApi();
    repo = ReviewsRepository(fake.client);
  });

  test('owner fetch uses /organization/reviews with status + paging', () async {
    fake.on(
      'GET',
      '/organization/reviews',
      FakeResponse.ok({
        'reviews': [reviewJson('1'), reviewJson('2', status: 'approved')],
        'page': 1,
        'totalPages': 2,
      }),
    );
    final page = await repo.fetch(
      ReviewScope.owner,
      status: ReviewStatus.pending,
    );
    expect(fake.requests.single.query, {
      'status': 'pending',
      'page': 1,
      'limit': 20,
    });
    expect(page.items, hasLength(2));
    expect(page.hasMore, isTrue);
    final r = page.items.first;
    expect(r.cardTitle, 'Jane Doe');
    expect(r.reviewerName, 'Reviewer 1');
    expect(r.status, ReviewStatus.pending);
  });

  test('all filter omits the status param', () async {
    fake.on('GET', '/organization/reviews', FakeResponse.ok([reviewJson('1')]));
    await repo.fetch(ReviewScope.owner);
    expect(fake.requests.single.query.containsKey('status'), isFalse);
  });

  test('staff fetch uses /staff/reviews', () async {
    fake.on(
      'GET',
      '/staff/reviews',
      FakeResponse.ok({
        'items': [reviewJson('9')],
      }),
    );
    final page = await repo.fetch(ReviewScope.staff);
    expect(page.items.single.id, '9');
  });

  test('setStatus PATCHes {status} and parses the echoed review', () async {
    fake.on(
      'PATCH',
      '/organization/reviews/1/status',
      FakeResponse.ok({'review': reviewJson('1', status: 'approved')}),
    );
    final r = await repo.setStatus(
      ReviewScope.owner,
      '1',
      ReviewStatus.approved,
    );
    expect(fake.requests.single.body, {'status': 'approved'});
    expect(r?.status, ReviewStatus.approved);
  });

  test('setStatus tolerates an empty response', () async {
    fake.on('PATCH', '/staff/reviews/1/status', FakeResponse.ok(null));
    expect(
      await repo.setStatus(ReviewScope.staff, '1', ReviewStatus.hidden),
      isNull,
    );
  });

  test('reply POSTs {text} and parses the reply', () async {
    fake.on(
      'POST',
      '/organization/reviews/1/reply',
      FakeResponse.ok({
        'review': reviewJson('1', reply: {'text': 'Thanks!'}),
      }),
    );
    final reply = await repo.reply(ReviewScope.owner, '1', '  Thanks!  ');
    expect(fake.requests.single.body, {'text': 'Thanks!'});
    expect(reply?.text, 'Thanks!');
  });

  test('403 surfaces as forbidden', () async {
    fake.on(
      'POST',
      '/staff/reviews/1/reply',
      FakeResponse.error(403, 'No permission'),
    );
    await expectLater(
      repo.reply(ReviewScope.staff, '1', 'x'),
      throwsA(
        isA<AppException>().having(
          (e) => e.kind,
          'kind',
          AppErrorKind.forbidden,
        ),
      ),
    );
  });
}
