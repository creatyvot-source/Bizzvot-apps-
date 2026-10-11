import 'package:bizzvot/features/catalog/domain/catalog_models.dart';
import 'package:bizzvot/features/catalog/domain/commerce_models.dart';
import 'package:bizzvot/features/catalog/domain/physical_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validators', () {
    test('PIN code is 6 digits not starting with 0', () {
      expect(ShippingValidators.pinCode('673001'), isNull);
      expect(ShippingValidators.pinCode('073001'), isNotNull);
      expect(ShippingValidators.pinCode('67300'), isNotNull);
      expect(ShippingValidators.pinCode(''), isNotNull);
    });

    test('mobile', () {
      expect(ShippingValidators.mobile('9876543210'), isNull);
      expect(ShippingValidators.mobile('+91 98765-43210'), isNull);
      expect(ShippingValidators.mobile('12345'), isNotNull);
    });

    test('GSTIN optional but validated', () {
      expect(ShippingValidators.optionalGstin(''), isNull);
      expect(ShippingValidators.optionalGstin('32AAACB1234C1Z5'), isNull);
      expect(ShippingValidators.optionalGstin('32aaacb1234c1z5'), isNull);
      expect(ShippingValidators.optionalGstin('INVALID'), isNotNull);
    });

    test('review url must be https', () {
      expect(ShippingValidators.reviewUrl('https://g.page/r/abc/review'), isNull);
      expect(ShippingValidators.reviewUrl('http://g.page/r/abc'), isNotNull);
      expect(ShippingValidators.reviewUrl('javascript:x'), isNotNull);
    });
  });

  test('ShippingAddress round trip', () {
    const a = ShippingAddress(
      name: 'Asha',
      phone: '9876543210',
      line1: '12 MG Road',
      city: 'Kozhikode',
      state: 'Kerala',
      pinCode: '673001',
    );
    expect(a.isValid, isTrue);
    final b = ShippingAddress.tryParse(a.toJson())!;
    expect(b.dedupeKey, a.dedupeKey);
    expect(b.country, 'IN');
  });

  group('LinePersonalization', () {
    const spec = PersonalizationSpec(target: NfcTarget.card, perUnit: true, printName: true);

    test('per-unit entries track quantity', () {
      final p = const LinePersonalization(spec: spec).resized(3);
      expect(p.units, hasLength(3));
      expect(p.resized(1).units, hasLength(1));
    });

    test('problems until every unit is linked, unless assign later', () {
      var p = const LinePersonalization(spec: spec).resized(2);
      expect(p.problem(2), contains('Unit 1'));
      p = p.copyWith(units: const [
        UnitPersonalization(cardId: 'c1', printName: 'A'),
        UnitPersonalization(cardId: 'c2', printName: 'B'),
      ]);
      expect(p.problem(2), isNull);
      expect(const LinePersonalization(spec: spec, assignLater: true).problem(10), isNull);
      expect(p.toJson()['units'], hasLength(2));
      expect((p.toJson()['units'] as List).first, containsPair('nfcTarget', 'card'));
    });

    test('review target accepts https link or card review page', () {
      const review = PersonalizationSpec(target: NfcTarget.review);
      expect(const UnitPersonalization(reviewUrl: 'http://x.y').problem(review), isNotNull);
      expect(const UnitPersonalization(reviewUrl: 'https://g.page/r/1').problem(review), isNull);
      expect(const UnitPersonalization(useCardReviewPage: true).problem(review), isNotNull);
      expect(
        const UnitPersonalization(useCardReviewPage: true, cardId: 'c1').toJson(NfcTarget.review),
        containsPair('reviewTarget', 'review_card'),
      );
    });

    test('CartLine copyWith resizes personalisation', () {
      final line = CartLine(
        itemType: CatalogItemType.product,
        itemId: 'p-staff-id',
        quantity: 2,
        titleSnapshot: 'Staff ID',
        lineId: 'l1',
        personalization: const LinePersonalization(spec: spec).resized(2),
      );
      expect(line.copyWith(quantity: 5).personalization!.units, hasLength(5));
      expect(line.key, endsWith('|l1'));
      expect(line.toRequestJson()['personalization'], isA<Map<String, dynamic>>());
    });
  });

  group('Fulfilment', () {
    test('timeline with shipment tracking', () {
      final o = Order.fromJson({
        '_id': 'o1',
        'status': 'processing',
        'paymentStatus': 'paid',
        'fulfilment': {
          'status': 'shipped',
          'timeline': [
            {'step': 'placed', 'at': '2026-10-01T10:00:00Z'},
            {'step': 'paid', 'at': '2026-10-01T10:05:00Z'},
            {'step': 'design_proof'},
            {'step': 'printing'},
            {'step': 'nfc_programmed'},
            {'step': 'shipped', 'at': '2026-10-04T09:00:00Z'},
          ],
          'shipment': {'courier': 'BlueDart', 'awb': '123456', 'trackingUrl': 'https://track.test/123456'},
        },
        'shippingAddress': {'name': 'Asha', 'line1': '12 MG Road', 'city': 'Kozhikode', 'state': 'Kerala', 'pinCode': '673001', 'phone': '9876543210'},
        'gst': {'gstin': '32AAACB1234C1Z5', 'placeOfSupply': 'Kerala'},
      });
      final f = o.fulfilment!;
      expect(f.current, FulfilmentStep.shipped);
      expect(f.isReached(FulfilmentStep.printing), isTrue);
      expect(f.isReached(FulfilmentStep.delivered), isFalse);
      expect(f.safeTrackingUri.toString(), 'https://track.test/123456');
      expect(f.courier, 'BlueDart');
      expect(o.shippingAddress!.city, 'Kozhikode');
      expect(o.gst!.placeOfSupply, 'Kerala');
    });

    test('non-https tracking link is ignored', () {
      final f = Fulfilment.tryParse({
        'fulfilment': {'status': 'shipped', 'trackingUrl': 'http://track.test/1'},
      })!;
      expect(f.safeTrackingUri, isNull);
    });

    test('absent fulfilment is null', () {
      expect(Fulfilment.tryParse({'_id': 'o'}), isNull);
    });
  });
}
