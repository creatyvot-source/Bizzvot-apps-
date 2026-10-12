import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/config/app_config.dart';
import '../../cart_checkout/presentation/cart_checkout_providers.dart';
import '../../cart_checkout/presentation/widgets/cart_button.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog_models.dart';
import '../domain/commerce_models.dart';
import 'catalog_providers.dart';
import 'common/feature_gate.dart';

/// Shop screen with:
/// - 2 clean header options: [Products] & [Services] (no category clutter)
/// - 2-column grid for products with direct Add to Cart and combo pack selection
/// - WhatsApp enquiries for services using phone number `+91 89215 04090`
/// - High-impact promotional hero banners based on the BizzVcard poster
/// - Reseller 30% commission program spotlight
class ShopHomeScreen extends ConsumerStatefulWidget {
  const ShopHomeScreen({super.key});

  @override
  ConsumerState<ShopHomeScreen> createState() => _ShopHomeScreenState();
}

class _ShopHomeScreenState extends ConsumerState<ShopHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _supportPhone = '+91 89215 04090';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openWhatsAppEnquiry(String subject) async {
    final cleanPhone = _supportPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final msg = Uri.encodeComponent(
      'Hi BizzVcard team, I want to enquire about: $subject. Please share details and pricing.',
    );
    final uri = Uri.parse('https://wa.me/$cleanPhone?text=$msg');
    HapticFeedback.lightImpact();
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _makeDirectCall() async {
    final cleaned = _supportPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    HapticFeedback.lightImpact();
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FeatureGate(
      flag: Flags.shop,
      title: 'Shop',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bizzvot Store'),
          actions: const [
            ThemeToggleActionButton(),
            CartButton(),
            SizedBox(width: AppSpacing.xs),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.surfaceContainerHigh
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: theme.colorScheme.onPrimary,
                  unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_bag_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Products'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.support_agent_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Services & Enquiry'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _ProductsTab(
              onViewDetails: (item) => context.push(
                Routes.ownerShopItem(item.type.wire, item.id),
              ),
              onOpenWhatsApp: _openWhatsAppEnquiry,
            ),
            _ServicesTab(
              onOpenWhatsApp: _openWhatsAppEnquiry,
              onCall: _makeDirectCall,
            ),
          ],
        ),
      ),
    );
  }
}

/// 2-Column Products Grid with Top Promotional Banners
class _ProductsTab extends ConsumerWidget {
  const _ProductsTab({
    required this.onViewDetails,
    required this.onOpenWhatsApp,
  });

  final ValueChanged<CatalogItem> onViewDetails;
  final ValueChanged<String> onOpenWhatsApp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const query = (
      type: CatalogItemType.product,
      category: null,
      search: null,
    );
    final asyncList = ref.watch(catalogListProvider(query));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    var products = asyncList.value?.items ?? const [];
    if (products.isEmpty) {
      products = CatalogRepository.dummyProducts;
    }

