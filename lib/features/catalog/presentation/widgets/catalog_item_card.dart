import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../domain/catalog_models.dart';
import '../../domain/formatting.dart';
import '../../domain/money.dart';
import '../common/commerce_widgets.dart';

/// "/ month", "/ year" or '' for one-time prices.
String periodSuffix(String? billingPeriod) {
  final k = wireKey(billingPeriod);
  return switch (k) {
    '' || 'one_time' || 'once' || 'onetime' || 'lifetime' => '',
    'month' || 'monthly' || 'mo' => ' / month',
    'year' || 'yearly' || 'annual' || 'annually' || 'yr' => ' / year',
    'quarter' || 'quarterly' => ' / quarter',
    'week' || 'weekly' => ' / week',
    _ => ' / ${humanize(billingPeriod).toLowerCase()}',
  };
}

/// Server display price for an item, or "Contact us".
String priceText(
  Money? price, {
  String? label,
  String? billingPeriod,
  bool contactOnly = false,
}) {
  if (contactOnly && label == null) return 'Contact us';
  if (label != null) return label;
  if (price == null) return 'Contact us';
  return '${price.format()}${periodSuffix(billingPeriod)}';
}

/// Image-forward catalogue card with a clear price hierarchy.
class CatalogItemCard extends StatelessWidget {
  const CatalogItemCard({super.key, required this.item, required this.onTap});

  final CatalogItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = priceText(
      item.price,
      label: item.priceLabel,
      billingPeriod: item.billingPeriod,
      contactOnly: item.contactOnly,
    );
    final unavailable = !item.active || !item.inStock;
    return Semantics(
      button: true,
      label: '${item.title}, $price${unavailable ? ', unavailable' : ''}',
      excludeSemantics: true,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SafeNetworkImage(
                      url: item.images.firstOrNull,
                      placeholderIcon: switch (item.type) {
                        CatalogItemType.product => Icons.inventory_2_outlined,
                        CatalogItemType.plan =>
                          Icons.workspace_premium_outlined,
                        _ => Icons.design_services_outlined,
                      },
                    ),
                    if (unavailable || item.categoryName != null)
                      Positioned(
                        left: AppSpacing.sm,
                        top: AppSpacing.sm,
                        right: AppSpacing.sm,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: StatusChip(
                            unavailable ? 'Unavailable' : item.categoryName!,
                            tone: unavailable
                                ? StatusTone.warning
                                : StatusTone.neutral,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.summary != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        item.summary!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      price,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
