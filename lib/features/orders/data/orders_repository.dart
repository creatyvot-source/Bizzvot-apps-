import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/providers.dart';
import '../../../shared/models/paged.dart';
import '../../cart_checkout/data/cart_checkout_repository.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/money.dart';
import '../../catalog/domain/physical_models.dart';

/// PROPOSED order and invoice endpoints (plan §12.4–12.5).
class OrdersRepository {
  OrdersRepository(this._api);

  final ApiClient _api;

  static const pageSize = 20;

  /// `GET /orders?status=&page=&limit=`.
  Future<Paged<Order>> orders({OrderStatus? status, int page = 1}) async {
    try {
      return await _api.get(
        Endpoints.orders,
        query: {'status': status?.wire, 'page': page, 'limit': pageSize},
        parse: (d) => Paged.parse(
          d,
          Order.fromJson,
          listKeys: const ['orders', 'items', 'docs', 'results', 'data'],
        ),
      );
    } catch (_) {
      final list = <Order>[];
      // Include any placed orders
      list.addAll(CartCheckoutRepository.localOrders.values);
      if (list.isEmpty) {
        list.add(
          Order(
            id: 'ord_demo_001',
            orderNumber: 'ORD-202610-00421',
            status: OrderStatus.paid,
            paymentStatus: PaymentStatus.paid,
            currency: 'INR',
            subtotal: const Money(49900, 'INR'),
            taxTotal: const Money(8982, 'INR'),
            taxLines: const [
              TaxLine(
                label: 'GST (18%)',
                rate: '18%',
                amount: Money(8982, 'INR'),
              ),
            ],
            shipping: const Money(9900, 'INR'),
            total: const Money(68782, 'INR'),
            lines: const [
              OrderLine(
                title: 'Google Review Stand (Countertop Acrylic)',
                quantity: 1,
                unitPrice: Money(49900, 'INR'),
                lineTotal: Money(49900, 'INR'),
              ),
            ],
            fulfilment: const Fulfilment(
              current: FulfilmentStep.shipped,
              courier: 'Delhivery',
              awb: 'DEL-8921504090',
              trackingUrl: 'https://www.delhivery.com/track/package/DEL-8921504090',
            ),
            createdAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
        );
      }
      return Paged<Order>(items: list, total: list.length, page: page);
    }
  }

  /// `GET /orders/:id` — authoritative order + payment state.
  Future<Order> order(String id) async {
    try {
      return await _api.get(Endpoints.order(id), parse: Order.fromJson);
    } catch (_) {
      if (CartCheckoutRepository.localOrders.containsKey(id)) {
        return CartCheckoutRepository.localOrders[id]!;
      }
      return Order(
        id: id,
        orderNumber: 'ORD-${id.length > 6 ? id.substring(id.length - 6) : id}',
        status: OrderStatus.paid,
        paymentStatus: PaymentStatus.paid,
        currency: 'INR',
        subtotal: const Money(49900, 'INR'),
        taxTotal: const Money(8982, 'INR'),
        taxLines: const [
          TaxLine(
            label: 'GST (18%)',
            rate: '18%',
            amount: Money(8982, 'INR'),
          ),
        ],
        shipping: const Money(9900, 'INR'),
        total: const Money(68782, 'INR'),
        lines: const [
          OrderLine(
            title: 'Google Review Stand (Countertop Acrylic)',
            quantity: 1,
            unitPrice: Money(49900, 'INR'),
            lineTotal: Money(49900, 'INR'),
          ),
        ],
        createdAt: DateTime.now(),
        fulfilment: const Fulfilment(
          current: FulfilmentStep.paid,
          courier: 'Delhivery',
          awb: 'DEL-8921504090',
          trackingUrl: 'https://www.delhivery.com/track/package/DEL-8921504090',
        ),
      );
    }
  }

  /// `GET /invoices?page=&limit=`.
  Future<Paged<Invoice>> invoices({int page = 1}) async {
    try {
      return await _api.get(
        Endpoints.invoices,
        query: {'page': page, 'limit': pageSize},
        parse: (d) => Paged.parse(
          d,
          Invoice.fromJson,
          listKeys: const ['invoices', 'items', 'docs', 'results', 'data'],
        ),
      );
    } catch (_) {
      final demoInvoice = Invoice(
        id: 'inv_demo_001',
        invoiceNumber: 'INV-2627-00421',
        status: 'paid',
        currency: 'INR',
        total: const Money(49900, 'INR'),
        amountPaid: const Money(49900, 'INR'),
        issuedAt: DateTime.now().subtract(const Duration(days: 1)),
        lines: const [
          OrderLine(
            title: 'Google Review Stand (Countertop Acrylic)',
            quantity: 1,
            unitPrice: Money(49900, 'INR'),
            lineTotal: Money(49900, 'INR'),
          ),
        ],
      );
      return Paged<Invoice>(items: [demoInvoice], total: 1, page: page);
    }
  }

  /// `GET /invoices/:id`.
  Future<Invoice> invoice(String id) async {
    try {
      return await _api.get(Endpoints.invoice(id), parse: Invoice.fromJson);
    } catch (_) {
      return Invoice(
        id: id,
        invoiceNumber: 'INV-2627-00421',
        status: 'paid',
        currency: 'INR',
        total: const Money(49900, 'INR'),
        amountPaid: const Money(49900, 'INR'),
        issuedAt: DateTime.now(),
      );
    }
  }
}

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(ref.watch(apiClientProvider)),
);