    return RefreshIndicator(
      onRefresh: () => ref.refresh(catalogListProvider(query).notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 110),
        children: [
          // 1. Promotional Hero Banner based on the User's Poster
          _PromoHeroBanner(
            onJoinReseller: () => onOpenWhatsApp(
              'BizzVcard Reseller Partner Program (30% Commission)',
            ),
          ),
          const SizedBox(height: 14),

          // 2. What We Can Do All-Category Feature Banner
          _WhatWeCanDoBanner(theme: theme, isDark: isDark),
          const SizedBox(height: 16),

          // Section Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Smart NFC & Hardware Products',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '2-Column Store',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3. 2-COLUMN GRID OF PRODUCTS
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: products.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.60,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
            ),
            itemBuilder: (context, i) {
              final item = products[i];
              return _ProductGridCard(
                item: item,
                onTap: () => onViewDetails(item),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Promotional Hero Banner with Poster image / gradient & 30% Reseller CTA
class _PromoHeroBanner extends StatelessWidget {
  const _PromoHeroBanner({required this.onJoinReseller});

  final VoidCallback onJoinReseller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background poster image if available
          Positioned.fill(
            child: Opacity(
              opacity: 0.35,
              child: Image.asset(
                'assets/images/bizzvcard_promo_banner.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          // Content Overlay
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9800),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.workspace_premium, size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            '30% COMMISSION',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Text(
                      'bizzVcard.com',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'ONE CARD.\nMORE BUSINESS.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Become a BizzVcard Reseller · High demand Google Review & Smart NFC cards · Marketing support included.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onJoinReseller,
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text(
                    'Enquire on WhatsApp (+91 89215 04090)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "What We Can Do" Category Showcase Banner
class _WhatWeCanDoBanner extends StatelessWidget {
  const _WhatWeCanDoBanner({required this.theme, required this.isDark});

  final ThemeData theme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHigh
            : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.3)
              : const Color(0xFF86EFAC),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Color(0xFF16A34A),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'What We Can Do For Your Business',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF14532D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _capabilityPill('Google Review Stand (₹499)', Icons.star_rate_rounded),
              _capabilityPill('Google Review Cards (₹350)', Icons.contactless_rounded),
              _capabilityPill('Business Digital Card (₹999)', Icons.badge_rounded),
              _capabilityPill('Staff ID Smart Cards (₹350)', Icons.people_alt_rounded),
              _capabilityPill('30% Margin for Resellers', Icons.monetization_on_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _capabilityPill(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white12
              : Colors.green.shade200,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF16A34A)),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : const Color(0xFF166534),
            ),
          ),
        ],
      ),
    );
  }
}

/// 2-Column Product Grid Card with Direct Add to Cart and Combos
class _ProductGridCard extends ConsumerStatefulWidget {
  const _ProductGridCard({required this.item, required this.onTap});

  final CatalogItem item;
  final VoidCallback onTap;

  @override
  ConsumerState<_ProductGridCard> createState() => _ProductGridCardState();
}

class _ProductGridCardState extends ConsumerState<_ProductGridCard> {
  int _selectedVariantIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final item = widget.item;

    final variants = item.variants;
    final activeVariant = variants.isNotEmpty && _selectedVariantIndex < variants.length
        ? variants[_selectedVariantIndex]
        : null;

    final displayPrice = activeVariant?.price?.format() ??
        item.price?.format() ??
        item.priceLabel ??
        '₹350';

    final imageUrl = item.images.isNotEmpty ? item.images.first : null;

    void addToCart() {
      HapticFeedback.mediumImpact();
      final line = CartLine(
        itemType: item.type,
        itemId: item.id,
        variantId: activeVariant?.id,
        variantLabel: activeVariant?.name,
        quantity: 1,
        titleSnapshot: item.title,
        paymentPolicy: item.paymentPolicy,
        requiresShipping: item.requiresShipping,
      );
      ref.read(cartProvider.notifier).add(line);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Added ${item.title} to Cart!',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'VIEW CART',
            textColor: Colors.white,
            onPressed: () {
              final isStaff = ref.read(currentUserProvider)?.isStaff ?? false;
              context.go(isStaff ? Routes.staffCart : Routes.ownerCart);
            },
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.3)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      color: isDark ? theme.colorScheme.surfaceContainerHigh : Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image with NFC badge
            AspectRatio(
              aspectRatio: 1.3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl != null)
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.credit_card, size: 40),
                      ),
                    )
                  else
                    Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.credit_card, size: 40),
                    ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.nfc, size: 12, color: Colors.white),
                          SizedBox(width: 2),
                          Text(
                            'NFC + QR',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),

                        // Combo pack variant switcher if available
                        if (variants.length > 1)
                          DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _selectedVariantIndex,
                              isDense: true,
                              isExpanded: true,
                              icon: const Icon(Icons.arrow_drop_down, size: 18),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                              items: [
                                for (var idx = 0; idx < variants.length; idx++)
                                  DropdownMenuItem(
                                    value: idx,
                                    child: Text(
                                      '${variants[idx].name} (${variants[idx].price?.format() ?? ''})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedVariantIndex = val);
                                }
                              },
                            ),
                          ),
                      ],
                    ),

                    // Price & Direct Add to Cart
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              displayPrice,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: theme.colorScheme.primary,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '+ GST & courier',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 9.5,
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          height: 32,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: addToCart,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_shopping_cart, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Add to Cart',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Services & Enquiries Tab with Reseller 30% Program and WhatsApp CTA
class _ServicesTab extends StatelessWidget {
  const _ServicesTab({
    required this.onOpenWhatsApp,
    required this.onCall,
  });

