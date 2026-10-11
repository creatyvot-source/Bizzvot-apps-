import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../cart_checkout/presentation/cart_checkout_providers.dart';
import '../../cart_checkout/presentation/widgets/cart_button.dart';
import '../data/link_launcher.dart';
import '../domain/catalog_models.dart';
import '../domain/commerce_models.dart';
import '../domain/idempotency.dart';
import '../domain/physical_models.dart';
import 'catalog_providers.dart';
import 'common/commerce_widgets.dart';
import 'common/feature_gate.dart';
import 'widgets/catalog_item_card.dart';

class CatalogItemScreen extends ConsumerStatefulWidget {
  const CatalogItemScreen({super.key, required this.type, required this.id});

  final String type;
  final String id;

  @override
  ConsumerState<CatalogItemScreen> createState() => _CatalogItemScreenState();
}

class _CatalogItemScreenState extends ConsumerState<CatalogItemScreen> {
  String? _variantId;
  final Set<String> _addOns = {};
  int _quantity = 1;

  CatalogItemKey get _key =>
      (type: CatalogItemType.parse(widget.type), id: widget.id);

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(catalogItemProvider(_key));
    final item = value.value;
    return FeatureGate(
      flag: Flags.shop,
      title: 'Shop',
      child: Scaffold(
        appBar: AppBar(
          title: Text(item?.title ?? _key.type.label),
          actions: const [
            CartButton(),
            SizedBox(width: AppSpacing.xs),
          ],
        ),
        body: AsyncValueView(
          value: value,
          onRetry: () => ref.invalidate(catalogItemProvider(_key)),
          data: _body,
        ),
        bottomNavigationBar: item == null ? null : _bottomBar(item),
      ),
    );
  }

  CatalogVariant? _variant(CatalogItem item) {
    if (item.variants.isEmpty) return null;
    final chosen = item.variants.where((v) => v.id == _variantId).firstOrNull;
    return chosen ?? item.variants.where((v) => v.available).firstOrNull;
  }

  Widget _body(CatalogItem item) {
    final theme = Theme.of(context);
    final variant = _variant(item);
    final displayPrice = variant?.price ?? item.price;
    return ContentWidth(
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          _Gallery(images: item.images, title: item.title, type: item.type),
          Padding(
            padding: AppSpacing.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.categoryName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: StatusChip(item.categoryName!),
                  ),
                Text(item.title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  priceText(
                    displayPrice,
                    label: variant?.price == null ? item.priceLabel : null,
                    billingPeriod: item.billingPeriod,
                    contactOnly: item.contactOnly,
                  ),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!item.contactOnly)
                  Text(
                    'Final price, taxes and any discounts are confirmed at checkout.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ..._statusNotices(item),
                if (!item.personalization.isNone && item.purchasable) ...[
                  const SizedBox(height: AppSpacing.md),
                  NoticeCard(
                    title: 'Personalised NFC product',
                    message: item.personalization.perUnit
                        ? 'After adding to cart, link each unit to a card and add the details to print — or choose “assign later”.'
                        : 'After adding to cart, choose what the NFC tag opens and the details to print — or choose “assign later”.',
                    icon: Icons.nfc,
                  ),
                ],
                if (item.summary != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(item.summary!, style: theme.textTheme.bodyLarge),
                ],
                if (item.description != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(item.description!, style: theme.textTheme.bodyMedium),
                ],
                if (item.variants.isNotEmpty) ...[
                  const SectionHeader('Options'),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final v in item.variants)
                        ChoiceChip(
                          label: Text(
                            v.price == null
                                ? v.name
                                : '${v.name} · ${v.price!.format()}',
                          ),
                          selected: variant?.id == v.id,
                          onSelected: v.available
                              ? (_) => setState(() => _variantId = v.id)
                              : null,
                          tooltip: v.available
                              ? null
                              : '${v.name} is unavailable',
                        ),
                    ],
                  ),
                ],
                if (item.addOns.isNotEmpty) ...[
                  const SectionHeader('Add-ons'),
                  for (final a in item.addOns)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _addOns.contains(a.id),
                      onChanged: item.purchasable
                          ? (on) => setState(
                              () => on == true
                                  ? _addOns.add(a.id)
                                  : _addOns.remove(a.id),
                            )
                          : null,
                      title: Text(a.title),
                      subtitle: Text(
                        [
                          if (a.price != null) '+ ${a.price!.format()}',
                          ?a.description,
                        ].join(' · '),
                      ),
                    ),
                ],
                if (item.benefits.isNotEmpty) ...[
                  const SectionHeader('Benefits'),
                  for (final b in item.benefits)
                    _Bullet(b, icon: Icons.star_outline),
                ],
                if (item.features.isNotEmpty) ...[
                  const SectionHeader('What’s included'),
                  for (final f in item.features)
                    _Bullet(f, icon: Icons.check_circle_outline),
                ],
                if (item.eligibilityNotes.isNotEmpty) ...[
                  const SectionHeader('Eligibility'),
                  for (final n in item.eligibilityNotes)
                    _Bullet(n, icon: Icons.info_outline),
                ],
                if (item.faq.isNotEmpty) ...[
                  const SectionHeader('FAQ'),
                  for (final f in item.faq)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(f.question),
                      childrenPadding: const EdgeInsets.only(
                        bottom: AppSpacing.md,
                      ),
                      expandedAlignment: Alignment.centerLeft,
                      children: [Text(f.answer)],
                    ),
                ],
                const SectionHeader('Need help?'),
                OutlinedButton.icon(
                  onPressed: () => _contact(item),
                  icon: const Icon(Icons.support_agent_outlined),
                  label: const Text('Contact support'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _statusNotices(CatalogItem item) {
    final notices = <Widget>[];
    void add(String title, String msg, StatusTone tone) => notices.addAll([
      const SizedBox(height: AppSpacing.md),
      NoticeCard(title: title, message: msg, tone: tone),
    ]);
    if (item.paymentPolicy.blocksCheckout) {
      add(
        'Purchase not available in app yet',
        'This item can’t be bought in the app yet. Contact us to purchase it.',
        StatusTone.info,
      );
    } else if (!item.active) {
      add(
        'Currently unavailable',
        'This item is not on sale right now.',
        StatusTone.warning,
      );
    } else if (!item.inStock) {
      add(
        'Out of stock',
        'This item is temporarily out of stock.',
        StatusTone.warning,
      );
    }
    return notices;
  }

  Widget _bottomBar(CatalogItem item) {
    final theme = Theme.of(context);
    final isPlan = item.type == CatalogItemType.plan;
    final variant = _variant(item);
    final variantBlocked = item.variants.isNotEmpty && variant == null;
    Widget action;
    if (isPlan && !item.paymentPolicy.blocksCheckout) {
      action = FilledButton.icon(
        onPressed: () => context.push(Routes.ownerSeats),
        icon: const Icon(Icons.event_seat_outlined),
        label: const Text('Choose seats'),
      );
    } else if (item.contactOnly || item.paymentPolicy.blocksCheckout) {
      action = FilledButton.icon(
        onPressed: () => _contact(item),
        icon: const Icon(Icons.mail_outline),
        label: const Text('Contact us'),
      );
    } else {
      action = FilledButton.icon(
        onPressed: item.purchasable && !variantBlocked
            ? () => _addToCart(item, variant)
            : null,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Add to cart'),
      );
    }
    final showQty = !isPlan && item.purchasable;
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
              if (showQty)
                QuantityStepper(
                  value: _quantity,
                  max: item.maxQuantity ?? CartLine.maxQuantity,
                  onChanged: (q) => setState(() => _quantity = q),
                ),
              action,
            ],
          ),
        ),
      ),
    );
  }

  void _addToCart(CatalogItem item, CatalogVariant? variant) {
    ref
        .read(cartProvider.notifier)
        .add(
          CartLine(
            itemType: item.type,
            itemId: item.id,
            variantId: variant?.id,
            variantLabel: variant?.name,
            addOnIds: _addOns.toList(),
            quantity: _quantity,
            titleSnapshot: item.title,
            paymentPolicy: item.paymentPolicy,
            requiresShipping: item.requiresShipping,
            // Personalised lines never merge: each holds its own unit details.
            lineId: item.personalization.isNone ? null : uuidV4(),
            personalization: item.personalization.isNone
                ? null
                : LinePersonalization(spec: item.personalization)
                      .resized(_quantity)
                      .withAtLeastOne(),
          ),
        );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Added ${item.title} to cart'),
          action: SnackBarAction(
            label: 'View cart',
            onPressed: () => context.push(Routes.ownerCart),
          ),
        ),
      );
  }

  Future<void> _contact(CatalogItem item) async {
    final config = ref.read(currentConfigProvider);
    final email = config.supportEmail ?? item.supportEmail;
    final phone = config.supportPhone ?? item.supportPhone;
    final launcher = ref.read(linkLauncherProvider);
    if (email == null && phone == null) {
      showMessage(
        context,
        'Support contact details are not available right now.',
      );
      return;
    }
    if (email != null && phone == null) {
      await _report(launcher.email(email, subject: 'Enquiry: ${item.title}'));
      return;
    }
    if (phone != null && email == null) {
      await _report(launcher.call(phone));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Email us'),
              subtitle: Text(email!),
              onTap: () {
                Navigator.of(ctx).pop();
                _report(
                  launcher.email(email, subject: 'Enquiry: ${item.title}'),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.call_outlined),
              title: const Text('Call us'),
              subtitle: Text(phone!),
              onTap: () {
                Navigator.of(ctx).pop();
                _report(launcher.call(phone));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _report(Future<bool> launch) async {
    final ok = await launch;
    if (!ok && mounted) {
      showMessage(context, 'Couldn’t open that link on this device.');
    }
  }
}

class _Gallery extends StatefulWidget {
  const _Gallery({
    required this.images,
    required this.title,
    required this.type,
  });
  final List<String> images;
  final String title;
  final CatalogItemType type;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    final icon = switch (widget.type) {
      CatalogItemType.product => Icons.inventory_2_outlined,
      CatalogItemType.plan => Icons.workspace_premium_outlined,
      _ => Icons.design_services_outlined,
    };
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: images.length <= 1
          ? SafeNetworkImage(
              url: images.firstOrNull,
              placeholderIcon: icon,
              semanticLabel: '${widget.title} image',
            )
          : Stack(
              children: [
                PageView.builder(
                  itemCount: images.length,
                  onPageChanged: (p) => setState(() => _page = p),
                  itemBuilder: (_, i) => SafeNetworkImage(
                    url: images[i],
                    placeholderIcon: icon,
                    semanticLabel:
                        '${widget.title} image ${i + 1} of ${images.length}',
                  ),
                ),
                Positioned(
                  bottom: AppSpacing.sm,
                  left: 0,
                  right: 0,
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < images.length; i++)
                          AnimatedContainer(
                            duration: AppMotion.fast,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _page ? 18 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(
                                alpha: i == _page ? 1 : 0.6,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
