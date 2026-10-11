import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../shared/models/paged.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/presentation/common/paged_list.dart';
import '../data/orders_repository.dart';

/// Paginated orders, filtered by status (null = all).
class OrdersListController extends PagedNotifier<Order> {
  OrdersListController(this.status);

  final OrderStatus? status;

  @override
  Future<Paged<Order>> fetchPage(int page) =>
      ref.read(ordersRepositoryProvider).orders(status: status, page: page);
}

final ordersListProvider = AsyncNotifierProvider.autoDispose
    .family<OrdersListController, PagedList<Order>, OrderStatus?>(
      OrdersListController.new,
    );

final orderDetailProvider = FutureProvider.autoDispose.family<Order, String>((
  ref,
  id,
) {
  ref.watch(sessionKeyProvider);
  return ref.watch(ordersRepositoryProvider).order(id);
});

class InvoicesListController extends PagedNotifier<Invoice> {
  @override
  Future<Paged<Invoice>> fetchPage(int page) =>
      ref.read(ordersRepositoryProvider).invoices(page: page);
}

final invoicesListProvider =
    AsyncNotifierProvider.autoDispose<
      InvoicesListController,
      PagedList<Invoice>
    >(InvoicesListController.new);

final invoiceDetailProvider = FutureProvider.autoDispose
    .family<Invoice, String>((ref, id) {
      ref.watch(sessionKeyProvider);
      return ref.watch(ordersRepositoryProvider).invoice(id);
    });

/// Invalidates cached order/invoice data after a payment state change.
void invalidateOrderCaches(Ref ref, {String? orderId}) {
  ref.invalidate(ordersListProvider);
  ref.invalidate(invoicesListProvider);
  if (orderId != null) ref.invalidate(orderDetailProvider(orderId));
}
