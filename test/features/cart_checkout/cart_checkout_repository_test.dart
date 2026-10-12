import 'package:flutter_test/flutter_test.dart';
import 'package:bizzvot/core/api/api_client.dart';
import 'package:bizzvot/features/cart_checkout/data/cart_checkout_repository.dart';
import 'package:bizzvot/features/catalog/domain/catalog_models.dart';
import 'package:bizzvot/features/catalog/domain/commerce_models.dart';
import 'package:bizzvot/features/catalog/domain/physical_models.dart';
import 'package:dio/dio.dart';

void main() {
  group('CartCheckoutRepository', () {
    late CartCheckoutRepository repo;

    setUp(() {
      final dio = Dio(BaseOptions(baseUrl: 'https://test.bizzvot.com/api/v1'));
      final client = ApiClient(dio);
      repo = CartCheckoutRepository(client);
    });

    test('quote falls back to accurate local repricing when offline', () async {
      final lines = [
        const CartLine(
          itemType: CatalogItemType.product,
          itemId: 'stand-acrylic',
          variantId: '3-pack',
          quantity: 1,
          titleSnapshot: 'Google Review Stand',
        ),
        const CartLine(
          itemType: CatalogItemType.product,
          itemId: 'card-pvc-review',
          variantId: 'single',
          quantity: 2,
          titleSnapshot: 'Google Review Card',
        ),
      ];

      final quote = await repo.quote(lines);

      expect(quote.currency, 'INR');
      expect(quote.lines.length, 2);
      expect(quote.subtotal?.minor, 179900);
      expect(quote.taxTotal?.minor, 32382);
      expect(quote.shipping?.minor, 9900);
      expect(quote.total?.minor, 222182);
    });

    test('createOrder falls back to offline simulated order with valid lines', () async {
      final lines = [
        const CartLine(
          itemType: CatalogItemType.product,
          itemId: 'stand-acrylic',
          variantId: 'single',
          quantity: 1,
          titleSnapshot: 'Google Review Stand',
        ),
      ];

      final order = await repo.createOrder(
        lines: lines,
        idempotencyKey: 'test-idemp-123',
        shippingAddress: const ShippingAddress(
          name: 'Muhammed KC',
          phone: '+918921504090',
          line1: 'Bizzvot HQ',
          city: 'Calicut',
          state: 'Kerala',
          pinCode: '673001',
        ),
      );

      expect(order.id, startsWith('ord_'));
      expect(order.orderNumber, startsWith('ORD-'));
      expect(order.subtotal?.minor, 49900);
      expect(order.taxTotal?.minor, 8982);
      expect(order.shipping?.minor, 9900);
      expect(order.total?.minor, 68782);
      expect(order.lines.length, 1);
      expect(order.lines.first.quantity, 1);
      expect(order.fulfilment?.courier, 'Delhivery');
    });

    test('startPayment generates payment attempt with checkoutUrl', () async {
      final session = await repo.startPayment(
        'ord_12345',
        idempotencyKey: 'test-idemp-pay',
      );

      expect(session.orderId, 'ord_12345');
      expect(session.checkoutUrl, isNotNull);
      expect(session.safeCheckoutUri, isNotNull);
    });

    test('order returns saved local order details', () async {
      final lines = [
        const CartLine(
          itemType: CatalogItemType.product,
          itemId: 'card-business-nfc',
          variantId: 'single',
          quantity: 1,
          titleSnapshot: 'Business Digital Card',
        ),
      ];

      final created = await repo.createOrder(
        lines: lines,
        idempotencyKey: 'test-idemp-fetch',
      );

      final fetched = await repo.order(created.id);

      expect(fetched.id, created.id);
      expect(fetched.subtotal?.minor, 99900);
      expect(fetched.total?.minor, 127782);
      expect(fetched.paymentOutcome, PaymentOutcome.paid);
    });
  });
}
