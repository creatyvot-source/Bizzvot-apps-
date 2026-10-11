import 'package:bizzvot/core/api/api_client.dart';
import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/features/public_card/data/public_card_repository.dart';
import 'package:bizzvot/features/public_card/domain/public_review.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';

void main() {
  late FakeApi fake;
  late PublicCardRepository repo;
  late List<bool> anonymousFlags;

  setUp(() {
    fake = FakeApi();
    anonymousFlags = [];
    fake.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          anonymousFlags.add(o.extra[ApiFlags.anonymous] == true);
          h.next(o);
        },
      ),
    );
    repo = PublicCardRepository(fake.client);
  });

  test('fetchCard hits /public/card/:slug anonymously', () async {
    fake.on(
      'GET',
      '/public/card/jane',
      FakeResponse.ok({'slug': 'jane', 'title': 'Jane'}),
    );
    final card = await repo.fetchCard('jane');
    expect(card.name, 'Jane');
    expect(anonymousFlags, [true]);
  });

  test('fetchCard maps 404/403/410 to unavailable kinds', () async {
    for (final (status, kind) in [
      (404, AppErrorKind.notFound),
      (403, AppErrorKind.forbidden),
      (410, AppErrorKind.gone),
    ]) {
      fake.on('GET', '/public/card/x', FakeResponse.error(status, 'nope'));
      await expectLater(
        repo.fetchCard('x'),
        throwsA(isA<AppException>().having((e) => e.kind, 'kind', kind)),
      );
    }
  });

  test('fetchReviews paginates and drops non-approved items', () async {
    fake.on(
      'GET',
      '/public/card/jane/reviews',
      FakeResponse.ok({
        'reviews': [
          {
            '_id': '1',
            'name': 'A',
            'rating': 5,
            'status': 'approved',
            'email': 'a@x.test',
          },
          {'_id': '2', 'name': 'B', 'rating': 1, 'status': 'pending'},
          {'_id': '3', 'name': 'C', 'rating': 3},
        ],
        'total': 30,
        'page': 1,
        'pages': 3,
      }),
    );
    final page = await repo.fetchReviews('jane');
    expect(page.items.map((r) => r.id), ['1', '3']);
    expect(page.hasMore, isTrue);
    expect(page.total, 30);
    expect(fake.requests.single.query, {
      'page': 1,
      'limit': PublicCardRepository.reviewsPageSize,
    });
    expect(anonymousFlags, [true]);
  });

  group('submitReview', () {
    const body = ReviewSubmission(rating: 4, name: 'Sam', comment: 'Nice');

    test('posts {rating, name, comment} and parses status', () async {
      fake.on(
        'POST',
        '/public/card/jane/review',
        FakeResponse.ok({'status': 'pending'}),
      );
      final result = await repo.submitReview('jane', body);
      expect(result.isApproved, isFalse);
      // Backend schema requires `reviewerName` (not `name`).
      expect(fake.requests.single.body, {
        'reviewerName': 'Sam',
        'rating': 4,
        'comment': 'Nice',
      });
      expect(anonymousFlags, [true]);
    });

    test('409 maps to conflict', () async {
      fake.on(
        'POST',
        '/public/card/jane/review',
        FakeResponse.error(409, 'Duplicate'),
      );
      await expectLater(
        repo.submitReview('jane', body),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.conflict,
          ),
        ),
      );
    });

    test('429 maps to rateLimited with retryAfter', () async {
      fake.on(
        'POST',
        '/public/card/jane/review',
        FakeResponse.error(
          429,
          'Slow down',
          headers: {
            'retry-after': ['42'],
          },
        ),
      );
      await expectLater(
        repo.submitReview('jane', body),
        throwsA(
          isA<AppException>()
              .having((e) => e.kind, 'kind', AppErrorKind.rateLimited)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 42),
              ),
        ),
      );
    });
  });

  test(
    'trackClick posts {cardId, linkType, linkUrl} and swallows errors',
    () async {
      fake.on(
        'POST',
        '/public/track-click',
        FakeResponse.error(400, 'Required'),
      );
      await repo.trackClick(
        cardId: 'c1',
        linkType: TrackType.social('LinkedIn'),
        linkUrl: 'https://linkedin.com/in/jane',
      );
      expect(fake.requests.single.body, {
        'cardId': 'c1',
        'linkType': 'social:linkedin',
        'linkUrl': 'https://linkedin.com/in/jane',
      });
      expect(anonymousFlags, [true]);

      // Omits an empty linkUrl; caps linkType at the backend's 64 chars.
      await repo.trackClick(
        cardId: 'c1',
        linkType: TrackType.custom('x' * 100),
      );
      final body = fake.requests.last.body! as Map;
      expect(body.keys, unorderedEquals(['cardId', 'linkType']));
      expect((body['linkType'] as String).length, TrackType.maxLength);

      // No card id → nothing sent.
      await repo.trackClick(cardId: '', linkType: TrackType.phone);
      expect(fake.requests, hasLength(2));
    },
  );

  test('public reviews derive hasMore from page*limit < total', () async {
    fake.on(
      'GET',
      '/public/card/jane/reviews',
      FakeResponse.ok({
        'items': [
          {
            '_id': '1',
            'reviewerName': 'A',
            'rating': 5,
            'reviewerEmail': 'a@x.test',
          },
        ],
        'total': 11,
        'page': 1,
        'limit': 10,
      }),
    );
    final page = await repo.fetchReviews('jane');
    expect(page.hasMore, isTrue);
    expect(page.items.single.reviewerName, 'A');

    fake.on(
      'GET',
      '/public/card/jane/reviews',
      FakeResponse.ok({'items': [], 'total': 11, 'page': 2, 'limit': 10}),
    );
    expect((await repo.fetchReviews('jane', page: 2)).hasMore, isFalse);
  });

  test('fetchVcard downloads bytes anonymously', () async {
    fake.on('GET', '/cards/c1/vcard', const FakeResponse(200, 'BEGIN:VCARD'));
    final bytes = await repo.fetchVcard('c1');
    expect(bytes, isNotEmpty);
    expect(anonymousFlags, [true]);
  });

  test('fetchDirectory hits the proposed directory endpoint', () async {
    fake.on(
      'GET',
      '/public/organizations/acme/directory',
      FakeResponse.ok({
        'organization': {'name': 'Acme'},
        'items': [
          {'slug': 'a', 'name': 'Ann'},
        ],
        'hasMore': false,
      }),
    );
    final page = await repo.fetchDirectory('acme');
    expect(page.entries.single.name, 'Ann');
    expect(page.organizationName, 'Acme');
    expect(anonymousFlags, [true]);
  });
}
