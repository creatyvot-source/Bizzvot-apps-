import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/state_views.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/presentation/common/paged_list.dart';
import 'orders_providers.dart';
import 'widgets/order_widgets.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  OrderStatus? _status;

  static const _filters = <(OrderStatus?, String)>[
    (null, 'All'),
    (OrderStatus.pendingPayment, 'Awaiting payment'),
    (OrderStatus.paid, 'Paid'),
    (OrderStatus.processing, 'Processing'),
    (OrderStatus.completed, 'Completed'),
    (OrderStatus.paymentFailed, 'Failed'),
    (OrderStatus.cancelled, 'Cancelled'),
    (OrderStatus.refunded, 'Refunded'),
  ];

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(ordersListProvider(_status));
    final notifier = ref.read(ordersListProvider(_status).notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        actions: [
          IconButton(
            tooltip: 'Invoices',
            icon: const Icon(Icons.description_outlined),
            onPressed: () => context.push(Routes.ownerInvoices),
          ),
        ],
      ),
      body: ContentWidth(
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  for (final (status, label) in _filters) ...[
                    ChoiceChip(
                      label: Text(label),
                      selected: _status == status,
                      onSelected: (_) => setState(() => _status = status),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                ],
              ),
            ),
            Expanded(
              child: PagedListView<Order>(
                value: value,
                onRefresh: notifier.refresh,
                onLoadMore: notifier.loadMore,
                empty: EmptyView(
                  icon: Icons.receipt_long_outlined,
                  title: _status == null ? 'No orders yet' : 'No orders with this status',
                  message: _status == null ? 'Orders you place in the shop appear here.' : null,
                  action: _status == null
                      ? FilledButton(
                          onPressed: () => context.push(Routes.ownerShop),
                          child: const Text('Browse shop'),
                        )
                      : null,
                ),
                itemBuilder: (context, o) => OrderTile(
                  order: o,
                  onTap: () => context.push(Routes.ownerOrder(o.id)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
