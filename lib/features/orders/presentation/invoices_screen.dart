import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../shared/widgets/state_views.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/formatting.dart';
import '../../catalog/presentation/common/commerce_widgets.dart';
import '../../catalog/presentation/common/paged_list.dart';
import 'orders_providers.dart';

StatusTone toneForInvoice(Invoice i) => switch (wireKey(i.status)) {
  'paid' => StatusTone.success,
  'void' || 'voided' || 'cancelled' || 'canceled' => StatusTone.neutral,
  'overdue' || 'failed' => StatusTone.danger,
  'refunded' || 'credited' => StatusTone.neutral,
  _ => StatusTone.info,
};

class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(invoicesListProvider);
    final notifier = ref.read(invoicesListProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      body: ContentWidth(
        child: PagedListView<Invoice>(
          value: value,
          onRefresh: notifier.refresh,
          onLoadMore: notifier.loadMore,
          empty: const EmptyView(
            icon: Icons.description_outlined,
            title: 'No invoices yet',
            message: 'Invoices and receipts for paid orders and renewals appear here.',
          ),
          itemBuilder: (context, inv) => ListTile(
            onTap: () => context.push(Routes.ownerInvoice(inv.id)),
            leading: const Icon(Icons.description_outlined),
            title: Text('Invoice ${inv.displayNumber}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatDate(inv.issuedAt)),
                const SizedBox(height: 4),
                StatusChip(inv.statusLabel, tone: toneForInvoice(inv)),
              ],
            ),
            trailing: MoneyText(
              inv.total,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
      ),
    );
  }
}
