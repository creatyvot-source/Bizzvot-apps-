import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../catalog/data/link_launcher.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/physical_models.dart';
import '../../catalog/presentation/common/commerce_widgets.dart';
import '../../catalog/presentation/common/cooldown.dart';
import '../../catalog/presentation/common/feature_gate.dart';
import 'cart_checkout_providers.dart';
import 'widgets/address_form.dart';
import 'widgets/quote_summary.dart';

/// Review the authoritative quote, capture delivery + GST details, accept
/// terms and place the order. Payment happens on the hosted checkout page;
/// the result is always confirmed on the payment status screen.
///
/// App-store policy (plan §12.6): items classed [PaymentPolicy.inAppDigital]
/// are blocked here until an approved in-app purchase flow exists.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen>
    with CooldownState<CheckoutScreen> {
  bool _termsAccepted = false;
  bool _placing = false;

  @override
  void initState() {
    super.initState();
    // Pre-select the most recent saved address.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || ref.read(checkoutDetailsProvider).address != null) return;
      try {
        final saved = await ref.read(addressBookProvider.future);
        if (!mounted || saved.isEmpty) return;
        if (ref.read(checkoutDetailsProvider).address == null) {
          ref.read(checkoutDetailsProvider.notifier).setAddress(saved.first);
        }
      } catch (_) {}
    });
  }

  Future<void> _placeOrder(Quote quote) async {
    if (_placing) return;
    setState(() => _placing = true);
    final details = ref.read(checkoutDetailsProvider);
    try {
      final result = await ref
          .read(checkoutControllerProvider.notifier)
          .placeOrder(
            quote: quote,
            lines: ref.read(cartProvider),
            shippingAddress: details.address,
            gst: details.gst.isEmpty ? null : details.gst,
          );
      if (!mounted) return;
      await openHostedCheckout(context, ref, result.session);
      if (!mounted) return;
      context.go(Routes.ownerPayment(result.orderId));
    } catch (e) {
      if (!mounted) return;
      final ex = AppException.from(e);
      if (!applyRateLimit(ex)) {
        showError(context, ex);
        // Prices or availability may have changed: fetch a fresh quote.
        if (ex.kind == AppErrorKind.conflict ||
            ex.kind == AppErrorKind.validation) {
          ref.invalidate(checkoutQuoteProvider);
        }
      } else {
        showError(context, ex);
      }
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Future<void> _editAddress({ShippingAddress? initial}) async {
    final r = await showAddressForm(context, initial: initial);
    if (r == null || !mounted) return;
    ref.read(checkoutDetailsProvider.notifier).setAddress(r.address);
    if (r.save) await ref.read(addressBookProvider.notifier).save(r.address);
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(cartProvider);
    final quoteValue = ref.watch(checkoutQuoteProvider);
    final details = ref.watch(checkoutDetailsProvider);
    final quote = quoteValue.value;
    final needsShipping =
        ref.watch(cartNeedsShippingProvider) ||
        (quote?.requiresShipping ?? false);
    final inAppBlocked =
        quote?.blocksInApp(lines) ??
        lines.any((l) => !l.checkoutAllowed);
    final personalizationIssue = lines
        .map((l) => l.personalizationProblem)
        .whereType<String>()
        .firstOrNull;
    final missingAddress = needsShipping && details.address == null;

    final blockReason = inAppBlocked
        ? 'Purchase not available in app yet'
        : personalizationIssue ??
              (missingAddress
                  ? 'Add a delivery address'
                  : quote == null
                  ? null
                  : !quote.canCheckout
                  ? (quote.hasUnavailable
                        ? 'Some items are unavailable'
                        : 'Price unavailable')
                  : !_termsAccepted
                  ? 'Accept the terms to continue'
                  : coolingDown
                  ? 'Please wait a moment and try again'
                  : null);
    final canPlace =
        quote != null &&
        !quoteValue.isLoading &&
        blockReason == null &&
        !_placing;

    return FeatureGate(
      flag: Flags.shop,
      title: 'Checkout',
      child: Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        bottomNavigationBar: lines.isEmpty
            ? null
            : TotalBar(
                total: quoteValue.isLoading ? null : quote?.total,
                caption: quoteValue.isLoading ? 'Updating price…' : blockReason,
                action: FilledButton.icon(
                  onPressed: canPlace ? () => _placeOrder(quote) : null,
                  icon: _placing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_outline),
                  label: Text(
                    _placing ? 'Placing order…' : 'Place order & pay',
                  ),
                ),
              ),
        body: lines.isEmpty
            ? EmptyView(
                icon: Icons.shopping_bag_outlined,
                title: 'Your cart is empty',
                action: FilledButton(
                  onPressed: () => context.go(Routes.ownerShop),
                  child: const Text('Browse shop'),
                ),
              )
            : ContentWidth(
                child: RefreshIndicator(
                  onRefresh: () => ref.refresh(checkoutQuoteProvider.future),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: AppSpacing.page,
                    children: [
                      if (inAppBlocked) ...[
                        const NoticeCard(
                          title: 'Purchase not available in app yet',
                          message:
                              'One or more items are digital features that can’t be '
                              'bought in the app yet. Remove them to continue, or contact us.',
                          tone: StatusTone.warning,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (personalizationIssue != null) ...[
                        NoticeCard(
                          title: 'Personalisation needed',
                          message:
                              '$personalizationIssue. Open your cart to finish.',
                          tone: StatusTone.warning,
                          icon: Icons.nfc,
                          action: TextButton(
                            onPressed: () => context.pop(),
                            child: const Text('Back to cart'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (needsShipping) _AddressSection(onEdit: _editAddress),
                      _GstSection(details: details),
                      const SizedBox(height: AppSpacing.md),
                      quoteValue.when(
                        skipLoadingOnRefresh: false,
                        skipLoadingOnReload: false,
                        loading: () => const Padding(
                          padding: EdgeInsets.all(AppSpacing.xl),
                          child: LoadingView(label: 'Getting the latest price'),
                        ),
                        error: (e, _) => ErrorView(
                          error: e,
                          onRetry: () => ref.invalidate(checkoutQuoteProvider),
                        ),
                        data: (q) => q == null
                            ? const SizedBox.shrink()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (q.hasUnavailable) ...[
                                    const NoticeCard(
                                      title: 'Some items are unavailable',
                                      message: 'Go back to your cart to remove them.',
                                      tone: StatusTone.warning,
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                  ],
                                  QuoteSummary(
                                    quote: q,
                                    shippingPending:
                                        needsShipping &&
                                        details.address == null,
                                  ),
                                  if (q.expiresAt != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: AppSpacing.sm,
                                      ),
                                      child: Text(
                                        'Prices held until ${TimeOfDay.fromDateTime(q.expiresAt!).format(context)}.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                  _TermsTile(
                                    value: _termsAccepted,
                                    termsUrl: q.termsUrl,
                                    onChanged: (v) =>
                                        setState(() => _termsAccepted = v),
                                  ),
                                  const _SecureNote(),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _AddressSection extends ConsumerWidget {
  const _AddressSection({required this.onEdit});
  final Future<void> Function({ShippingAddress? initial}) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(checkoutDetailsProvider).address;
    final saved =
        ref.watch(addressBookProvider).value ?? const <ShippingAddress>[];
    final theme = Theme.of(context);
    final others = saved
        .where((a) => a.dedupeKey != selected?.dedupeKey)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          'Delivery address',
          subtitle: 'Shipping is calculated from this address',
        ),
        if (selected == null)
          OutlinedButton.icon(
            onPressed: () => onEdit(),
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Add delivery address'),
          )
        else
          Card(
            child: ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(selected.name),
              subtitle: Text('${selected.singleLine}\n${selected.phone}'),
              isThreeLine: true,
              trailing: TextButton(
                onPressed: () => onEdit(initial: selected),
                child: const Text('Edit'),
              ),
            ),
          ),
        if (others.isNotEmpty || selected != null)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Saved addresses (${saved.length})',
              style: theme.textTheme.bodyMedium,
            ),
            children: [
              for (final a in others)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.home_outlined),
                  title: Text(a.name),
                  subtitle: Text(a.singleLine),
                  onTap: () =>
                      ref.read(checkoutDetailsProvider.notifier).setAddress(a),
                  trailing: IconButton(
                    tooltip: 'Delete saved address',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        ref.read(addressBookProvider.notifier).remove(a),
                  ),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add),
                title: const Text('Add a new address'),
                onTap: () => onEdit(),
              ),
            ],
          ),
      ],
    );
  }
}

class _GstSection extends ConsumerStatefulWidget {
  const _GstSection({required this.details});
  final CheckoutDetails details;

  @override
  ConsumerState<_GstSection> createState() => _GstSectionState();
}

class _GstSectionState extends ConsumerState<_GstSection> {
  final _form = GlobalKey<FormState>();
  late final _gstin = TextEditingController(text: widget.details.gst.gstin);
  late final _business = TextEditingController(
    text: widget.details.gst.businessName,
  );
  String? _place;

  @override
  void dispose() {
    _gstin.dispose();
    _business.dispose();
    super.dispose();
  }

  void _apply() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final g = _gstin.text.trim().toUpperCase();
    final b = _business.text.trim();
    ref
        .read(checkoutDetailsProvider.notifier)
        .setGst(
          GstDetails(
            gstin: g.isEmpty ? null : g,
            businessName: b.isEmpty ? null : b,
            placeOfSupply: _place ?? widget.details.address?.state,
          ),
        );
    FocusScope.of(context).unfocus();
    showMessage(context, 'GST details updated');
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.details.gst;
    final place =
        _place ?? current.placeOfSupply ?? widget.details.address?.state;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.receipt_long_outlined),
      title: const Text('GST invoice (optional)'),
      subtitle: Text(
        current.gstin == null
            ? 'Add your GSTIN to claim input tax credit'
            : 'GSTIN ${current.gstin}',
      ),
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                controller: _gstin,
                textCapitalization: TextCapitalization.characters,
                maxLength: 15,
                decoration: const InputDecoration(
                  labelText: 'GSTIN (optional)',
                ),
                validator: ShippingValidators.optionalGstin,
              ),
              TextFormField(
                controller: _business,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Registered business name (optional)',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: indianStates.contains(place) ? place : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Place of supply',
                  helperText: 'Usually the state of the delivery address',
                ),
                items: [
                  for (final s in indianStates)
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) => setState(() => _place = v),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: _apply,
                  child: const Text('Apply & update price'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TermsTile extends ConsumerWidget {
  const _TermsTile({
    required this.value,
    required this.onChanged,
    this.termsUrl,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? termsUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = termsUrl ?? ref.watch(currentConfigProvider).termsUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: value,
          onChanged: (v) => onChanged(v ?? false),
          title: const Text(
            'I agree to the terms of sale, delivery and refund policy, and confirm the '
            'personalisation details are correct.',
          ),
        ),
        if (url != null)
          TextButton.icon(
            onPressed: () async {
              final ok = await ref.read(linkLauncherProvider).openWeb(url);
              if (!ok && context.mounted) {
                showMessage(context, 'Couldn’t open the terms page.');
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Read the terms'),
          ),
      ],
    );
  }
}

class _SecureNote extends StatelessWidget {
  const _SecureNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'You’ll pay on a secure payment page. We confirm your payment with our '
              'server before your order is processed.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
