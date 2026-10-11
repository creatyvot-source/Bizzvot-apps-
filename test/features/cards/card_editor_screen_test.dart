import 'package:bizzvot/core/auth/auth_user.dart';
import 'package:bizzvot/features/cards/data/media_picker.dart';
import 'package:bizzvot/features/cards/presentation/card_editor_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import 'cards_test_harness.dart';

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> tapSave(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Save'));
  await tester.pumpAndSettle();
}

void main() {
  group('owner', () {
    testWidgets('saves only the changed fields', (tester) async {
      final api = BinaryFakeApi()
        ..on('GET', '/organization/cards/c1', FakeResponse.ok(cardJson()))
        ..on(
          'PATCH',
          '/organization/cards/c1',
          FakeResponse.ok(cardJson(extra: {'title': 'Asha R.'})),
        );
      await pumpScreen(tester, const CardEditorScreen(cardId: 'c1'), api: api);

      // All owner sections are present, private details clearly labelled.
      expect(find.text('Identity'), findsOneWidget);
      expect(find.text('Directory visibility'), findsOneWidget);
      expect(
        find.textContaining('Private · never shown publicly'),
        findsOneWidget,
      );

      // Save is disabled until something changes.
      final save = find.widgetWithText(TextButton, 'Save');
      expect(tester.widget<TextButton>(save).onPressed, isNull);

      await tester.enterText(field('Name on card'), 'Asha R.');
      await tester.pump();
      expect(tester.widget<TextButton>(save).onPressed, isNotNull);

      await tester.ensureVisible(find.text('Private'));
      await tester.tap(find.text('Private'));
      await tester.pump();

      await tapSave(tester);
      final patch = api.requests.firstWhere((r) => r.method == 'PATCH');
      expect(patch.body, {'title': 'Asha R.', 'visibility': 'private'});
      expect(find.text('Card saved'), findsOneWidget);
    });

    testWidgets('validates contact fields before saving', (tester) async {
      final api = BinaryFakeApi()
        ..on('GET', '/organization/cards/c1', FakeResponse.ok(cardJson()));
      await pumpScreen(tester, const CardEditorScreen(cardId: 'c1'), api: api);
      await tester.enterText(field('Email'), 'not-an-email');
      await tester.enterText(field('Website'), 'javascript:alert(1)');
      await tester.pump();
      await tapSave(tester);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Enter a valid https:// link'), findsOneWidget);
      expect(api.requests.where((r) => r.method == 'PATCH'), isEmpty);
    });

    testWidgets('unsaved changes guard asks before leaving', (tester) async {
      final api = BinaryFakeApi()
        ..on('GET', '/organization/cards/c1', FakeResponse.ok(cardJson()));
      await pumpScreen(
        tester,
        const CardEditorScreen(cardId: 'c1'),
        api: api,
        pushed: true,
      );
      await tester.enterText(field('Designation'), 'Head of Sales');
      await tester.pump();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Edit card'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('uploads gallery images and enforces the limit', (
      tester,
    ) async {
      final picker = FakeMediaPicker(
        images: [PickedFile(name: 'one.png', bytes: tinyPng)],
      );
      final api = BinaryFakeApi()
        ..on(
          'GET',
          '/organization/cards/c1',
          FakeResponse.ok(
            cardJson(
              extra: {
                'gallery': List.generate(
                  4,
                  (i) => 'https://cdn.example.com/g$i.png',
                ),
              },
            ),
          ),
        )
        ..on(
          'POST',
          '/media/upload',
          FakeResponse.ok({'url': 'https://cdn.example.com/new.png'}),
        )
        ..on('PATCH', '/organization/cards/c1', FakeResponse.ok(cardJson()));
      await pumpScreen(
        tester,
        const CardEditorScreen(cardId: 'c1'),
        api: api,
        picker: picker,
      );

      expect(find.text('4 of 5'), findsOneWidget);
      await tester.ensureVisible(find.text('Add images'));
      await tester.tap(find.text('Add images'));
      await tester.pumpAndSettle();
      expect(picker.lastLimit, 1);
      expect(find.text('5 of 5'), findsOneWidget);
      expect(find.text('Gallery is full'), findsOneWidget);

      final upload = api.requests.firstWhere((r) => r.path == '/media/upload');
      expect((upload.body as FormData).files.single.key, 'file');

      await tapSave(tester);
      final patch = api.requests.firstWhere((r) => r.method == 'PATCH');
      expect((patch.body as Map)['gallery'], hasLength(5));
    });

    testWidgets('rejects non-image files client-side', (tester) async {
      final picker = FakeMediaPicker(
        image: PickedFile(name: 'x.png', bytes: tinyPdf),
      );
      final api = BinaryFakeApi()
        ..on('GET', '/organization/cards/c1', FakeResponse.ok(cardJson()));
      await pumpScreen(
        tester,
        const CardEditorScreen(cardId: 'c1'),
        api: api,
        picker: picker,
      );
      await tester.ensureVisible(find.byTooltip('Upload Profile photo'));
      await tester.tap(find.byTooltip('Upload Profile photo'));
      await tester.pumpAndSettle();
      expect(find.text('Use a JPG, PNG or WebP image.'), findsOneWidget);
      expect(api.requests.where((r) => r.path == '/media/upload'), isEmpty);
    });

    testWidgets('removed PDFs are deleted from the library after save', (
      tester,
    ) async {
      final api = BinaryFakeApi()
        ..on(
          'GET',
          '/organization/cards/c1',
          FakeResponse.ok(
            cardJson(
              extra: {
                'pdfs': [
                  {
                    'url': 'https://cdn.example.com/brochure.pdf',
                    'name': 'Brochure',
                  },
                ],
              },
            ),
          ),
        )
        ..on('PATCH', '/organization/cards/c1', FakeResponse.ok(cardJson()))
        ..on('DELETE', '/cards/c1/library', FakeResponse.ok(null));
      await pumpScreen(tester, const CardEditorScreen(cardId: 'c1'), api: api);
      await tester.ensureVisible(find.byTooltip('Remove document'));
      await tester.tap(find.byTooltip('Remove document'));
      await tester.pump();
      await tapSave(tester);
      expect(
        (api.requests.firstWhere((r) => r.method == 'PATCH').body
            as Map)['pdfs'],
        isEmpty,
      );
      final del = api.requests.firstWhere((r) => r.method == 'DELETE');
      expect(del.body, {'url': 'https://cdn.example.com/brochure.pdf'});
    });
  });

  group('staff', () {
    testWidgets('manageLinks only shows links and PATCHes /staff/card', (
      tester,
    ) async {
      final api = BinaryFakeApi()
        ..on('GET', '/staff/card', FakeResponse.ok(cardJson()))
        ..on('PATCH', '/staff/card', FakeResponse.ok(cardJson()));
      await pumpScreen(
        tester,
        const CardEditorScreen(staffMode: true),
        api: api,
        user: staffUser(permissions: const StaffPermissions(manageLinks: true)),
      );

      expect(find.text('Social & custom links'), findsOneWidget);
      expect(find.text('Identity'), findsNothing);
      expect(find.text('Contact'), findsNothing);
      expect(find.textContaining('Private'), findsNothing);
      expect(find.text('Directory visibility'), findsNothing);

      await tester.tap(find.text('Add social link'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Link (https://)'),
        'http://insecure.example.com',
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        find.text('Use a secure link starting with https://'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Link (https://)'),
        'https://www.linkedin.com/in/asha',
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await tapSave(tester);
      final patch = api.requests.firstWhere((r) => r.method == 'PATCH');
      expect(patch.path, '/staff/card');
      expect((patch.body as Map).keys, ['socialLinks']);
      expect(
        api.requests.any((r) => r.path.startsWith('/organization')),
        isFalse,
      );
    });

    testWidgets('no permissions shows a locked state', (tester) async {
      final api = BinaryFakeApi();
      await pumpScreen(
        tester,
        const CardEditorScreen(staffMode: true),
        api: api,
        user: staffUser(),
      );
      expect(find.text('You can’t edit this card'), findsOneWidget);
      expect(api.requests, isEmpty);
    });
  });
}
