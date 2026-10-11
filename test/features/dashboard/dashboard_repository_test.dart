import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/features/dashboard/data/dashboard_repository.dart';
import 'package:bizzvot/features/dashboard/domain/dashboard_overview.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';

void main() {
  late FakeApi fake;
  late DashboardRepository repo;

  setUp(() {
    fake = FakeApi();
    repo = DashboardRepository(fake.client);
  });

  test('maps the real backend payload and takes the name from the profile', () async {
    fake
      ..on('GET', '/organization/dashboard', FakeResponse.ok({
        'cards': 3,
        'cardsLimit': 3,
        'staff': 2,
        'staffLimit': 2,
        'reviews': 5,
        'averageRating': 4.25,
      }))
      ..on('GET', '/organization/profile', FakeResponse.ok({
        '_id': 'org1',
        'name': 'Acme',
        'status': 'active',
        'planExpiry': '2026-12-01T00:00:00.000Z',
      }));

    final o = await repo.fetchOverview();

    expect(o.organizationName, 'Acme');
    expect(o.organizationStatus, 'active');
    expect(o.totalCards, 3);
    expect(o.cardsLimit, 3);
    expect(o.staffCount, 2);
    expect(o.staffLimit, 2);
    expect(o.totalReviews, 5);
    expect(o.averageRating, 4.25);
    expect(o.cardSlotsFull, isTrue);
    expect(o.staffSlotsFull, isTrue);
    expect(o.unlimitedCards, isFalse);
    expect(o.planExpiry, isNotNull);
    expect(o.trial, isNull);
  });

  test('a failing profile does not hide the counts', () async {
    fake
      ..on('GET', '/organization/dashboard',
          FakeResponse.ok({'cards': 1, 'cardsLimit': 3, 'reviews': 0}))
      ..on('GET', '/organization/profile', FakeResponse.error(500, 'boom'));

    final o = await repo.fetchOverview();
    expect(o.organizationName, 'Your organization');
    expect(o.totalCards, 1);
    expect(o.cardSlotsFull, isFalse);
  });

  test('dashboard failures propagate as AppException', () async {
    fake.on('GET', '/organization/dashboard', FakeResponse.error(403, 'Forbidden'));
    fake.on('GET', '/organization/profile', FakeResponse.ok({'name': 'Acme'}));
    await expectLater(
      repo.fetchOverview(),
      throwsA(isA<AppException>().having((e) => e.kind, 'kind', AppErrorKind.forbidden)),
    );
  });

  test('missing/negative limits mean unlimited; future fields are read', () {
    final o = DashboardOverview.fromJson({
      'cards': 7,
      'cardsLimit': null,
      'staffLimit': -1,
      'activeCards': 5,
      'disabledByBilling': 2,
      'organization': {'name': 'Beta', 'status': 'trial'},
      'trial': {'active': true, 'daysRemaining': 4},
    });
    expect(o.organizationName, 'Beta');
    expect(o.unlimitedCards, isTrue);
    expect(o.staffLimit, isNull);
    expect(o.activeCards, 5);
    expect(o.disabledByBilling, 2);
    expect(o.trial?.daysRemaining, 4);
  });
}
