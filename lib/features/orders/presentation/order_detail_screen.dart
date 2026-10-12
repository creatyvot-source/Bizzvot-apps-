import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/state_views.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/formatting.dart';
import '../../catalog/presentation/common/commerce_widgets.dart';
import 'orders_providers.dart';
import 'widgets/order_widgets.dart';

/// Immutable server snapshot of an order: items, prices, tax, payment,
/// fulfilment (with shipment tracking), refund and linked subscription.
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(orderDetailProvider(orderId));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          value.value == null
              ? 'Order'
              : 'Order #${value.value!.displayNumber}',
        ),
      ),
      body: AsyncValueView(
        value: value,
        onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
        data: (o) => RefreshIndicator(
          onRefresh: () => ref.refresh(orderDetailProvider(orderId).future),
          child: ContentWidth(child: _OrderBody(order: o)),
        ),
      ),
    );
  }
}

class _OrderBody extends StatelessWidget {
  const _OrderBody({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = order;
    final outcome = o.paymentOutcome;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppSpacing.page,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            StatusChip(o.statusLabel, tone: toneForOrder(o)),
            StatusChip(
              'Payment: ${o.paymentStatusLabel}',
              tone: toneForOutcome(outcome),
            ),
            if (o.refundStatus != null)
              StatusChip(
                'Refund: ${humanize(o.refundStatus)}',
                tone: StatusTone.neutral,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Placed ${formatDateTime(o.createdAt)}',
          style: theme.textTheme.bodySmall,
        ),
        if (outcome == PaymentOutcome.pending ||
            outcome == PaymentOutcome.failed) ...[
          const SizedBox(height: AppSpacing.md),
          NoticeCard(
            title: outcome == PaymentOutcome.failed
                ? 'Payment failed'
                : 'Payment not completed',
            message: o.failureReason ?? 'This order is waiting for payment. It will be processed once the payment is confirmed.',
            tone: outcome == PaymentOutcome.failed
                ? StatusTone.danger
                : StatusTone.warning,
            action: o.retryPaymentAllowed
                ? FilledButton(
                    onPressed: () => context.push(Routes.ownerPayment(o.id)),
                    child: const Text('Complete payment'),
                  )
                : null,
          ),
        ],
        if (o.fulfilment != null || o.shippingAddress != null) ...[
          const SectionHeader('Delivery'),
          Card(
            child: Padding(
              padding: AppSpacing.page,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (o.fulfilment != null)
                    FulfilmentTimeline(
                      fulfilment: o.fulfilment!,
                      paid: outcome == PaymentOutcome.paid,
                      placedAt: o.createdAt,
                    ),
                  if (o.shippingAddress != null) ...[
                    if (o.fulfilment != null)
                      const Divider(height: AppSpacing.lg),
                    Text('Ship to', style: theme.textTheme.labelLarge),
                    const SizedBox(height: AppSpacing.xs),
                    Text(o.shippingAddress!.name),
                    Text(o.shippingAddress!.singleLine),
                  ],
                ],
              ),
            ),
          ),
        ] else if (o.fulfilmentStatus != null) ...[
          const SizedBox(height: AppSpacing.md),
          InfoRow.text('Fulfilment', humanize(o.fulfilmentStatus)),
        ],
        const SectionHeader('Items'),
        Card(
          child: Padding(
            padding: AppSpacing.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (o.lines.isEmpty)
                  Text(
                    'Item details are not available.',
                    style: theme.textTheme.bodyMedium,
                  ),
                for (final l in o.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InfoRow(
                          label:
                              '${l.title}${l.variantLabel == null ? '' : ' · ${l.variantLabel}'} × ${l.quantity}',
                          value: MoneyText(l.lineTotal),
                        ),
                        if (l.unitPrice != null)
                          Text(
                            '${l.unitPrice!.format()} each',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                const Divider(height: AppSpacing.lg),
                if (o.subtotal != null) InfoRow.money('Subtotal', o.subtotal),
                if (o.discountTotal != null && !o.discountTotal!.isZero)
                  InfoRow.money('Discount', o.discountTotal, negative: true),
                if (o.shipping != null) InfoRow.money('Courier & Delivery', o.shipping),
                for (final t in o.taxLines)
                  InfoRow.money(
                    t.rate == null ? t.label : '${t.label} (${t.rate})',
                    t.amount,
                  ),
                if (o.taxLines.isEmpty && o.taxTotal != null)
                  InfoRow.money('GST (18%)', o.taxTotal),
                InfoRow.money('Total', o.total, emphasize: true),
                if (o.refundedAmount != null)
                  InfoRow.money('Refunded', o.refundedAmount),
              ],
            ),
          ),
        ),
        if (o.gst != null) ...[
          const SectionHeader('GST details'),
          Card(
            child: Padding(
              padding: AppSpacing.page,
              child: Column(
                children: [
                  if (o.gst!.gstin != null)
                    InfoRow.text('GSTIN', o.gst!.gstin!),
                  if (o.gst!.businessName != null)
                    InfoRow.text('Business', o.gst!.businessName!),
                  if (o.gst!.placeOfSupply != null)
                    InfoRow.text('Place of supply', o.gst!.placeOfSupply!),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (o.invoiceId != null)
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.ownerInvoice(o.invoiceId!)),
            icon: const Icon(Icons.description_outlined),
            label: const Text('View invoice'),
          ),
        if (o.subscriptionId != null) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () =>
                context.push(Routes.ownerSubscription(o.subscriptionId!)),
            icon: const Icon(Icons.autorenew),
            label: const Text('View linked subscription'),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'Prices and taxes are a snapshot from when the order was placed.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
