import 'dart:typed_data';

import 'package:bizzvot/features/cards/domain/card_filters.dart';
import 'package:bizzvot/features/cards/domain/media_rules.dart';
import 'package:bizzvot/features/cards/domain/qr_codes.dart';
import 'package:bizzvot/shared/models/card.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cards_test_harness.dart';

void main() {
  group('limits', () {
    test('remaining slots clamp at zero', () {
      expect(MediaRules.remaining(3, CardLimits.gallery), 2);
      expect(MediaRules.remaining(5, CardLimits.gallery), 0);
      expect(MediaRules.remaining(7, CardLimits.gallery), 0);
    });

    test('per-kind limits follow the spec (5 / 10 / 5)', () {
      final card = CardModel.fromJson(cardJson(extra: {
        'gallery': List.generate(5, (i) => 'https://cdn/g$i.png'),
        'pdfs': List.generate(4, (i) => {'url': 'https://cdn/d$i.pdf'}),
        'videos': ['https://youtu.be/dQw4w9WgXcQ'],
      }));
      expect(MediaRules.remainingGallery(card), 0);
      expect(MediaRules.remainingPdfs(card), 6);
      expect(MediaRules.remainingVideos(card), 4);
    });
  });

  group('file validation', () {
    test('sniffs real types from signatures', () {
      expect(MediaRules.sniffMime(tinyPng), 'image/png');
      expect(MediaRules.sniffMime(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), 'image/jpeg');
      expect(MediaRules.sniffMime(tinyPdf), 'application/pdf');
      expect(MediaRules.sniffMime(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('images: type and 5 MB size', () {
      expect(MediaRules.validateImage(tinyPng), isNull);
      expect(MediaRules.validateImage(tinyPdf), isNotNull);
      final big = Uint8List(MediaRules.maxImageBytes + 1)..setAll(0, tinyPng);
      expect(MediaRules.validateImage(big), contains('5 MB'));
      expect(MediaRules.validateImage(Uint8List(0)), isNotNull);
    });

    test('pdfs: signature required', () {
      expect(MediaRules.validatePdf(tinyPdf), isNull);
      expect(MediaRules.validatePdf(tinyPng), isNotNull);
    });
  });

  group('YouTube', () {
    test('accepts common https forms', () {
      for (final url in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=10',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
        'https://www.youtube.com/embed/dQw4w9WgXcQ',
      ]) {
        expect(MediaRules.youtubeId(url), 'dQw4w9WgXcQ', reason: url);
      }
    });

    test('rejects http, other hosts and bad ids', () {
      expect(MediaRules.youtubeId('http://youtu.be/dQw4w9WgXcQ'), isNull);
      expect(MediaRules.youtubeId('https://vimeo.com/123'), isNull);
      expect(MediaRules.youtubeId('https://youtube.com.evil.com/watch?v=dQw4w9WgXcQ'), isNull);
      expect(MediaRules.youtubeId('https://youtu.be/short'), isNull);
      expect(MediaRules.validateYoutube(''), isNotNull);
    });
  });

  test('links must be https', () {
    expect(MediaRules.validateHttpsLink('https://example.com'), isNull);
    expect(MediaRules.validateHttpsLink('http://example.com'), isNotNull);
    expect(MediaRules.validateHttpsLink('javascript:alert(1)'), isNotNull);
    expect(MediaRules.optionalHttpsLink(''), isNull);
  });

  group('list filtering', () {
    final cards = [
      CardModel.fromJson(cardJson(id: 'a')),
      CardModel.fromJson(cardJson(id: 'b', status: 'disabled', extra: {'title': 'Bo Chen'})),
      CardModel.fromJson(cardJson(id: 'c', status: 'disabled', disabledByBilling: true, extra: {'title': 'Cy'})),
    ];

    test('status filter distinguishes billing-disabled cards', () {
      expect(filterCards(cards, status: CardStatusFilter.active).map((c) => c.id), ['a']);
      expect(filterCards(cards, status: CardStatusFilter.disabled).map((c) => c.id), ['b']);
      expect(filterCards(cards, status: CardStatusFilter.disabledByBilling).map((c) => c.id), ['c']);
    });

    test('search is case-insensitive across fields', () {
      expect(filterCards(cards, query: 'bo ch').map((c) => c.id), ['b']);
      expect(filterCards(cards, query: 'SALES'), hasLength(3));
    });

    test('labels', () {
      expect(cardStatusLabel(cards[2]), 'Disabled by billing');
      expect(cardVisibilityShortLabel(CardVisibility.inherit), 'Inherit');
    });
  });

  test('data URLs and file stems', () {
    expect(decodeDataUrl(tinyPngDataUrl), tinyPng);
    expect(decodeDataUrl('data:image/png,notbase64'), isNull);
    expect(safeFileStem('Asha Rao / Sales!'), 'asha-rao-sales');
    expect(safeFileStem('***'), 'card');
  });
}
