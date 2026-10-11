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
    test('parses the paginated envelope and requests limit=100', () async {
      api.on('GET', '/organization/cards',
          FakeResponse.ok(cardsPage([cardJson(), cardJson(id: 'c2')])));
      final cards = await repo.listCards();
      expect(cards.map((c) => c.id), ['c1', 'c2']);
      expect(cards.first.company, 'Acme');
      expect(cards.first.template, CardTemplate.corporate);
      expect(api.requests.single.query, {'page': 1, 'limit': 100});
    });

    test('follows hasMore across pages', () async {
      api.onDynamic('GET', '/organization/cards', (req) {
        final page = req.query['page'];
        return FakeResponse.ok(page == 1
            ? cardsPage([cardJson(id: 'a')], hasMore: true)
            : cardsPage([cardJson(id: 'b')]));
      });
      expect((await repo.listCards()).map((c) => c.id), ['a', 'b']);
      expect(api.requests, hasLength(2));
    });

    test('tolerates a bare array and drops rows without id', () async {
      api.on('GET', '/organization/cards', FakeResponse.ok([
        cardJson(),
        {'title': 'no id'},
      ]));
      expect(await repo.listCards(), hasLength(1));
    });
  });

  test('getCard unwraps {card: ...}', () async {
    api.on('GET', '/organization/cards/c1', FakeResponse.ok({'card': cardJson()}));
    final card = await repo.getCard('c1');
    expect(card.id, 'c1');
    expect(card.brandColor, '#1F4FD8');
  });

  test('createCard POSTs title/designation and parses the card', () async {
    api.on('POST', '/organization/cards', FakeResponse(201, {'success': true, 'data': cardJson(id: 'new')}));
    final card = await repo.createCard(title: ' Asha ', designation: 'Lead');
    expect(card.id, 'new');
    expect(api.requests.single.body, {'title': 'Asha', 'designation': 'Lead'});
  });

  test('createCard surfaces the plan limit as forbidden', () async {
    api.on('POST', '/organization/cards',
        const FakeResponse(403, {'success': false, 'error': 'Card limit reached: max 3 card(s)'}));
    await expectLater(
      repo.createCard(title: 'X'),
      throwsA(isA<AppException>()
          .having((e) => e.kind, 'kind', AppErrorKind.forbidden)
          .having((e) => e.message, 'message', contains('Card limit reached'))),
    );
  });

  test('updateCard sends the body and re-fetches when not echoed', () async {
    api.on('PATCH', '/organization/cards/c1', FakeResponse.ok(null));
    api.on('GET', '/organization/cards/c1', FakeResponse.ok(cardJson()));
    final card = await repo.updateCard('c1', {'title': 'New'});
    expect(card.id, 'c1');
    expect(api.requests.firstWhere((r) => r.method == 'PATCH').body, {'title': 'New'});
  });

  test('setStatus is a per-card PATCH {status}', () async {
    api.on('PATCH', '/organization/cards/c1', FakeResponse.ok(cardJson()));
    await repo.setStatus('c1', CardStatus.disabled);
    expect(api.requests.single.body, {'status': 'disabled'});
  });

  test('deleteCard calls DELETE', () async {
    api.on('DELETE', '/organization/cards/c1', FakeResponse.ok({'deleted': true}));
    await repo.deleteCard('c1');
    expect(api.requests.single.method, 'DELETE');
  });

  group('QR codes', () {
    test('qrCode POSTs and decodes data.qrCodeUrl', () async {
      api.on('POST', '/cards/c1/qrcode', FakeResponse.ok({
        'qrCodeUrl': tinyPngDataUrl,
        'publicUrl': 'https://www.bizzvot.com/card/asha-rao',
      }));
      expect(await repo.qrCode('c1'), tinyPng);
      expect(api.requests.single.method, 'POST');
    });

    test('QrCodeEntry treats a data URL in qrCodeUrl as inline data', () {
      final e = QrCodeEntry.fromJson({'cardId': 'c', 'qrCodeUrl': tinyPngDataUrl, 'publicUrl': 'https://x/card/s'});
      expect(e.dataUrl, tinyPngDataUrl);
      expect(e.url, isNull);
      expect(e.publicUrl, 'https://x/card/s');
    });

    test('staff without editCard get a 403', () async {
      api.on('POST', '/cards/c1/qrcode', const FakeResponse(403, {'success': false, 'error': 'Missing permission'}));
      await expectLater(
        repo.qrCode('c1'),
        throwsA(isA<AppException>().having((e) => e.kind, 'kind', AppErrorKind.forbidden)),
      );
    });

    test('qrEntryImage refuses non-https remote URLs', () async {
      const entry = QrCodeEntry(cardId: 'c', url: 'http://insecure.example.com/q.png');
      expect(await repo.qrEntryImage(entry), isNull);
    });
  });

  test('vcard returns the file and rejects non-vCard bodies', () async {
    final vcf = Uint8List.fromList(utf8.encode('BEGIN:VCARD\nVERSION:3.0\nEND:VCARD\n'));
    api.onBytes('GET', '/cards/c1/vcard', vcf);
    expect(await repo.vcard('c1'), vcf);

    api.on('GET', '/cards/c2/vcard', const FakeResponse(404, {'success': false, 'error': 'Not found'}));
    await expectLater(repo.vcard('c2'), throwsA(isA<AppException>()));
  });

  group('uploads', () {
    test('uploadImage posts multipart field "file" and parses data.url', () async {
      api.on('POST', '/media/upload',
          FakeResponse(201, {'success': true, 'data': {'url': 'https://cdn.example.com/a.png', 'filename': 'a.png'}}));
      final url = await repo.uploadImage(bytes: tinyPng, filename: 'a.png', mimeType: 'image/png');
      expect(url, 'https://cdn.example.com/a.png');
      final form = api.requests.single.body as FormData;
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'a.png');
    });

    test('quota exceeded (413) is surfaced', () async {
      api.on('POST', '/media/upload', const FakeResponse(413, {'success': false, 'error': 'Upload quota exceeded'}));
      await expectLater(
        repo.uploadImage(bytes: tinyPng, filename: 'a.png', mimeType: 'image/png'),
        throwsA(isA<AppException>().having((e) => e.message, 'message', 'Upload quota exceeded')),
      );
    });

    test('uploadedUrl handles many response shapes', () {
      expect(CardsRepository.uploadedUrl('https://a'), 'https://a');
      expect(CardsRepository.uploadedUrl({'secure_url': 'https://b'}), 'https://b');
      expect(CardsRepository.uploadedUrl({'media': {'url': 'https://c'}}), 'https://c');
      expect(CardsRepository.uploadedUrl({}), isNull);
    });
  });

  group('staff cards', () {
    test('GET /staff/cards array → preferred or first card', () async {
      api.on('GET', '/staff/cards', FakeResponse.ok([cardJson(id: 'a'), cardJson(id: 'b')]));
      expect((await repo.staffCard())?.id, 'a');
      expect((await repo.staffCard(preferredId: 'b'))?.id, 'b');
      expect((await repo.staffCard(preferredId: 'zzz'))?.id, 'a');
    });

    test('empty array means no card assigned', () async {
      api.on('GET', '/staff/cards', FakeResponse.ok([]));
      expect(await repo.staffCard(), isNull);
    });

    test('updateStaffCard PATCHes /staff/cards/:id', () async {
      api.on('PATCH', '/staff/cards/c1', FakeResponse.ok(cardJson()));
      final card = await repo.updateStaffCard('c1', {'designation': 'Lead'});
      expect(card.id, 'c1');
      expect(api.requests.single.body, {'designation': 'Lead'});
    });

    test('strict-schema 400 message is shown as-is', () async {
      api.on('PATCH', '/staff/cards/c1',
          const FakeResponse(400, {'success': false, 'error': "Unrecognized key(s) in object: 'company'"}));
      await expectLater(
        repo.updateStaffCard('c1', {'company': 'x'}),
        throwsA(isA<AppException>().having((e) => e.kind, 'kind', AppErrorKind.validation)),
      );
    });
  });
}
