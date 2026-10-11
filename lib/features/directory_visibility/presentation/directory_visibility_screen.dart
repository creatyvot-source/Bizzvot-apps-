import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/models/card.dart';
import '../../../shared/models/organization.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../cards/presentation/cards_list_screen.dart' show CardAvatar;
import '../../cards/presentation/cards_providers.dart';
import '../../cards/presentation/widgets/card_chips.dart';
import '../../cards/presentation/widgets/editor_widgets.dart' show ComingSoonNote;
import '../domain/visibility_rules.dart';
import 'directory_visibility_providers.dart';

/// Owner: organization people-directory setting + per-card visibility.
class DirectoryVisibilityScreen extends ConsumerStatefulWidget {
  const DirectoryVisibilityScreen({super.key});

  @override
  ConsumerState<DirectoryVisibilityScreen> createState() =>
      _DirectoryVisibilityScreenState();
}

class _DirectoryVisibilityScreenState
    extends ConsumerState<DirectoryVisibilityScreen> {
  /// Optimistic directory value while the PATCH is in flight.
  DirectoryVisibility? _pendingOrg;
  final _pendingCards = <String, CardVisibility>{};
  final _selected = <String>{};
  bool _selecting = false;

  /// Non-null while a bulk update runs: (done, total).
  (int, int)? _bulk;

  bool get _locked => _bulk != null;

  Future<void> _refresh() async {
    ref
      ..invalidate(directoryProfileProvider)
      ..invalidate(cardsListProvider);
    await Future.wait([
      ref.read(directoryProfileProvider.future),
      ref.read(cardsListProvider.future),
    ]).catchError((_) => const <Object>[]);
  }

  Future<void> _setOrg(DirectoryVisibility value) async {
    if (_pendingOrg != null) return;
    if (value == DirectoryVisibility.private) {
      final ok = await confirmAction(
        context,
        title: 'Hide the people directory?',
        message:
            'Your public people directory will stop listing any cards. '
            'Direct card links and QR codes keep working for active cards.',
        confirmLabel: 'Hide directory',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _pendingOrg = value);
    try {
      await ref.read(directoryActionsProvider).setDirectoryVisibility(value);
      await ref.read(directoryProfileProvider.future);
      if (mounted) {
        showMessage(
          context,
          value == DirectoryVisibility.public
              ? 'People directory is public'
              : 'People directory is hidden',
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _pendingOrg = null);
    }
  }

  Future<void> _setCard(CardModel card, CardVisibility value) async {
    if (value == card.visibility || _pendingCards.containsKey(card.id)) return;
    setState(() => _pendingCards[card.id] = value);
    try {
      await ref
          .read(directoryActionsProvider)
          .setCardVisibility(card.id, value);
      await ref.read(cardsListProvider.future);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _pendingCards.remove(card.id));
    }
  }

  Future<void> _bulkApply(CardVisibility value) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final verb = switch (value) {
      CardVisibility.public => 'Make ${ids.length} cards public?',
      CardVisibility.private => 'Make ${ids.length} cards private?',
      CardVisibility.inherit => 'Set ${ids.length} cards to inherit?',
    };
    final ok = await confirmAction(
      context,
      title: ids.length == 1 ? verb.replaceFirst('1 cards', '1 card') : verb,
      message: '${value.label}: ${_explain(value)}',
      confirmLabel: 'Apply',
    );
    if (!ok || !mounted) return;
    setState(() => _bulk = (0, ids.length));
    final result = await ref
        .read(directoryActionsProvider)
        .bulkSetVisibility(
          ids,
          value,
          onProgress: (done, total) {
            if (mounted) setState(() => _bulk = (done, total));
          },
        );
    if (!mounted) return;
    setState(() {
      _bulk = null;
      _selected
        ..clear()
        ..addAll(result.failed.keys);
      _selecting = result.hasFailures;
    });
    if (!result.hasFailures) {
      showMessage(
        context,
        'Updated ${result.succeeded.length} card${result.succeeded.length == 1 ? '' : 's'}',
      );
      return;
    }
    final firstError = result.failed.values.first;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.error_outline),
        title: const Text('Some cards were not updated'),
        content: Text(
          '${result.succeeded.length} of ${result.total} cards were updated. '
          '${result.failed.length} failed: $firstError\n\n'
          'The cards that failed are still selected so you can try again.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static String _explain(CardVisibility v) => switch (v) {
    CardVisibility.inherit => 'listed only when the organization directory is public and the card is active.',
    CardVisibility.public =>
      'listed when active, unless the organization directory is private.',
    CardVisibility.private =>
      'never listed in the directory. Direct links and QR codes still work.',
  };

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(directoryAvailableProvider)) return const _UnavailableView();
    final profile = ref.watch(directoryProfileProvider);
    final cards = ref.watch(cardsListProvider);
    final directoryEnabled = ref
        .watch(currentConfigProvider)
        .isEnabled(Flags.directory);
    final org =
        _pendingOrg ??
        profile.value?.directoryVisibility ??
        DirectoryVisibility.public;
    final slug = profile.value?.slug;
    final canPreview = directoryEnabled && slug != null && slug.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Directory visibility'),
        actions: [
          if (canPreview)
            IconButton(
              tooltip: 'Preview directory',
              onPressed: () => context.push(Routes.publicDirectory(slug)),
              icon: const Icon(Icons.open_in_new),
            ),
        ],
      ),
      body: ContentWidth(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: AppSpacing.page,
                sliver: SliverList.list(
                  children: [
                    _orgCard(profile, org),
                    const SizedBox(height: AppSpacing.md),
                    const _RulesCard(),
                    if (canPreview) ...[
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.push(Routes.publicDirectory(slug)),
                        icon: const Icon(Icons.travel_explore),
                        label: const Text('Preview directory as a visitor'),
                      ),
                    ],
                    SectionHeader(
                      'Cards',
                      subtitle: 'Choose who appears in the directory.',
                      action:
                          cards.hasValue && (cards.value?.isNotEmpty ?? false)
                          ? TextButton(
                              onPressed: _locked
                                  ? null
                                  : () => setState(() {
                                      _selecting = !_selecting;
                                      _selected.clear();
                                    }),
                              child: Text(_selecting ? 'Done' : 'Select'),
                            )
                          : null,
                    ),
                    if (_bulk != null)
                      _BulkProgress(done: _bulk!.$1, total: _bulk!.$2),
                    if (_selecting && cards.hasValue)
                      _selectionBar(cards.value!),
                  ],
                ),
              ),
              ..._cardSlivers(cards, org),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _orgCard(
    AsyncValue<OrganizationProfile> profile,
    DirectoryVisibility org,
  ) {
    if (profile.hasError && !profile.hasValue) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('Directory setting could not be loaded'),
          trailing: TextButton(
            onPressed: () => ref.invalidate(directoryProfileProvider),
            child: const Text('Retry'),
          ),
        ),
      );
    }
    final loading = !profile.hasValue;
    final public = org == DirectoryVisibility.public;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(
              public ? Icons.groups_outlined : Icons.lock_outline,
            ),
            title: const Text('Show people directory'),
            subtitle: Text(
              public
                  ? 'Public: eligible active cards are listed on your organization’s directory page.'
                  : 'Private: the directory lists no one, whatever each card’s setting.',
            ),
            value: public,
            onChanged: loading || _pendingOrg != null || _locked
                ? null
                : (v) => _setOrg(
                    v
                        ? DirectoryVisibility.public
                        : DirectoryVisibility.private,
                  ),
          ),
          if (_pendingOrg != null || loading) const LinearProgressIndicator(),
        ],
      ),
    );
  }

  Widget _selectionBar(List<CardModel> all) {
    final allSelected = _selected.length == all.length;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      '${_selected.length} selected',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _locked
                      ? null
                      : () => setState(() {
                          if (allSelected) {
                            _selected.clear();
                          } else {
                            _selected.addAll(all.map((c) => c.id));
                          }
                        }),
                  child: Text(allSelected ? 'Clear' : 'Select all'),
                ),
              ],
            ),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final (v, label, icon) in const [
                  (CardVisibility.public, 'Make public', Icons.public),
                  (CardVisibility.private, 'Make private', Icons.lock_outline),
                  (
                    CardVisibility.inherit,
                    'Inherit',
                    Icons.account_tree_outlined,
                  ),
                ])
                  FilledButton.tonalIcon(
                    onPressed: _selected.isEmpty || _locked
                        ? null
                        : () => _bulkApply(v),
                    icon: Icon(icon),
                    label: Text(label),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _cardSlivers(
    AsyncValue<List<CardModel>> cards,
    DirectoryVisibility org,
  ) {
    if (!cards.hasValue) {
      if (cards.hasError) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorView(
              error: cards.error!,
              onRetry: () => ref.invalidate(cardsListProvider),
            ),
          ),
        ];
      }
      return const [SliverFillRemaining(child: SkeletonList(count: 4))];
    }
    final list = cards.value!;
    if (list.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyView(
            icon: Icons.badge_outlined,
            title: 'No cards yet',
            message: 'Cards appear here once you add staff members.',
          ),
        ),
      ];
    }
    return [
      SliverList.separated(
        itemCount: list.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final card = list[i];
          final pending = _pendingCards[card.id];
          final visibility = pending ?? card.visibility;
          final status = directoryStatusText(
            org: org,
            card: visibility,
            cardActive: card.isActive,
          );
          final selected = _selected.contains(card.id);
          return ListTile(
            onTap: _selecting && !_locked
                ? () => setState(
                    () => selected
                        ? _selected.remove(card.id)
                        : _selected.add(card.id),
                  )
                : null,
            selected: selected,
            leading: _selecting
                ? Checkbox(
                    value: selected,
                    onChanged: _locked
                        ? null
                        : (v) => setState(
                            () => v == true
                                ? _selected.add(card.id)
                                : _selected.remove(card.id),
                          ),
                    semanticLabel: 'Select ${card.displayTitle}',
                  )
                : CardAvatar(card: card),
            title: Text(card.displayTitle),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    CardStatusChip(card: card),
                    CardVisibilityChip(visibility: visibility),
                  ],
                ),
              ],
            ),
            trailing: pending != null
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : PopupMenuButton<CardVisibility>(
                    tooltip: 'Change visibility for ${card.displayTitle}',
                    enabled: !_locked && !_selecting,
                    initialValue: visibility,
                    onSelected: (v) => _setCard(card, v),
                    icon: const Icon(Icons.tune),
                    itemBuilder: (_) => [
                      for (final v in CardVisibility.values)
                        CheckedPopupMenuItem(
                          value: v,
                          checked: v == visibility,
                          child: Text(v.label),
                        ),
                    ],
                  ),
          );
        },
      ),
    ];
  }
}

