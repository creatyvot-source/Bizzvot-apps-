import 'package:bizzvot/core/auth/auth_user.dart';
import 'package:bizzvot/features/cards/presentation/card_detail_screen.dart';
import 'package:bizzvot/features/cards/presentation/card_share_screen.dart';
import 'package:bizzvot/features/cards/presentation/cards_list_screen.dart';
import 'package:bizzvot/features/cards/presentation/my_card_screen.dart';
import 'package:bizzvot/features/cards/presentation/widgets/card_preview.dart';
import 'package:bizzvot/shared/models/card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import 'cards_test_harness.dart';

void main() {
  group('CardsListScreen', () {
    testWidgets('lists cards with chips, filters and opens detail', (tester) async {
      final api = BinaryFakeApi()
        ..on('GET', '/organization/cards', FakeResponse.ok([
          cardJson(),
          cardJson(id: 'c2', status: 'disabled', disabledByBilling: true, visibility: 'private',
              extra: {'title': 'Bo Chen'}),
        ]));
      await pumpScreen(tester, const CardsListScreen(), api: api);

      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('Bo Chen'), findsOneWidget);
      expect(find.text('Disabled by billing'), findsWidgets);
      expect(find.text('Private'), findsOneWidget);
      expect(find.byTooltip('Share all QR codes'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Active'));
      await tester.pumpAndSettle();
      expect(find.text('Bo Chen'), findsNothing);
      expect(find.text('1 of 2 cards'), findsOneWidget);

      await tester.tap(find.text('Asha Rao'));
      await tester.pumpAndSettle();
      expect(find.text('route:/o/cards/c1'), findsOneWidget);
    });

    testWidgets('search with no match shows a clearable empty state', (tester) async {
      final api = BinaryFakeApi()..on('GET', '/organization/cards', FakeResponse.ok([cardJson()]));
      await pumpScreen(tester, const CardsListScreen(), api: api);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No matching cards'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('Asha Rao'), findsOneWidget);
    });

    testWidgets('empty organization shows add-staff CTA', (tester) async {
      final api = BinaryFakeApi()..on('GET', '/organization/cards', FakeResponse.ok([]));
      await pumpScreen(tester, const CardsListScreen(), api: api);
      expect(find.text('No cards yet'), findsOneWidget);
      expect(find.text('Add staff member'), findsOneWidget);
    });

    testWidgets('shares all QR codes as PNG files', (tester) async {
      final share = FakeShareService();
      final api = BinaryFakeApi()
        ..on('GET', '/organization/cards', FakeResponse.ok([cardJson()]))
        ..on('GET', '/organization/cards/qrcodes', FakeResponse.ok([
          {'cardId': 'c1', 'slug': 'asha-rao', 'dataUrl': tinyPngDataUrl},
        ]));
      await pumpScreen(tester, const CardsListScreen(), api: api, share: share);
      await tester.tap(find.byTooltip('Share all QR codes'));
      await tester.pumpAndSettle();
      expect(share.sharedFiles.single.single.name, 'qr-asha-rao.png');
    });

    testWidgets('load error shows retry', (tester) async {
      final api = BinaryFakeApi()..on('GET', '/organization/cards', FakeResponse.error(500, 'boom'));
      await pumpScreen(tester, const CardsListScreen(), api: api);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('CardDetailScreen', () {
    testWidgets('activates via status endpoint', (tester) async {
      final api = BinaryFakeApi()
        ..on('GET', '/organization/cards/c1', FakeResponse.ok(cardJson(status: 'disabled')))
        ..on('PATCH', '/organization/cards/status', FakeResponse.ok(null));
      await pumpScreen(tester, const CardDetailScreen(cardId: 'c1'), api: api);

      expect(find.byType(CardPreview), findsOneWidget);
      await tester.ensureVisible(find.text('Activate card'));
      await tester.tap(find.text('Activate card'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Activate'));
      await tester.pumpAndSettle();

      final req = api.requests.firstWhere((r) => r.method == 'PATCH');
      expect(req.body, {'cardIds': ['c1'], 'status': 'active'});
    });

    testWidgets('billing-disabled card explains and 409 suggests seats', (tester) async {
      final api = BinaryFakeApi()
        ..on('GET', '/organization/cards/c1',
            FakeResponse.ok(cardJson(status: 'disabled', disabledByBilling: true)))
        ..on('PATCH', '/organization/cards/status', FakeResponse.error(409, 'No free paid slot.'));
      await pumpScreen(tester, const CardDetailScreen(cardId: 'c1'), api: api);

      expect(find.textContaining('server confirms a free paid card slot'), findsOneWidget);
      await tester.ensureVisible(find.text('Activate card'));
      await tester.tap(find.text('Activate card'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Activate'));
      await tester.pumpAndSettle();

      expect(find.text('Card could not be activated'), findsOneWidget);
      expect(find.textContaining('No free paid slot.'), findsOneWidget);
      await tester.tap(find.text('View seats'));
      await tester.pumpAndSettle();
      expect(find.text('route:/o/billing/seats'), findsOneWidget);
    });

    testWidgets('delete asks for confirmation', (tester) async {
      final api = BinaryFakeApi()
        ..on('GET', '/organization/cards/c1', FakeResponse.ok(cardJson()))
        ..on('GET', '/organization/cards', FakeResponse.ok([]))
        ..on('DELETE', '/organization/cards/c1', FakeResponse.ok(null));
      await pumpScreen(tester, const CardDetailScreen(cardId: 'c1'), api: api, pushed: true);
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete card'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this card?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(api.requests.any((r) => r.method == 'DELETE'), isTrue);
      expect(find.text('open'), findsOneWidget); // popped back
    });
  });

  group('CardPreview', () {
    testWidgets('never renders private details', (tester) async {
      final card = CardModel.fromJson(cardJson());
      expect(card.hasPrivateDetails, isTrue);
      for (final t in CardTemplate.values) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: CardPreview(card: card.copyWith(template: t)))),
        ));
        expect(find.text('Asha Rao'), findsOneWidget);
        expect(find.textContaining('O+'), findsNothing);
        expect(find.textContaining('Ravi'), findsNothing);
        expect(find.textContaining('Meena'), findsNothing);
      }
    });

    test('hex helpers', () {
      expect(toHex(parseHexColor('#1f4fd8')!), '#1F4FD8');
      expect(parseHexColor('red'), isNull);
    });
  });

  group('CardShareScreen', () {
    testWidgets('shows QR, copies and shares link, shares vCard', (tester) async {
      final share = FakeShareService();
      final api = BinaryFakeApi()
        ..on('GET', '/organization/cards/c1', FakeResponse.ok(cardJson()))
        ..onBytes('GET', '/cards/c1/qrcode', tinyPng)
        ..onBytes('GET', '/cards/c1/vcard', tinyVcard);
      await pumpScreen(tester, const CardShareScreen(cardId: 'c1'), api: api, share: share);

      expect(find.bySemanticsLabel(RegExp('QR code that opens the card')), findsOneWidget);
      expect(find.textContaining('/card/asha-rao'), findsOneWidget);

      await tester.tap(find.byTooltip('Copy link'));
      await tester.pumpAndSettle();
      expect(share.copied.single, endsWith('/card/asha-rao'));

      await tester.tap(find.text('Share link'));
      await tester.pumpAndSettle();
      expect(share.sharedTexts.single, endsWith('/card/asha-rao'));

      await tester.ensureVisible(find.text('Share / save contact (vCard)'));
      await tester.tap(find.text('Share / save contact (vCard)'));
      await tester.pumpAndSettle();
      expect(share.sharedFiles.single.single.name, 'asha-rao.vcf');
      expect(share.sharedFiles.single.single.mimeType, 'text/vcard');
    });

    testWidgets('hides vCard when disabled; staff mode uses /staff/card', (tester) async {
      final api = BinaryFakeApi()
        ..on('GET', '/staff/card', FakeResponse.ok(cardJson(extra: {'vcardEnabled': false})))
        ..onBytes('GET', '/cards/c1/qrcode', tinyPng);
      await pumpScreen(
        tester,
        const CardShareScreen(staffMode: true),
        api: api,
        user: staffUser(),
      );
      expect(find.text('Share / save contact (vCard)'), findsNothing);
      expect(find.textContaining('turned off'), findsOneWidget);
      expect(api.requests.any((r) => r.path.startsWith('/organization')), isFalse);
    });
  });

  group('MyCardScreen', () {
    testWidgets('shows preview and permission-gated actions', (tester) async {
      final api = BinaryFakeApi()..on('GET', '/staff/card', FakeResponse.ok(cardJson()));
      await pumpScreen(
        tester,
        const MyCardScreen(),
        api: api,
        user: staffUser(permissions: const StaffPermissions(manageLinks: true)),
      );
      expect(find.byType(CardPreview), findsOneWidget);
      expect(find.text('Edit links'), findsOneWidget);
      await tester.ensureVisible(find.text('Share & QR'));
      await tester.tap(find.text('Share & QR'));
      await tester.pumpAndSettle();
      expect(find.text('route:/s/card/share'), findsOneWidget);
    });

    testWidgets('no edit button without permissions', (tester) async {
      final api = BinaryFakeApi()..on('GET', '/staff/card', FakeResponse.ok(cardJson()));
      await pumpScreen(tester, const MyCardScreen(), api: api, user: staffUser());
      expect(find.text('Edit card'), findsNothing);
      expect(find.text('Edit links'), findsNothing);
      expect(find.textContaining('managed by your organization owner'), findsOneWidget);
    });

    testWidgets('empty state when no card assigned', (tester) async {
      final api = BinaryFakeApi()..on('GET', '/staff/card', FakeResponse.ok(null));
      await pumpScreen(tester, const MyCardScreen(), api: api, user: staffUser(cardId: null));
      expect(find.text('No card assigned yet'), findsOneWidget);
    });
  });
}
