import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../catalog/domain/commerce_models.dart';
import '../../../catalog/domain/money.dart';
import '../../../catalog/presentation/common/commerce_widgets.dart';

/// Itemised server quote: lines, discounts, taxes, shipping and total.
/// Every amount shown is a server value; nothing is summed on the client.
class QuoteSummary extends StatelessWidget {
  const QuoteSummary({
    super.key,
    required this.quote,
    this.showLines = true,
    this.shippingPending = false,
  });

  final Quote quote;
  final bool showLines;

  /// Shipping depends on an address not yet given.
  final bool shippingPending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: AppSpacing.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Order summary', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (showLines)
              for (final l in quote.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InfoRow(
                        label:
                            '${l.title}${l.variantLabel == null ? '' : ' · ${l.variantLabel}'} × ${l.quantity}',
                        value: l.available
                            ? MoneyText(l.lineTotal)
                            : const Text('Unavailable'),
                      ),
                      if (l.unitPrice != null && l.quantity > 1)
                        Text(
                          '${l.unitPrice!.format()} each',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (!l.available && l.issue != null)
                        Text(
                          l.issue!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
            if (showLines) const Divider(height: AppSpacing.lg),
            if (quote.subtotal != null)
              InfoRow.money('Subtotal', quote.subtotal),
            for (final d in quote.discounts)
              InfoRow.money(d.label, d.amount, negative: true),
            if (quote.discounts.isEmpty &&
                quote.discountTotal != null &&
                !quote.discountTotal!.isZero)
              InfoRow.money('Discount', quote.discountTotal, negative: true),
            if (quote.shipping != null)
              InfoRow(
                label: 'Shipping',
                value: quote.shipping!.isZero
                    ? const Text('Free')
                    : MoneyText(quote.shipping),
              )
            else if (shippingPending)
              InfoRow.text('Shipping', 'Calculated after address'),
            for (final t in quote.taxes)
              InfoRow.money(
                t.rate == null ? t.label : '${t.label} (${t.rate})',
                t.amount,
              ),
            if (quote.taxes.isEmpty && quote.taxTotal != null)
              InfoRow.money('Tax', quote.taxTotal),
            const Divider(height: AppSpacing.lg),
            InfoRow.money(
              'Total',
              quote.total,
              emphasize: true,
              fallback: 'Unavailable',
            ),
            for (final n in quote.notes)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  n,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sticky bottom bar: server total + primary action.
class TotalBar extends StatelessWidget {
  const TotalBar({super.key, required this.action, this.total, this.caption});

  final Money? total;
  final String? caption;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              if (total != null || caption != null)
                MergeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (total != null)
                        Text('Total', style: theme.textTheme.labelMedium),
                      if (total != null)
                        MoneyText(
                          total,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      if (caption != null)
                        Text(
                          caption!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              action,
            ],
          ),
        ),
      ),
    );
  }
}
