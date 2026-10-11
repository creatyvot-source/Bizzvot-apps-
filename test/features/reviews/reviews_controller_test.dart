import 'dart:async';

import 'package:bizzvot/core/auth/session_controller.dart';
import 'package:bizzvot/features/reviews/data/reviews_repository.dart';
import 'package:bizzvot/features/reviews/presentation/reviews_providers.dart';
import 'package:bizzvot/shared/models/review.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import 'reviews_repository_test.dart' show reviewJson;

void main() {
  late FakeApi fake;
  late ProviderContainer container;
  const scope = ReviewScope.owner;

  setUp(() {
    fake = FakeApi()
      ..onDynamic('GET', '/organization/reviews', (req) {
        final status = req.query['status'];
        final all = [
          reviewJson('1'),
          reviewJson('2', status: 'approved'),
          reviewJson('3', status: 'hidden'),
        ];
        return FakeResponse.ok({
          'reviews': status == null
              ? all
              : all.where((r) => r['status'] == status).toList(),
        });
      });
    container = ProviderContainer.test(
      overrides: [
        sessionKeyProvider.overrideWithValue('user-1'),
        reviewsRepositoryProvider.overrideWithValue(
          ReviewsRepository(fake.client),
        ),
      ],
    );
  });

  Future<ReviewsState> load() {
    final sub = container.listen(reviewsControllerProvider(scope), (_, _) {});
    addTearDown(sub.close);
    return container.read(reviewsControllerProvider(scope).future);
  }

  test('filter change refetches with the status param', () async {
    expect((await load()).items, hasLength(3));
    container
        .read(reviewFilterProvider(scope).notifier)
        .select(ReviewFilter.hidden);
    final s = await container.read(reviewsControllerProvider(scope).future);
    expect(s.filter, ReviewFilter.hidden);
    expect(s.items.single.id, '3');
    expect(fake.requests.last.query['status'], 'hidden');
  });

  test('setStatus is optimistic and keeps the server echo', () async {
    await load();
    final gate = Completer<void>();
    fake.onDynamic('PATCH', '/organization/reviews/1/status', (_) {
      return FakeResponse.ok({'review': reviewJson('1', status: 'approved')});
    });
    final pending = container
        .read(reviewsControllerProvider(scope).notifier)
        .setStatus('1', ReviewStatus.approved)
        .whenComplete(gate.complete);

    final during = container.read(reviewsControllerProvider(scope)).value!;
    expect(during.items.first.status, ReviewStatus.approved);
    expect(during.busyIds, contains('1'));
    // Defensive local filtering moves it out of the pending view at once.
    expect(during.visible(ReviewFilter.pending), isEmpty);

    await pending;
    final after = container.read(reviewsControllerProvider(scope)).value!;
    expect(after.items.first.status, ReviewStatus.approved);
    expect(after.busyIds, isEmpty);
  });

  test('setStatus rolls back on error and rethrows', () async {
    await load();
    fake.on(
      'PATCH',
      '/organization/reviews/1/status',
      FakeResponse.error(500, 'boom'),
    );
    await expectLater(
      container
          .read(reviewsControllerProvider(scope).notifier)
          .setStatus('1', ReviewStatus.hidden),
      throwsA(anything),
    );
    final s = container.read(reviewsControllerProvider(scope)).value!;
    expect(s.items.first.status, ReviewStatus.pending);
    expect(s.busyIds, isEmpty);
  });

  test('reply is optimistic and rolls back on error', () async {
    await load();
    fake.on(
      'POST',
      '/organization/reviews/2/reply',
      FakeResponse.error(422, 'Too long'),
    );
    final future = container
        .read(reviewsControllerProvider(scope).notifier)
        .reply('2', 'Thanks a lot');
    expect(
      container
          .read(reviewsControllerProvider(scope))
          .value!
          .items[1]
          .reply
          ?.text,
      'Thanks a lot',
    );
    await expectLater(future, throwsA(anything));
    expect(
      container.read(reviewsControllerProvider(scope)).value!.items[1].reply,
      isNull,
    );
  });
}
