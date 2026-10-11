import 'package:bizzvot/features/directory_visibility/data/directory_visibility_repository.dart';
import 'package:bizzvot/features/directory_visibility/presentation/directory_visibility_screen.dart';
import 'package:bizzvot/shared/models/card.dart';
import 'package:bizzvot/shared/models/organization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../cards/cards_test_harness.dart';

void main() {
  group('DirectoryVisibilityRepository', () {
    late FakeApi api;
    late DirectoryVisibilityRepository repo;

    setUp(() {
      api = FakeApi();
      repo = DirectoryVisibilityRepository(api.client);
    });

    test('reads directoryVisibility from the profile', () async {
      api.on(
        'GET',
        '/organization/profile',
        FakeResponse.ok({
          'organization': {
            '_id': 'o1',
            'name': 'Acme',
            'slug': 'acme',
            'directoryVisibility': 'private',
          },
        }),
      );
      final p = await repo.profile();
      expect(p.directoryVisibility, DirectoryVisibility.private);
      expect(p.slug, 'acme');
    });

    test('PATCH bodies carry only the visibility field', () async {
      api
        ..on('PATCH', '/organization/profile', FakeResponse.ok(null))
        ..on('PATCH', '/organization/cards/c1', FakeResponse.ok(null));
      await repo.setDirectoryVisibility(DirectoryVisibility.public);
      await repo.setCardVisibility('c1', CardVisibility.private);
      expect(api.requests[0].body, {'directoryVisibility': 'public'});
      expect(api.requests[1].body, {'visibility': 'private'});
    });

    test('bulk update is sequential and reports partial failures', () async {
      api
        ..on('PATCH', '/organization/cards/a', FakeResponse.ok(null))
        ..on(
          'PATCH',
          '/organization/cards/b',
          FakeResponse.error(403, 'Not allowed for this card.'),
        )
        ..on('PATCH', '/organization/cards/c', FakeResponse.ok(null));
      final progress = <int>[];
      final result = await repo.bulkSetVisibility(
        ['a', 'b', 'c'],
        CardVisibility.public,
        onProgress: (done, _) => progress.add(done),
      );
      expect(result.succeeded, ['a', 'c']);
      expect(result.failed, {'b': 'Not allowed for this card.'});
      expect(progress, [1, 2, 3]);
      expect(api.requests.map((r) => r.path), [
        '/organization/cards/a',
        '/organization/cards/b',
        '/organization/cards/c',
      ]);
    });

    test('bulk update stops on rate limiting', () async {
      api
        ..on(
          'PATCH',
          '/organization/cards/a',
          FakeResponse.error(429, 'Slow down'),
        )
        ..on('PATCH', '/organization/cards/b', FakeResponse.ok(null));
      final result = await repo.bulkSetVisibility([
        'a',
        'b',
      ], CardVisibility.private);
      expect(result.succeeded, isEmpty);
      expect(result.failed.keys, ['a', 'b']);
      expect(api.requests, hasLength(1));
    });
  });

  group('DirectoryVisibilityScreen', () {
    BinaryFakeApi buildApi({String directory = 'public'}) => BinaryFakeApi()
      ..on(
        'GET',
        '/organization/profile',
        FakeResponse.ok({
          '_id': 'o1',
          'name': 'Acme',
          'slug': 'acme',
          'directoryVisibility': directory,
        }),
      )
      ..on(
        'GET',
        '/organization/cards',
        FakeResponse.ok([
          cardJson(id: 'a', extra: {'title': 'Asha Rao'}),
          cardJson(id: 'b', visibility: 'private', extra: {'title': 'Bo Chen'}),
          cardJson(
            id: 'c',
            visibility: 'public',
            status: 'disabled',
            extra: {'title': 'Cy Diaz'},
          ),
        ]),
      );

    Future<void> pump(WidgetTester tester, BinaryFakeApi api) => pumpScreen(
      tester,
      const DirectoryVisibilityScreen(),
      api: api,
      extra: [
        directoryVisibilityRepositoryProvider.overrideWithValue(
          DirectoryVisibilityRepository(api.client),
        ),
      ],
    );

    testWidgets('explains precedence and shows per-card status', (
      tester,
    ) async {
      final api = buildApi();
      await pump(tester, api);
      expect(find.text('How visibility works'), findsOneWidget);
      expect(
        find.textContaining('does not block its direct link'),
        findsOneWidget,
      );
      expect(find.text('Listed in the directory'), findsOneWidget);
      expect(find.text('Hidden · card is private'), findsOneWidget);
      expect(find.text('Hidden · card is not active'), findsOneWidget);

      await tester.tap(find.byTooltip('Preview directory'));
      await tester.pumpAndSettle();
      expect(find.text('route:/directory/acme'), findsOneWidget);
    });

    testWidgets('making the directory private confirms and PATCHes', (
      tester,
    ) async {
      final api = buildApi()
        ..on('PATCH', '/organization/profile', FakeResponse.ok(null));
      await pump(tester, api);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Hide the people directory?'), findsOneWidget);
      await tester.tap(find.text('Hide directory'));
      await tester.pumpAndSettle();
      expect(api.requests.firstWhere((r) => r.method == 'PATCH').body, {
        'directoryVisibility': 'private',
      });
    });

    testWidgets('private org hides everyone', (tester) async {
      await pump(tester, buildApi(directory: 'private'));
      expect(find.text('Listed in the directory'), findsNothing);
      expect(find.text('Hidden · directory is private'), findsNWidgets(2));
      expect(find.text('Hidden · card is private'), findsOneWidget);
    });

    testWidgets('bulk make public reports partial failures', (tester) async {
      final api = buildApi()
        ..on('PATCH', '/organization/cards/a', FakeResponse.ok(null))
        ..on(
          'PATCH',
          '/organization/cards/b',
          FakeResponse.error(409, 'Card is locked.'),
        );
      await pump(tester, api);

      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Checkbox && w.semanticLabel == 'Select Asha Rao',
        ),
      );
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Checkbox && w.semanticLabel == 'Select Bo Chen',
        ),
      );
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.text('Make public'));
      await tester.pumpAndSettle();
      expect(find.text('Make 2 cards public?'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Some cards were not updated'), findsOneWidget);
      expect(find.textContaining('1 of 2 cards were updated'), findsOneWidget);
      expect(find.textContaining('Card is locked.'), findsOneWidget);
      final patches = api.requests.where((r) => r.method == 'PATCH').toList();
      expect(
        patches.map((r) => r.body),
        everyElement({'visibility': 'public'}),
      );
    });
  });
}
