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
import 'widgets/catalog_item_card.dart';

/// Bizzvot services, products and plans with categories and search.
class ShopHomeScreen extends StatelessWidget {
  const ShopHomeScreen({super.key});

  /// Digital seats/plans are status-only in v1 (App Store 3.1.1 / Play
  /// Payments), so they are not offered in the shop; see Billing.
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
            title: const Text('Shop'),
            actions: const [
              CartButton(),
              SizedBox(width: AppSpacing.xs),
            ],
            bottom: const TabBar(
              tabs: [Tab(text: 'Products'), Tab(text: 'Services')],
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final query = (type: widget.type, category: _category, search: _query);
    final list = ref.watch(catalogListProvider(query));
    final notifier = ref.read(catalogListProvider(query).notifier);
    final isPlans = widget.type == CatalogItemType.plan;

    return LayoutBuilder(
      builder: (context, c) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final width = c.maxWidth.clamp(0, AppSpacing.maxContentWidth * 1.4);
        final columns = scale > 1.3
            ? (width / 340).floor().clamp(1, 3)
            : (width / 170).floor().clamp(1, 4);

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.maxContentWidth * 1.4,
            ),
            child: Column(
              children: [
                if (!isPlans)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    child: TextField(
                      controller: _search,
                      onChanged: _onSearch,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search ${widget.type.label.toLowerCase()}s',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _search.clear();
                                  _onSearch('');
                                  setState(() {});
                                },
                              ),
                      ),
                    ),
                  ),
                if (!isPlans)
                  _CategoryChips(
                    type: widget.type,
                    selected: _category,
                    onSelected: (v) => setState(() => _category = v),
                  ),
                  Expanded(
                  child: PagedListView(
                    value: list,
                    columns: columns,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.xl,
                    ),
                    onRefresh: notifier.refresh,
                    onLoadMore: notifier.loadMore,
                    empty: EmptyView(
                      icon: Icons.storefront_outlined,
                      title: _query != null || _category != null
                          ? 'No matches'
                          : 'Nothing here yet',
                      message: _query != null || _category != null
                          ? 'Try a different search or category.'
                          : 'New ${widget.type.label.toLowerCase()}s will appear here.',
                    ),
                    itemBuilder: (context, item) => CatalogItemCard(
                      item: item,
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

class _CategoryChips extends ConsumerWidget {
  const _CategoryChips({
    required this.type,
    required this.selected,
    required this.onSelected,
  });

  final CatalogItemType type;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(catalogCategoriesProvider).value ?? const [];
    final visible = cats
        .where((c) => c.type == null || c.type == type)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: AppSpacing.pageH,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final c in visible) ...[
            const SizedBox(width: AppSpacing.sm),
            ChoiceChip(
              label: Text(c.name),
              selected: selected == c.filterValue,
              onSelected: (on) => onSelected(on ? c.filterValue : null),
            ),
          ],
        ],
      ),
    );
  }
}
