import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/features/analytics/data/analytics_repository.dart';
import 'package:bizzvot/features/analytics/domain/analytics_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';

void main() {
  late FakeApi fake;
  late AnalyticsRepository repo;

  setUp(() {
    fake = FakeApi();
    repo = AnalyticsRepository(
      fake.client,
      clock: () => DateTime(2026, 10, 11),
    );
  });

  test(
    'views/reviews/links hit /analytics/card/:id/* with range params',
    () async {
      fake
        ..on(
          'GET',
          '/analytics/card/c1/views',
          FakeResponse.ok({'total': 5, 'unique': 3}),
        )
        ..on(
          'GET',
          '/analytics/card/c1/reviews',
          FakeResponse.ok({'total': 2, 'average': 4.5}),
        )
        ..on(
          'GET',
          '/analytics/card/c1/links',
          FakeResponse.ok({
            'items': [
              {'type': 'email', 'count': 1},
            ],
          }),
        );

      final v = await repo.fetchViews('c1', AnalyticsRange.month);
      final r = await repo.fetchReviews('c1', AnalyticsRange.month);
      final l = await repo.fetchLinks('c1', AnalyticsRange.month);

      expect(v.total, 5);
      expect(r.average, 4.5);
      expect(l.counts.single, (LinkCategory.email, 1));
      for (final req in fake.requests) {
        expect(req.query, {
          'range': '30d',
          'from': '2026-09-12',
          'to': '2026-10-11',
        });
      }
    },
  );

  test('403 for another card surfaces as forbidden', () async {
    fake.on(
      'GET',
      '/analytics/card/other/views',
      FakeResponse.error(403, 'Not your card'),
    );
    await expectLater(
      repo.fetchViews('other', AnalyticsRange.week),
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
