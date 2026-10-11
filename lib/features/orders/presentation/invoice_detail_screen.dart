import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../catalog/data/link_launcher.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/formatting.dart';
import '../../catalog/presentation/common/commerce_widgets.dart';
import 'invoices_screen.dart';
import 'orders_providers.dart';

class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(invoiceDetailProvider(invoiceId));
    final inv = value.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(inv == null ? 'Invoice' : 'Invoice ${inv.displayNumber}'),
        actions: [
          if (inv?.safeFileUri != null)
            IconButton(
              tooltip: 'Share invoice link',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => ref
                  .read(linkLauncherProvider)
                  .shareText(
                    inv!.safeFileUri.toString(),
                    subject: 'Invoice ${inv.displayNumber}',
                  ),
            ),
        ],
      ),
      body: AsyncValueView(
        value: value,
        onRetry: () => ref.invalidate(invoiceDetailProvider(invoiceId)),
        data: (i) => RefreshIndicator(
          onRefresh: () => ref.refresh(invoiceDetailProvider(invoiceId).future),
          child: ContentWidth(child: _InvoiceBody(invoice: i)),
        ),
      ),
    );
  }
}

class _InvoiceBody extends ConsumerWidget {
  const _InvoiceBody({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = invoice;
    final theme = Theme.of(context);
    final pdf = i.safeFileUri;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppSpacing.page,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: StatusChip(i.statusLabel, tone: toneForInvoice(i)),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: AppSpacing.page,
            child: Column(
              children: [
                InfoRow.text('Invoice number', i.displayNumber),
                InfoRow.text('Issued', formatDate(i.issuedAt)),
                if (i.dueAt != null) InfoRow.text('Due', formatDate(i.dueAt)),
                if (i.buyerGstin != null)
                  InfoRow.text('Your GSTIN', i.buyerGstin!),
                if (i.placeOfSupply != null)
                  InfoRow.text('Place of supply', i.placeOfSupply!),
                if (i.taxId != null) InfoRow.text('Seller GSTIN', i.taxId!),
              ],
            ),
          ),
        ),
        if (i.lines.isNotEmpty) ...[
          const SectionHeader('Items'),
          Card(
            child: Padding(
              padding: AppSpacing.page,
              child: Column(
                children: [
                  for (final l in i.lines)
                    InfoRow(
                      label: '${l.title} × ${l.quantity}',
                      value: MoneyText(l.lineTotal),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SectionHeader('Totals'),
        Card(
          child: Padding(
            padding: AppSpacing.page,
            child: Column(
              children: [
                if (i.subtotal != null) InfoRow.money('Subtotal', i.subtotal),
                if (i.discountTotal != null && !i.discountTotal!.isZero)
                  InfoRow.money('Discount', i.discountTotal, negative: true),
                for (final t in i.taxDetails)
                  InfoRow.money(
                    t.rate == null ? t.label : '${t.label} (${t.rate})',
                    t.amount,
                  ),
                if (i.taxDetails.isEmpty && i.taxTotal != null)
                  InfoRow.money('Tax', i.taxTotal),
                InfoRow.money('Total', i.total, emphasize: true),
                if (i.amountPaid != null) InfoRow.money('Paid', i.amountPaid),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (pdf != null)
          FilledButton.icon(
            onPressed: () async {
              final ok = await ref
                  .read(linkLauncherProvider)
                  .openDocument(pdf.toString());
              if (!ok && context.mounted) {
                showMessage(context, 'Couldn’t open the invoice PDF.');
              }
            },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Open PDF'),
          )
        else
          Text(
            'A downloadable PDF isn’t available for this invoice yet.',
            style: theme.textTheme.bodySmall,
          ),
        if (i.orderId != null) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.ownerOrder(i.orderId!)),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('View order'),
          ),
        ],
        if (i.subscriptionId != null) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () =>
                context.push(Routes.ownerSubscription(i.subscriptionId!)),
            icon: const Icon(Icons.autorenew),
            label: const Text('View subscription'),
          ),
        ],
      ],
    );
  }
}
