import 'dart:convert';
import 'dart:typed_data';

import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/features/cards/data/cards_repository.dart';
import 'package:bizzvot/features/cards/domain/qr_codes.dart';
import 'package:bizzvot/shared/models/card.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import 'cards_test_harness.dart';

void main() {
  late BinaryFakeApi api;
  late CardsRepository repo;

  setUp(() {
    api = BinaryFakeApi();
    repo = CardsRepository(api.client);
  });

  group('listCards', () {
    test('parses a bare array', () async {
      api.on(
        'GET',
        '/organization/cards',
        FakeResponse.ok([cardJson(), cardJson(id: 'c2')]),
      );
      final cards = await repo.listCards();
      expect(cards.map((c) => c.id), ['c1', 'c2']);
      expect(cards.first.template, CardTemplate.corporate);
      expect(cards.first.visibility, CardVisibility.inherit);
    });

    test('parses {cards: [...]} and drops rows without id', () async {
      api.on(
        'GET',
        '/organization/cards',
        FakeResponse.ok({
          'cards': [
            cardJson(status: 'disabled', disabledByBilling: true),
            {'title': 'no id'},
          ],
        }),
      );
      final cards = await repo.listCards();
      expect(cards, hasLength(1));
      expect(cards.single.isActive, isFalse);
      expect(cards.single.disabledByBilling, isTrue);
    });

    test('tolerates unexpected shapes', () async {
      api.on('GET', '/organization/cards', FakeResponse.ok('nope'));
      expect(await repo.listCards(), isEmpty);
    });
  });

  test('getCard unwraps {card: ...}', () async {
    api.on(
      'GET',
      '/organization/cards/c1',
      FakeResponse.ok({'card': cardJson(visibility: 'private')}),
    );
    final card = await repo.getCard('c1');
    expect(card.visibility, CardVisibility.private);
    expect(card.bloodGroup, 'O+');
  });

  test('updateCard sends the patch and re-fetches when not echoed', () async {
    api.on('PATCH', '/organization/cards/c1', FakeResponse.ok(null));
    api.on('GET', '/organization/cards/c1', FakeResponse.ok(cardJson()));
    final card = await repo.updateCard('c1', {'title': 'New'});
    expect(card.id, 'c1');
    final patch = api.requests.firstWhere((r) => r.method == 'PATCH');
    expect(patch.body, {'title': 'New'});
  });

  test('setStatus body is {cardIds, status}', () async {
    api.on('PATCH', '/organization/cards/status', FakeResponse.ok(null));
    await repo.setStatus(['c1'], CardStatus.active);
    expect(api.requests.single.body, {
      'cardIds': ['c1'],
      'status': 'active',
    });
  });

  test('setStatus surfaces 409 seat errors with the server message', () async {
    api.on(
      'PATCH',
      '/organization/cards/status',
      FakeResponse.error(409, 'No free paid card slot is available.'),
    );
    await expectLater(
      repo.setStatus(['c1'], CardStatus.active),
      throwsA(
        isA<AppException>()
            .having((e) => e.kind, 'kind', AppErrorKind.conflict)
            .having(
              (e) => e.message,
              'message',
              'No free paid card slot is available.',
            ),
      ),
    );
  });

  test('deleteCard calls DELETE', () async {
    api.on('DELETE', '/organization/cards/c1', FakeResponse.ok(null));
    await repo.deleteCard('c1');
    expect(api.requests.single.method, 'DELETE');
  });

  group('QR codes', () {
    test('qrCode returns PNG bytes as-is', () async {
      api.onBytes('GET', '/cards/c1/qrcode', tinyPng);
      expect(await repo.qrCode('c1'), tinyPng);
    });

    test('qrCode decodes a JSON data URL', () async {
      api.on(
        'GET',
        '/cards/c1/qrcode',
        FakeResponse.ok({'qrCode': tinyPngDataUrl}),
      );
      expect(await repo.qrCode('c1'), tinyPng);
    });

    test('allQrCodes parses JSON entries with url or dataUrl', () async {
      api.on(
        'GET',
        '/organization/cards/qrcodes',
        FakeResponse.ok([
          {'cardId': 'c1', 'slug': 'asha', 'dataUrl': tinyPngDataUrl},
          {'cardId': 'c2', 'url': 'https://cdn.example.com/qr/c2.png'},
          {'cardId': 'c3'},
        ]),
      );
      final bundle = await repo.allQrCodes();
      expect(bundle, isA<QrEntryList>());
      final entries = (bundle as QrEntryList).entries;
      expect(entries.map((e) => e.cardId), ['c1', 'c2']);
      expect(entries.last.url, 'https://cdn.example.com/qr/c2.png');
      expect(await repo.qrEntryImage(entries.first), tinyPng);
    });

    test('allQrCodes accepts a ZIP archive', () async {
      final zip = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 1, 2, 3]);
      api.onBytes('GET', '/organization/cards/qrcodes', zip);
      final bundle = await repo.allQrCodes();
      expect(bundle, isA<QrArchive>().having((a) => a.extension, 'ext', 'zip'));
    });

    test('qrEntryImage refuses non-https remote URLs', () async {
      const entry = QrCodeEntry(
        cardId: 'c',
        url: 'http://insecure.example.com/q.png',
      );
      expect(await repo.qrEntryImage(entry), isNull);
    });
  });

  test('vcard returns the file and rejects non-vCard bodies', () async {
    final vcf = Uint8List.fromList(
      utf8.encode('BEGIN:VCARD\nVERSION:3.0\nEND:VCARD\n'),
    );
    api.onBytes('GET', '/cards/c1/vcard', vcf);
    expect(await repo.vcard('c1'), vcf);

    api.on('GET', '/cards/c2/vcard', FakeResponse.ok({'nope': true}));
    await expectLater(repo.vcard('c2'), throwsA(isA<AppException>()));
  });

  group('uploads', () {
    test('uploadImage posts multipart field "file" and parses url', () async {
      api.on(
        'POST',
        '/media/upload',
        FakeResponse.ok({'url': 'https://cdn.example.com/a.png'}),
      );
      final url = await repo.uploadImage(
        bytes: tinyPng,
        filename: 'a.png',
        mimeType: 'image/png',
      );
      expect(url, 'https://cdn.example.com/a.png');
      final form = api.requests.single.body as FormData;
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'a.png');
    });

    test('uploadCardDocument goes to /cards/:id/media', () async {
      api.on(
        'POST',
        '/cards/c1/media',
        FakeResponse.ok({
          'file': {'location': 'https://cdn/x.pdf'},
        }),
      );
      final url = await repo.uploadCardDocument(
        'c1',
        bytes: tinyPdf,
        filename: 'x.pdf',
      );
      expect(url, 'https://cdn/x.pdf');
    });

    test('uploadedUrl handles many response shapes', () {
      expect(CardsRepository.uploadedUrl('https://a'), 'https://a');
      expect(
        CardsRepository.uploadedUrl({'secure_url': 'https://b'}),
        'https://b',
      );
      expect(
        CardsRepository.uploadedUrl({
          'media': {'url': 'https://c'},
        }),
        'https://c',
      );
      expect(
        CardsRepository.uploadedUrl({
          'pdfs': [
            {'url': 'https://old'},
            {'url': 'https://new'},
          ],
        }),
        'https://new',
      );
      expect(CardsRepository.uploadedUrl({}), isNull);
    });

    test('missing url is an error', () async {
      api.on('POST', '/media/upload', FakeResponse.ok({'ok': true}));
      await expectLater(
        repo.uploadImage(
          bytes: tinyPng,
          filename: 'a.png',
          mimeType: 'image/png',
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  test('removeLibraryFile sends DELETE with {url}', () async {
    api.on('DELETE', '/cards/c1/library', FakeResponse.ok(null));
    await repo.removeLibraryFile('c1', 'https://cdn/x.pdf');
    expect(api.requests.single.body, {'url': 'https://cdn/x.pdf'});
  });

  group('staff card', () {
    test('parses the card', () async {
      api.on('GET', '/staff/card', FakeResponse.ok({'card': cardJson()}));
      expect((await repo.staffCard())?.id, 'c1');
    });

    test('null data means no card assigned', () async {
      api.on('GET', '/staff/card', FakeResponse.ok(null));
      expect(await repo.staffCard(), isNull);
    });

    test(
      '404 without a known card id means none; with one it is an error',
      () async {
        api.on('GET', '/staff/card', FakeResponse.error(404, 'Not found'));
        expect(await repo.staffCard(), isNull);
        await expectLater(
          repo.staffCard(knownCardId: 'c1'),
          throwsA(isA<AppException>()),
        );
      },
    );

    test('updateStaffCard PATCHes /staff/card', () async {
      api.on('PATCH', '/staff/card', FakeResponse.ok(cardJson()));
      final card = await repo.updateStaffCard({'socialLinks': []});
      expect(card.id, 'c1');
      expect(api.requests.single.body, {'socialLinks': []});
    });
  });
}
