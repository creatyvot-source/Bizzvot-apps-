import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/widgets/state_views.dart';
import '../../cart_checkout/presentation/widgets/cart_button.dart';
import '../domain/catalog_models.dart';
import 'catalog_providers.dart';
import 'common/feature_gate.dart';
import 'common/paged_list.dart';
import 'widgets/category_icon_tab_bar.dart';
import 'widgets/discovery_media_card.dart';
import 'widgets/floating_search_capsule.dart';

/// Modern Bizzvot Services & Shop screen converted to an Airbnb-inspired discovery layout.
/// Features a floating search capsule pill, horizontal icon category tabs, and
/// immersive media discovery cards with ratings, avatar badges, and clear pricing.
class ShopHomeScreen extends StatelessWidget {
  const ShopHomeScreen({super.key});

  static const _tabs = [CatalogItemType.product, CatalogItemType.service];

  @override
  Widget build(BuildContext context) {
    return FeatureGate(
      flag: Flags.shop,
      title: 'Shop',
      child: DefaultTabController(
        length: _tabs.length,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Bizzvot Shop & NFC'),
            actions: const [
              CartButton(),
              SizedBox(width: AppSpacing.xs),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'NFC Products & Hardware'),
                Tab(text: 'Digital Cards & Services'),
              ],
            ),
          ),
          body: TabBarView(
            children: [for (final t in _tabs) _CatalogTab(type: t)],
          ),
        ),
      ),
    );
  }
}

class _CatalogTab extends ConsumerStatefulWidget {
  const _CatalogTab({required this.type});
  final CatalogItemType type;

  @override
  ConsumerState<_CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends ConsumerState<_CatalogTab>
    with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  Timer? _debounce;
  String? _query;
  String? _category;
  bool _isSearching = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final q = v.trim();
      setState(() => _query = q.isEmpty ? null : q);
    });
  }

  List<CategoryTabItem> _buildCategoryTabs() {
    if (widget.type == CatalogItemType.product) {
      return const [
        CategoryTabItem(
          id: '',
          label: 'All NFC',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard_rounded,
        ),
        CategoryTabItem(
          id: 'stands',
          label: 'Review Stands',
          icon: Icons.star_outline_rounded,
          selectedIcon: Icons.star_rounded,
        ),
        CategoryTabItem(
          id: 'cards',
          label: 'Smart NFC Cards',
          icon: Icons.contactless_outlined,
          selectedIcon: Icons.contactless_rounded,
        ),
        CategoryTabItem(
          id: 'staff_badges',
          label: 'Staff ID Badges',
          icon: Icons.badge_outlined,
          selectedIcon: Icons.badge_rounded,
        ),
        CategoryTabItem(
          id: 'combos',
          label: 'Business Bundles',
          icon: Icons.business_center_outlined,
          selectedIcon: Icons.business_center_rounded,
        ),
      ];
    } else {
      return const [
        CategoryTabItem(
          id: '',
          label: 'All Services',
          icon: Icons.grid_view_outlined,
          selectedIcon: Icons.grid_view_rounded,
        ),
        CategoryTabItem(
          id: 'design',
          label: 'Custom Branding',
          icon: Icons.palette_outlined,
          selectedIcon: Icons.palette_rounded,
        ),
        CategoryTabItem(
          id: 'reviews',
          label: 'Review Setup',
          icon: Icons.rate_review_outlined,
          selectedIcon: Icons.rate_review_rounded,
        ),
        CategoryTabItem(
          id: 'enterprise',
          label: 'Enterprise Onboarding',
          icon: Icons.domain_outlined,
          selectedIcon: Icons.domain_rounded,
        ),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final query = (type: widget.type, category: _category, search: _query);
    final list = ref.watch(catalogListProvider(query));
    final notifier = ref.read(catalogListProvider(query).notifier);

    return LayoutBuilder(
      builder: (context, c) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final width = c.maxWidth.clamp(0, AppSpacing.maxContentWidth * 1.4);
        final columns = scale > 1.3
            ? (width / 380).floor().clamp(1, 2)
            : (width / 320).floor().clamp(1, 3);

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.maxContentWidth * 1.4,
            ),
            child: Column(
              children: [
                const SizedBox(height: 4),

                // 1. Floating Airbnb-Style Search Capsule Pill
                if (!_isSearching)
                  FloatingSearchCapsule(
                    title: _query != null && _query!.isNotEmpty
                        ? 'Search: $_query'
                        : 'Explore Bizzvot NFC & Cards',
                    subtitle: widget.type == CatalogItemType.product
                        ? 'Google Review Stands · Smart Cards · ID Badges'
                        : 'Digital Profiles · Brand Services · Reviews',
                    isFilterActive: _category != null,
                    onTap: () => setState(() => _isSearching = true),
                    onFilterTap: () => setState(() => _isSearching = true),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    child: TextField(
                      controller: _search,
                      autofocus: true,
                      onChanged: _onSearch,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText:
                            'Search ${widget.type.label.toLowerCase()}s by name or SKU...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          tooltip: 'Close search',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            _onSearch('');
                            setState(() => _isSearching = false);
                          },
                        ),
                      ),
                    ),
                  ),

                // 2. Horizontal Scrolling Icon Category Tab Bar (Airbnb Style)
                CategoryIconTabBar(
                  items: _buildCategoryTabs(),
                  selectedId: _category ?? '',
                  onSelected: (id) => setState(() => _category = id),
                ),

                const Divider(height: 1, thickness: 0.5),

                // 3. Immersive Feed of Discovery Media Cards
                Expanded(
                  child: PagedListView(
                    value: list,
                    columns: columns,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.xl,
                    ),
                    onRefresh: notifier.refresh,
                    onLoadMore: notifier.loadMore,
                    empty: EmptyView(
                      icon: Icons.storefront_outlined,
                      title: _query != null || _category != null
                          ? 'No matching products'
                          : 'Nothing here yet',
                      message: _query != null || _category != null
                          ? 'Try selecting "All NFC" or clearing search keywords.'
                          : 'New ${widget.type.label.toLowerCase()}s will appear here.',
                    ),
                    itemBuilder: (context, item) => DiscoveryMediaCard(
                      item: item,
                      rating: 4.98,
                      reviewCount: 218,
                      badgeText: item.type == CatalogItemType.product
                          ? 'NFC Tap Enabled'
                          : 'Digital Service',
                      onTap: () => context.push(
                        Routes.ownerShopItem(item.type.wire, item.id),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