class _BulkProgress extends StatelessWidget {
  const _BulkProgress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(liveRegion: true, child: Text('Updating $done of $total…')),
        const SizedBox(height: AppSpacing.xs),
        LinearProgressIndicator(
          value: total == 0 ? null : done / total,
          semanticsLabel: 'Bulk update progress',
        ),
      ],
    ),
  );
}

class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const rules = <(IconData, String)>[
      (
        Icons.lock_outline,
        'A private organization directory wins: no card is listed, even cards set to Public.',
      ),
      (
        Icons.visibility_off_outlined,
        'A card set to Private is never listed in the directory.',
      ),
      (
        Icons.account_tree_outlined,
        'Inherit and Public cards are listed when the directory is public and the card is active.',
      ),
      (
        Icons.qr_code_2,
        'Hiding a card from the directory does not block its direct link or QR code. Active cards stay reachable by anyone who has the link.',
      ),
    ];
    return Card(
      child: Padding(
        padding: AppSpacing.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'How visibility works',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final (icon, text) in rules)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(text, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shown while the backend has no `directoryVisibility` / card `visibility`
/// fields: explains the rules without pretending to save anything.
class _UnavailableView extends StatelessWidget {
  const _UnavailableView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Directory visibility')),
      body: ContentWidth(
        child: ListView(
          padding: AppSpacing.page,
          children: [
            const ComingSoonNote(
              message: 'Coming soon: a public people directory for your '
                  'organization, with per-card visibility controls.',
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.qr_code_2),
                title: const Text('Sharing works today'),
                subtitle: Text(
                  'Every active card can already be opened by its link or QR code. '
                  'Share them from each card’s Share & QR screen.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const _RulesCard(),
          ],
        ),
      ),
    );
  }
}
