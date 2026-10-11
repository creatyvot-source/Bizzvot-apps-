import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../domain/catalog_models.dart';
import '../common/commerce_widgets.dart';
import 'catalog_item_card.dart';

/// Immersive discovery card converting the Airbnb layout to Bizzvot products and digital cards.
/// Features a rounded photo carousel with dot indicators, floating wishlist heart,
/// overlaid avatar badge, star rating row, subtitle, and bold pricing hierarchy.
class DiscoveryMediaCard extends StatefulWidget {
  const DiscoveryMediaCard({
    super.key,
    required this.item,
    required this.onTap,
    this.avatarUrl,
    this.avatarInitial = 'B',
    this.rating = 4.96,
    this.reviewCount = 142,
    this.badgeText,
  });

  final CatalogItem item;
  final VoidCallback onTap;
  final String? avatarUrl;
  final String avatarInitial;
  final double rating;
  final int reviewCount;
  final String? badgeText;

  @override
  State<DiscoveryMediaCard> createState() => _DiscoveryMediaCardState();
}

class _DiscoveryMediaCardState extends State<DiscoveryMediaCard> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isFavorite = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final item = widget.item;

    final price = priceText(
      item.price,
      label: item.priceLabel,
      billingPeriod: item.billingPeriod,
      contactOnly: item.contactOnly,
    );

    final images = item.images.isNotEmpty
        ? item.images
        : [null]; // At least one page to show placeholder

    final unavailable = !item.active || !item.inStock;

    return Semantics(
      button: true,
      label: '${item.title}, $price, Rating ${widget.rating} stars',
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Media Carousel Container (Airbnb Photo Style)
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Image PageView
                      PageView.builder(
                        controller: _pageController,
                        itemCount: images.length,
                        onPageChanged: (i) => setState(() => _currentPage = i),
                        itemBuilder: (context, index) {
                          return SafeNetworkImage(
                            url: images[index],
                            placeholderIcon: switch (item.type) {
                              CatalogItemType.product =>
                                Icons.inventory_2_outlined,
                              CatalogItemType.plan =>
                                Icons.workspace_premium_outlined,
                              _ => Icons.design_services_outlined,
                            },
                          );
                        },
                      ),

                      // Gradient overlay for bottom badge legibility
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 60,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.4),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Carousel Dot Indicators (Bottom Center)
                      if (images.length > 1)
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              images.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                                width: _currentPage == i ? 7 : 5,
                                height: _currentPage == i ? 7 : 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _currentPage == i
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Floating Top-Right Wishlist Heart Button
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Tooltip(
                          message: _isFavorite ? 'Remove from wishlist' : 'Save to wishlist',
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () {
                                setState(() => _isFavorite = !_isFavorite);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.25),
                                ),
                                child: Icon(
                                  _isFavorite
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: _isFavorite ? Colors.redAccent : Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Overlaid Bottom-Left Avatar / Brand Badge (Airbnb Host Avatar style)
                      Positioned(
                        bottom: 10,
                        left: 12,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 17,
                            backgroundColor: theme.colorScheme.primary,
                            backgroundImage: widget.avatarUrl != null
                                ? NetworkImage(widget.avatarUrl!)
                                : null,
                            child: widget.avatarUrl == null
                                ? Text(
                                    widget.avatarInitial,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),

                      // Optional Top-Left Status Badge (e.g. "Bestseller" or "NFC Powered")
                      if (widget.badgeText != null || unavailable)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: unavailable
                                  ? Colors.black.withValues(alpha: 0.75)
                                  : Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              unavailable ? 'Unavailable' : widget.badgeText!,
                              style: TextStyle(
                                color: unavailable ? Colors.white : Colors.black,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 2. Info Block (Airbnb Typography & Hierarchy)
              // Row 1: Title (left) & Star Rating (right)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.25,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        widget.rating.toStringAsFixed(2),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 3),

              // Row 2: Subtitle / Features / Tech
              Text(
                item.summary ??
                    (item.includesNote != null
                        ? item.includesNote!
                        : 'Dynamic NFC + QR · Instant tap to review'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? theme.colorScheme.onSurfaceVariant
                      : const Color(0xFF71717A),
                  fontSize: 13,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 2),

              // Row 3: Fulfilment / Delivery / Shipping
              Text(
                'Fast dispatch · Free delivery across India',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8)
                      : const Color(0xFFA1A1AA),
                  fontSize: 12,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 6),

              // Row 4: Price Hierarchy
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: price,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    TextSpan(
                      text: ' total',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? theme.colorScheme.onSurfaceVariant
                            : const Color(0xFF71717A),
                        fontSize: 13,
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
