import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/widgets/state_views.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/presentation/common/commerce_widgets.dart';
import '../../catalog/presentation/common/feature_gate.dart';
import 'cart_checkout_providers.dart';
import 'widgets/personalization_editor.dart';
import 'widgets/quote_summary.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(cartProvider);
    final quote = ref.watch(cartQuoteProvider);
    final q = quote.value;
    final personalizationIssue = lines
        .map((l) => l.personalizationProblem)
        .whereType<String>()
        .firstOrNull;

    Widget bottom() {
      if (lines.isEmpty) return const SizedBox.shrink();
      if (quote.isLoading) {
        return const TotalBar(
          bottomPadding: 84.0,
          action: FilledButton(onPressed: null, child: Text('Getting price…')),
        );
      }
      if (q == null) {
        return TotalBar(
          bottomPadding: 84.0,
          caption: 'Prices, taxes and shipping are confirmed by our server.',
          action: FilledButton.icon(
            onPressed: () => ref.read(cartQuoteProvider.notifier).fetch(),
            icon: const Icon(Icons.request_quote_outlined),
            label: const Text('Get quote'),
          ),
        );
      }
      final blocked = !q.canCheckout || personalizationIssue != null;
      return TotalBar(
        total: q.total,
        bottomPadding: 84.0,
        caption:
            personalizationIssue ??
            (q.hasUnavailable ? 'Remove unavailable items to continue' : null),
        action: FilledButton.icon(
          onPressed: blocked ? null : () => context.push(Routes.ownerCheckout),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Checkout'),
        ),
      );
    }

    return FeatureGate(
      flag: Flags.shop,
      title: 'Cart',
      child: Scaffold(
        appBar: AppBar(
          title: Text(lines.isEmpty ? 'Cart' : 'Cart (${lines.length})'),
          actions: [
            if (lines.isNotEmpty)
              TextButton(
                onPressed: () => ref.read(cartProvider.notifier).clear(),
                child: const Text('Clear'),
              ),
          ],
        ),
        bottomNavigationBar: bottom(),
        body: lines.isEmpty
            ? EmptyView(
                icon: Icons.shopping_bag_outlined,
                title: 'Your cart is empty',
                message: 'Browse NFC products, services and plans in the shop.',
                action: FilledButton(
                  onPressed: () => context.push(Routes.ownerShop),
                  child: const Text('Browse shop'),
                ),
              )
            : ContentWidth(
                child: RefreshIndicator(
                  onRefresh: () => ref.read(cartQuoteProvider.notifier).fetch(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: AppSpacing.page,
                    children: [
                      for (final l in lines) ...[
                        _CartLineTile(line: l, quote: q),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (quote.hasError)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: ErrorView(
                            error: quote.error!,
                            onRetry: () =>
                                ref.read(cartQuoteProvider.notifier).fetch(),
                          ),
                        ),
                      if (q != null && q.hasUnavailable) ...[
                        NoticeCard(
                          title: 'Some items can’t be ordered',
                          message: q.invalidLines.isEmpty
                              ? 'Items marked unavailable must be removed before checkout.'
                              : q.invalidLines
                                    .map((i) => i.reason)
                                    .toSet()
                                    .join('\n'),
                          tone: StatusTone.warning,
                          action: TextButton(
                            onPressed: () => ref
                                .read(cartProvider.notifier)
                                .removeInvalid(q),
                            child: const Text('Remove unavailable items'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (q != null)
                        QuoteSummary(
                          quote: q,
                          shippingPending: ref.watch(cartNeedsShippingProvider),
                        ),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({required this.line, required this.quote});
  final CartLine line;
  final Quote? quote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cart = ref.read(cartProvider.notifier);
    final serverLine = quote?.lines
        .where(
          (q) => line.matches(
            itemId: q.itemId,
            itemType: q.itemType.name,
            variantId: q.variantId,
          ),
        )
        .firstOrNull;
    final invalid = quote?.invalidLines
        .where(
          (i) => line.matches(
            itemId: i.itemId,
            itemType: i.itemType,
            variantId: i.variantId,
          ),
        )
        .firstOrNull;
    final unavailable =
        invalid != null || (serverLine != null && !serverLine.available);
    final p = line.personalization;

    return Card(
      child: Padding(
        padding: AppSpacing.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.titleSnapshot,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (line.variantLabel != null)
                        Text(
                          line.variantLabel!,
                          style: theme.textTheme.bodySmall,
                        ),
                      if (serverLine?.lineTotal != null && !unavailable)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: MoneyText(
                            serverLine!.lineTotal,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      if (unavailable)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: StatusChip(
                            invalid?.reason ??
                                serverLine?.issue ??
                                'Unavailable',
                            tone: StatusTone.warning,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove ${line.titleSnapshot}',
                  onPressed: () => cart.remove(line.key),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            QuantityStepper(
              value: line.quantity,
              max: CartLine.maxQuantity,
              label: 'Quantity of ${line.titleSnapshot}',
              onChanged: (v) => cart.setQuantity(line.key, v),
            ),
            if (p != null) ...[
              const Divider(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  StatusChip(
                    p.assignLater
                        ? 'Assign later'
                        : line.personalizationProblem == null
                        ? 'Personalised'
                        : p.spec.perUnit
                        ? '${_complete(line)} of ${line.quantity} personalised'
                        : 'Needs details',
                    icon: Icons.nfc,
                    tone: line.personalizationProblem == null
                        ? StatusTone.success
                        : StatusTone.warning,
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final next = await showPersonalizationEditor(
                        context,
                        line,
                      );
                      if (next != null) cart.setPersonalization(line.key, next);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Personalise'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static int _complete(CartLine l) {
    final p = l.personalization!;
    return p.units.where((u) => u.problem(p.spec) == null && !u.isEmpty).length;
  }
}
