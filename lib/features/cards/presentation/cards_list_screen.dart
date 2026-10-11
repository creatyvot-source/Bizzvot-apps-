import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utilities/validators.dart';
import '../../../shared/models/card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/share_service.dart';
import '../domain/card_filters.dart';
import 'cards_providers.dart';
import 'widgets/card_chips.dart';
import 'widgets/share_helpers.dart';

/// Owner "Cards" tab: every card in the organization with search, status
/// filter and bulk QR export.
class CardsListScreen extends ConsumerStatefulWidget {
  const CardsListScreen({super.key});

  @override
  ConsumerState<CardsListScreen> createState() => _CardsListScreenState();
}

class _CardsListScreenState extends ConsumerState<CardsListScreen> {
  final _search = TextEditingController();
  CardStatusFilter _filter = CardStatusFilter.all;
  bool _exporting = false;
  bool _creating = false;

  Future<void> _createCard() async {
    final input = await showDialog<({String title, String? designation})>(
      context: context,
      builder: (_) => const _NewCardDialog(),
    );
    if (input == null || !mounted) return;
    setState(() => _creating = true);
    try {
      final card = await ref
          .read(cardActionsProvider)
          .create(title: input.title, designation: input.designation);
      if (!mounted) return;
      showMessage(context, 'Card created');
      context.push(Routes.ownerCardEdit(card.id));
    } on AppException catch (e) {
      if (!mounted) return;
      if (e.kind == AppErrorKind.forbidden) {
        // e.g. "Card limit reached: max 3 card(s)".
        final upgrade = await confirmAction(
          context,
          title: 'Card limit reached',
          message: '${e.message}\n\nAdd seats to create more cards.',
          confirmLabel: 'View seats',
        );
        if (upgrade && mounted) context.push(Routes.ownerSeats);
      } else {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() => ref.refresh(cardsListProvider.future);

  Future<void> _shareAllQrCodes(BuildContext anchor) async {
    if (_exporting) return;
    final origin = shareOriginOf(anchor);
    setState(() => _exporting = true);
    try {
      final (:files, :failed) = await ref
          .read(cardActionsProvider)
          .allQrFiles();
      if (failed > 0 && mounted) {
        showMessage(
          context,
          '$failed QR code${failed == 1 ? '' : 's'} could not be downloaded.',
        );
      }
      if (files.isEmpty) {
        if (mounted) {
          showMessage(context, 'There are no QR codes to share yet.');
        }
        return;
      }
      await ref
          .read(shareServiceProvider)
          .shareFiles(files, text: 'Bizzvot card QR codes', origin: origin);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsListProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating ? null : _createCard,
        icon: const Icon(Icons.add),
        label: const Text('New card'),
      ),
      appBar: AppBar(
        title: const Text('Cards'),
        actions: [
          Builder(
            builder: (anchor) => IconButton(
              tooltip: 'Share all QR codes',
              onPressed: _exporting ? null : () => _shareAllQrCodes(anchor),
              icon: _exporting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_2),
            ),
          ),
          IconButton(
            tooltip: 'Directory visibility',
            onPressed: () => context.push(Routes.ownerVisibility),
            icon: const Icon(Icons.visibility_outlined),
          ),
        ],
      ),
      body: ContentWidth(
        child: cards.isLoading && !cards.hasValue
            ? const SkeletonList()
            : AsyncValueView<List<CardModel>>(
                value: cards,
                loadingLabel: 'Loading cards',
                onRetry: () => ref.invalidate(cardsListProvider),
                data: (all) {
                  if (all.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: LayoutBuilder(
                        builder: (context, c) => SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: c.maxHeight),
                            child: EmptyView(
                              icon: Icons.badge_outlined,
                              title: 'No cards yet',
                              message:
                                  'Create a digital card, then assign it to a staff member.',
                              action: FilledButton.icon(
                                onPressed: _creating ? null : _createCard,
                                icon: const Icon(Icons.add_card),
                                label: const Text('Create card'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  final visible = filterCards(
                    all,
                    query: _search.text,
                    status: _filter,
                  );
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: _filters(all.length, visible.length),
                        ),
                        if (visible.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: EmptyView(
                              icon: Icons.search_off,
                              title: 'No matching cards',
                              message: 'Try a different search or filter.',
                              action: OutlinedButton(
                                onPressed: () => setState(() {
                                  _search.clear();
                                  _filter = CardStatusFilter.all;
                                }),
                                child: const Text('Clear filters'),
                              ),
                            ),
                          )
                        else
                          SliverList.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) => CardListTile(
                              card: visible[i],
                              onTap: () =>
                                  context.push(Routes.ownerCard(visible[i].id)),
                            ),
                          ),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 96), // clears the FAB
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _filters(int total, int shown) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search name, designation, company',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in CardStatusFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Semantics(
              liveRegion: true,
              child: Text(
                shown == total ? '$total cards' : '$shown of $total cards',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row: avatar, name, designation, status + visibility chips.
class CardListTile extends StatelessWidget {
  const CardListTile({
    super.key,
    required this.card,
    this.onTap,
    this.leading,
    this.trailing,
  });

  final CardModel card;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      if (card.title != null &&
          card.staffName != null &&
          card.staffName != card.title)
        card.staffName,
      card.designation,
    ].whereType<String>();
    return ListTile(
      onTap: onTap,
      leading: leading ?? CardAvatar(card: card),
      title: Text(card.displayTitle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitleParts.isNotEmpty) Text(subtitleParts.join(' · ')),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              CardStatusChip(card: card),
              CardVisibilityChip(visibility: card.visibility),
            ],
          ),
        ],
      ),
      trailing:
          trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right)),
    );
  }
}

class CardAvatar extends StatelessWidget {
  const CardAvatar({super.key, required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: InitialsAvatar(name: card.displayTitle, imageUrl: card.profilePhoto),
  );
}

class _NewCardDialog extends StatefulWidget {
  const _NewCardDialog();

  @override
  State<_NewCardDialog> createState() => _NewCardDialogState();
}

class _NewCardDialogState extends State<_NewCardDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _designation = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _designation.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final d = _designation.text.trim();
    Navigator.of(context).pop((title: _title.text.trim(), designation: d.isEmpty ? null : d));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('New card'),
        scrollable: true,
        content: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _title,
                autofocus: true,
                maxLength: 200,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name on card'),
                validator: (v) => Validators.required(v, 'Name'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _designation,
                maxLength: 200,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Designation (optional)'),
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('Create')),
        ],
      );
}
