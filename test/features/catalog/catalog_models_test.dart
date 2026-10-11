import 'package:bizzvot/features/catalog/domain/catalog_models.dart';
import 'package:bizzvot/features/catalog/domain/commerce_models.dart';
import 'package:bizzvot/features/catalog/domain/money.dart';
import 'package:bizzvot/features/catalog/domain/physical_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'commerce_test_utils.dart';

void main() {
  group('CatalogItem', () {
    test('parses NFC physical products from server fixtures', () {
      final items = nfcProducts.map((p) => CatalogItem.fromJson(p, type: CatalogItemType.product)).toList();
      expect(items.map((i) => i.price), [
        const Money(49900, 'INR'),
        const Money(35000, 'INR'),
        const Money(35000, 'INR'),
        const Money(99900, 'INR'),
      ]);
      for (final i in items) {
        expect(i.paymentPolicy, PaymentPolicy.physical);
        expect(i.policyDeclared, isTrue);
        expect(i.requiresShipping, isTrue);
        expect(i.purchasable, isTrue);
      }
      expect(items[0].personalization.target, NfcTarget.review);
      expect(items[2].personalization.perUnit, isTrue);
      expect(items[2].personalization.printName, isTrue);
    });

    test('defaults when fields missing and contact-only without price', () {
      final i = CatalogItem.fromJson({'id': 's1', 'name': 'Website design', 'type': 'service'});
      expect(i.type, CatalogItemType.service);
      expect(i.contactOnly, isTrue);
      expect(i.purchasable, isFalse);
      expect(i.paymentPolicy, PaymentPolicy.inPersonService);
      expect(i.policyDeclared, isFalse);
      expect(i.requiresShipping, isFalse);
    });

    test('in-app digital items block checkout', () {
      final i = CatalogItem.fromJson({
        'id': 'd1',
        'title': 'Premium theme',
        'price': '99',
        'currency': 'INR',
        'paymentPolicy': 'in_app_digital',
      });
      expect(i.paymentPolicy.blocksCheckout, isTrue);
      expect(i.purchasable, isFalse);
    });

    test('rejects unsafe image urls and parses rich detail', () {
      final i = CatalogItem.fromJson({
        '_id': 'x',
        'title': 'Stand',
        'images': ['javascript:alert(1)', 'https://cdn.test/a.png', {'url': 'https://cdn.test/b.png'}],
        'variants': [
          {'_id': 'v1', 'name': 'Black', 'inventoryStatus': 'out_of_stock'},
          {'_id': 'v2', 'name': 'White'},
        ],
        'faq': [{'question': 'Q?', 'answer': 'A.'}, {'question': 'no answer'}],
        'status': 'inactive',
      });
      expect(i.images, ['https://cdn.test/a.png', 'https://cdn.test/b.png']);
      expect(i.variants.first.available, isFalse);
      expect(i.variants.last.available, isTrue);
      expect(i.faq, hasLength(1));
      expect(i.active, isFalse);
    });
  });

  test('Plan parses price per seat and limits', () {
    final p = Plan.fromJson({
      '_id': 'pro',
      'name': 'Pro',
      'pricePerSeatMinor': 19900,
      'currency': 'INR',
      'billingPeriod': 'monthly',
      'limits': {'cards': 10},
      'features': ['Analytics', {'title': 'Reviews'}],
    });
    expect(p.price, const Money(19900, 'INR'));
    expect(p.limits, {'cards': '10'});
    expect(p.features, ['Analytics', 'Reviews']);
  });

  group('status parsing', () {
    test('unknown statuses are preserved', () {
      final o = Order.fromJson({'_id': 'o1', 'status': 'on_hold_review', 'paymentStatus': 'weird'});
      expect(o.status, OrderStatus.unknown);
      expect(o.statusLabel, 'On hold review');
      expect(o.paymentStatus, PaymentStatus.unknown);
      expect(o.paymentOutcome, PaymentOutcome.pending);
      expect(o.paymentOutcome.isTerminal, isFalse);
    });

    test('payment outcome derived from server fields only', () {
      PaymentOutcome out(Map<String, Object?> j) => Order.fromJson({'_id': 'o', ...j}).paymentOutcome;
      expect(out({'status': 'pending_payment'}), PaymentOutcome.pending);
      expect(out({'status': 'processing', 'paymentStatus': 'captured'}), PaymentOutcome.paid);
      expect(out({'status': 'processing'}), PaymentOutcome.processing);
      expect(out({'status': 'payment_failed'}), PaymentOutcome.failed);
      expect(out({'status': 'cancelled'}), PaymentOutcome.cancelled);
      expect(out({'status': 'expired'}), PaymentOutcome.expired);
      expect(out({'paymentStatus': 'refunded'}), PaymentOutcome.refunded);
      expect(out({'payment': {'status': 'succeeded'}}), PaymentOutcome.paid);
    });

    test('subscription statuses', () {
      expect(SubscriptionStatus.parse('past_due'), SubscriptionStatus.pastDue);
      expect(SubscriptionStatus.parse('grace'), SubscriptionStatus.gracePeriod);
      expect(SubscriptionStatus.parse('canceled'), SubscriptionStatus.cancelled);
      expect(SubscriptionStatus.parse('zzz'), SubscriptionStatus.unknown);
    });
  });

  group('Quote', () {
    test('itemised server totals and invalid lines', () {
      final q = Quote.fromJson({
        'quoteId': 'q1',
        'currency': 'INR',
        'lines': [
          {'itemType': 'product', 'itemId': 'p-stand', 'title': 'Stand', 'quantity': 2, 'unitPrice': '499', 'lineTotal': '998'},
          {'itemType': 'product', 'itemId': 'gone', 'title': 'Old', 'quantity': 1, 'available': false, 'issue': 'Discontinued'},
        ],
        'discounts': [{'label': 'WELCOME10', 'amount': '99.80'}],
        'taxes': [{'label': 'GST', 'rate': 18, 'amount': '161.68'}],
        'totals': {'subtotal': '998', 'shipping': '60', 'total': '1119.88'},
      });
      expect(q.id, 'q1');
      expect(q.lines.first.lineTotal, const Money(99800, 'INR'));
      expect(q.discounts.single.amount, const Money(9980, 'INR'));
      expect(q.taxes.single.rate, '18%');
      expect(q.shipping, const Money(6000, 'INR'));
      expect(q.total, const Money(111988, 'INR'));
      expect(q.hasUnavailable, isTrue);
      expect(q.canCheckout, isFalse);
    });

    test('cannot checkout without a server total', () {
      final q = Quote.fromJson({'lines': [{'itemId': 'a', 'title': 'A'}]});
      expect(q.canCheckout, isFalse);
    });
  });

  group('PaymentSession', () {
    test('accepts https checkout urls only', () {
      expect(PaymentSession.fromJson({'checkoutUrl': 'https://rzp.io/i/abc'}).safeCheckoutUri, isNotNull);
      expect(PaymentSession.fromJson({'paymentUrl': 'http://rzp.io/i/abc'}).safeCheckoutUri, isNull);
      expect(PaymentSession.fromJson({'shortUrl': 'javascript:alert(1)'}).safeCheckoutUri, isNull);
      expect(
        PaymentSession.fromJson({'payment': {'shortUrl': 'https://rzp.io/x'}, 'orderId': 'o1'}).safeCheckoutUri.toString(),
        'https://rzp.io/x',
      );
    });
  });

  test('CartLine request JSON carries no amounts or titles', () {
    const line = CartLine(
      itemType: CatalogItemType.product,
      itemId: 'p-stand',
      quantity: 2,
      titleSnapshot: 'Stand',
      variantId: 'v1',
    );
    final j = line.toRequestJson();
    expect(j, {'itemType': 'product', 'itemId': 'p-stand', 'variantId': 'v1', 'quantity': 2});
  });
}