  final ValueChanged<String> onOpenWhatsApp;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final services = CatalogRepository.dummyServices;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
      children: [
        // 1. Reseller 30% Commission Hero Showcase
        _ResellerServiceCard(
          onJoin: () => onOpenWhatsApp(
            'BizzVcard Reseller Partner (30% Commission on every sale)',
          ),
        ),
        const SizedBox(height: 16),

        // 2. Direct WhatsApp & Call Bar
        _DirectContactBar(
          theme: theme,
          isDark: isDark,
          onWhatsApp: () => onOpenWhatsApp('General BizzVcard Service Enquiry'),
          onCall: onCall,
        ),
        const SizedBox(height: 20),

        // Section Title
        Text(
          'Services & Enterprise Customization',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 12),

        // 3. Service Cards
        for (final s in services) ...[
          _ServiceDetailCard(
            item: s,
            onWhatsApp: () => onOpenWhatsApp('${s.title} (${s.priceLabel})'),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _ResellerServiceCard extends StatelessWidget {
  const _ResellerServiceCard({required this.onJoin});

  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFFEA580C), Color(0xFFC2410C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEA580C).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '⭐ 30% COMMISSION',
                  style: TextStyle(
                    color: Color(0xFFC2410C),
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
              const Text(
                'TAP · CONNECT · GROW',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Become a BizzVcard Reseller',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Earn 30% commission on every Google Review card, stand & digital card sold to local businesses.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),

          // Features bullet points
          _resellerBullet(Icons.trending_up, 'High Demand Products (Digital Cards & Review Stands)'),
          _resellerBullet(Icons.paid_outlined, '30% Commission paid directly on every sale'),
          _resellerBullet(Icons.inventory_2_outlined, 'Full Marketing Support: posters, content & graphics'),
          _resellerBullet(Icons.flash_on, 'Easy Onboarding: start selling today'),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFFC2410C),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onJoin,
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text(
                'Join via WhatsApp (+91 89215 04090)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resellerBullet(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectContactBar extends StatelessWidget {
  const _DirectContactBar({
    required this.theme,
    required this.isDark,
    required this.onWhatsApp,
    required this.onCall,
  });

  final ThemeData theme;
  final bool isDark;
  final VoidCallback onWhatsApp;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHigh
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Need Custom Orders or Bulk Inquiries?',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Direct helpline: +91 89215 04090 (Available 9 AM - 8 PM IST)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onWhatsApp,
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text(
                    'WhatsApp',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onCall,
                  icon: const Icon(Icons.call, size: 16),
                  label: const Text(
                    'Direct Call',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServiceDetailCard extends StatelessWidget {
  const _ServiceDetailCard({required this.item, required this.onWhatsApp});

  final CatalogItem item;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.3)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      color: isDark ? theme.colorScheme.surfaceContainerHigh : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                        item.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.priceLabel ?? 'Custom Enquiry',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.design_services_outlined,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.description ?? item.summary ?? '',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            if (item.features.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final f in item.features)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          f,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.15),
                  foregroundColor: const Color(0xFF1E8E42),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: onWhatsApp,
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text(
                  'Enquire on WhatsApp (+91 89215 04090)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
