import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/models/card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import 'cards_providers.dart';
import 'widgets/card_chips.dart';
import 'widgets/card_preview.dart';

/// Owner card summary with preview and actions.
class CardDetailScreen extends ConsumerStatefulWidget {
  const CardDetailScreen({super.key, required this.cardId});

  final String cardId;

  @override
  ConsumerState<CardDetailScreen> createState() => _CardDetailScreenState();
}

enum _MenuAction { delete }

class _CardDetailScreenState extends ConsumerState<CardDetailScreen> {
  bool _busy = false;

  Future<void> _setStatus(CardModel card, CardStatus status) async {
    final activating = status == CardStatus.active;
    final ok = await confirmAction(
      context,
      title: activating ? 'Activate this card?' : 'Disable this card?',
      message: activating
          ? 'Outside the trial, an active card uses one paid card slot. '
                'The card link and QR code will open for visitors.'
          : 'Visitors will no longer be able to open this card by link or QR code. '
                'You can activate it again later if a slot is available.',
      confirmLabel: activating ? 'Activate' : 'Disable',
      destructive: !activating,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(cardActionsProvider).setStatus(card.id, status);
      if (mounted) {
        showMessage(context, activating ? 'Card activated' : 'Card disabled');
      }
    } on AppException catch (e) {
      if (!mounted) return;
      final seatProblem =
          activating &&
          (e.kind == AppErrorKind.forbidden ||
              e.kind == AppErrorKind.conflict ||
              e.statusCode == 402);
      if (seatProblem) {
        setState(() => _busy = false);
        await _showSeatDialog(e.message);
      } else {
        showError(context, e);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSeatDialog(String message) async {
    final buy = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.event_seat_outlined),
        title: const Text('Card could not be activated'),
        content: Text(
          '$message\n\nActivating a card needs a free paid card slot. '
          'You can add seats from Billing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('View seats'),
          ),
        ],
      ),
    );
    if (buy == true && mounted) context.push(Routes.ownerSeats);
  }

  Future<void> _delete(CardModel card) async {
    final ok = await confirmAction(
      context,
      title: 'Delete this card?',
      message:
          'This permanently deletes "${card.displayTitle}". Its link and QR code '
          'will stop working. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(cardActionsProvider).delete(card.id);
      if (!mounted) return;
      showMessage(context, 'Card deleted');
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.ownerCards);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(cardDetailProvider(widget.cardId));
    final card = async.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(card?.displayTitle ?? 'Card'),
        actions: [
          if (card != null) ...[
            IconButton(
              tooltip: 'Edit card',
              onPressed: _busy
                  ? null
                  : () => context.push(Routes.ownerCardEdit(card.id)),
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<_MenuAction>(
              tooltip: 'More actions',
              enabled: !_busy,
              onSelected: (a) => switch (a) {
                _MenuAction.delete => _delete(card),
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: _MenuAction.delete,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_outline,
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                    title: Text(
                      'Delete card',
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: ContentWidth(
        child: AsyncValueView<CardModel>(
          value: async,
          loadingLabel: 'Loading card',
          onRetry: () => ref.invalidate(cardDetailProvider(widget.cardId)),
          data: (card) => RefreshIndicator(
            onRefresh: () =>
                ref.refresh(cardDetailProvider(widget.cardId).future),
            child: ListView(
              padding: AppSpacing.page,
              children: [
                if (_busy) const LinearProgressIndicator(),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    CardStatusChip(card: card),
                    CardVisibilityChip(visibility: card.visibility),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (card.disabledByBilling && !card.isActive) ...[
                  _BillingBanner(
                    onViewSeats: () => context.push(Routes.ownerSeats),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                CardPreview(card: card),
                const SizedBox(height: AppSpacing.md),
                _StatusAction(
                  card: card,
                  busy: _busy,
                  onChange: (s) => _setStatus(card, s),
                ),
                const SizedBox(height: AppSpacing.md),
                _ActionGrid(card: card),
                const SizedBox(height: AppSpacing.md),
                _Summary(card: card),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BillingBanner extends StatelessWidget {
  const _BillingBanner({required this.onViewSeats});

  final VoidCallback onViewSeats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: AppSpacing.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.credit_card_off_outlined,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Disabled by billing',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This card was disabled because the trial ended or the organization '
              'has more active cards than paid slots. It can only be reactivated '
              'once the server confirms a free paid card slot.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: onViewSeats,
              icon: const Icon(Icons.event_seat_outlined),
              label: const Text('Billing & seats'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusAction extends StatelessWidget {
  const _StatusAction({
    required this.card,
    required this.busy,
    required this.onChange,
  });

  final CardModel card;
  final bool busy;
  final ValueChanged<CardStatus> onChange;

  @override
  Widget build(BuildContext context) {
    if (card.isActive) {
      return OutlinedButton.icon(
        onPressed: busy ? null : () => onChange(CardStatus.disabled),
        icon: const Icon(Icons.pause_circle_outline),
        label: const Text('Disable card'),
      );
    }
    return FilledButton.icon(
      onPressed: busy ? null : () => onChange(CardStatus.active),
      icon: const Icon(Icons.play_circle_outline),
      label: const Text('Activate card'),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, VoidCallback?)>[
      (
        Icons.edit_outlined,
        'Edit',
        () => context.push(Routes.ownerCardEdit(card.id)),
      ),
      (
        Icons.qr_code_2,
        'Share & QR',
        () => context.push(Routes.ownerCardShare(card.id)),
      ),
      (
        Icons.insights_outlined,
        'Analytics',
        () => context.push(Routes.ownerCardAnalytics(card.id)),
      ),
      (
        Icons.open_in_new,
        'Preview as visitor',
        card.slug.isEmpty
            ? null
            : () => context.push(Routes.publicCard(card.slug)),
      ),
    ];
    return Card(
      child: Column(
        children: [
          for (final (icon, label, onTap) in actions)
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: const Icon(Icons.chevron_right),
              enabled: onTap != null,
              onTap: onTap,
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      if (card.staffName != null) ('Staff member', card.staffName!),
      ('Template', card.template.label),
      ('Directory visibility', card.visibility.label),
      ('Save contact (vCard)', card.vcardEnabled ? 'On' : 'Off'),
      ('Links', '${card.socialLinks.length + card.customLinks.length}'),
      ('Gallery', '${card.gallery.length} of ${CardLimits.gallery}'),
      ('Documents', '${card.pdfs.length} of ${CardLimits.pdfs}'),
      ('Videos', '${card.videos.length} of ${CardLimits.videos}'),
      if (card.viewCount != null) ('Views', '${card.viewCount}'),
      if (card.reviewCount != null) ('Reviews', '${card.reviewCount}'),
      if (card.averageRating != null)
        ('Average rating', card.averageRating!.toStringAsFixed(1)),
      if (card.updatedAt != null)
        ('Last updated', DateFormat.yMMMd().add_jm().format(card.updatedAt!)),
    ];
    return Card(
      child: Padding(
        padding: AppSpacing.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Summary', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: MergeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          k,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(child: Text(v, textAlign: TextAlign.end)),
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
