import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/providers.dart';
import '../../../shared/models/paged.dart';
import '../../catalog/domain/commerce_models.dart';

/// PROPOSED order and invoice endpoints (plan §12.4–12.5).
class OrdersRepository {
  OrdersRepository(this._api);

  final ApiClient _api;

  static const pageSize = 20;

  /// `GET /orders?status=&page=&limit=`.
  Future<Paged<Order>> orders({OrderStatus? status, int page = 1}) => _api.get(
        Endpoints.orders,
        query: {
          'status': status?.wire,
          'page': page,
          'limit': pageSize,
        },
        parse: (d) => Paged.parse(d, Order.fromJson,
            listKeys: const ['orders', 'items', 'docs', 'results', 'data']),
      );

  /// `GET /orders/:id` — authoritative order + payment state.
  Future<Order> order(String id) =>
      _api.get(Endpoints.order(id), parse: Order.fromJson);

  /// `GET /invoices?page=&limit=`.
  Future<Paged<Invoice>> invoices({int page = 1}) => _api.get(
        Endpoints.invoices,
        query: {'page': page, 'limit': pageSize},
        parse: (d) => Paged.parse(d, Invoice.fromJson,
            listKeys: const ['invoices', 'items', 'docs', 'results', 'data']),
      );

  /// `GET /invoices/:id`.
  Future<Invoice> invoice(String id) =>
      _api.get(Endpoints.invoice(id), parse: Invoice.fromJson);
}

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(ref.watch(apiClientProvider)),
);
