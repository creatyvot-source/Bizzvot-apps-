import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/providers.dart';
import '../../../shared/models/card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/share_service.dart';
import 'cards_providers.dart';
import 'widgets/share_helpers.dart';

/// QR code, public link and vCard sharing for one card (owner) or the
/// signed-in staff member's own card.
class CardShareScreen extends ConsumerWidget {
  const CardShareScreen({super.key, this.cardId, this.staffMode = false});

  final String? cardId;
  final bool staffMode;

  CardRef get _target => (cardId: cardId, staffMode: staffMode);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cardForProvider(_target));
    return Scaffold(
      appBar: AppBar(title: const Text('Share & QR')),
      body: ContentWidth(
        child: AsyncValueView<CardModel?>(
          value: async,
          loadingLabel: 'Loading card',
          onRetry: () => ref.invalidate(cardForProvider(_target)),
          data: (card) => card == null
              ? const EmptyView(
                  icon: Icons.badge_outlined,
                  title: 'No card to share',
                  message: 'A card has not been assigned yet.',
                )
              : _ShareBody(card: card),
        ),
      ),
    );
  }
}

class _ShareBody extends ConsumerStatefulWidget {
  const _ShareBody({required this.card});

  final CardModel card;

  @override
  ConsumerState<_ShareBody> createState() => _ShareBodyState();
}

class _ShareBodyState extends ConsumerState<_ShareBody> {
  String? _busy;

  CardModel get card => widget.card;

  String? get _link {
    if (card.slug.isEmpty) return null;
    final env = ref.read(envProvider);
    return env.publicCardUrl(card.slug);
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = _link;
    final share = ref.read(shareServiceProvider);
    final actions = ref.read(cardActionsProvider);
    final qr = ref.watch(cardQrProvider(card.id));

    return RefreshIndicator(
      onRefresh: () => ref.refresh(cardQrProvider(card.id).future),
      child: ListView(
        padding: AppSpacing.page,
        children: [
          if (!card.isActive) ...[
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('This card is disabled'),
                subtitle: const Text(
                  'Visitors will see an unavailable page until the card is active.',
                ),
                textColor: theme.colorScheme.onSecondaryContainer,
                iconColor: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(
            card.displayTitle,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280, maxHeight: 280),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                // QR codes need a light quiet zone in dark mode too.
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: AspectRatio(
                aspectRatio: 1,
                child: qr.when(
                  skipLoadingOnRefresh: true,
                  data: (bytes) => Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    semanticLabel: 'QR code that opens the card of ${card.displayTitle}',
                    errorBuilder: (_, _, _) => const _QrUnavailable(),
                  ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => _QrUnavailable(
                    onRetry: () => ref.invalidate(cardQrProvider(card.id)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (link != null) ...[
            Text('Public link', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            Card(
              child: ListTile(
                title: SelectableText(link),
                trailing: IconButton(
                  tooltip: 'Copy link',
                  icon: const Icon(Icons.copy),
                  onPressed: () => _run('copy', () async {
                    await share.copyText(link);
                    if (mounted) showMessage(this.context, 'Link copied');
                  }),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Builder(
              builder: (anchor) => FilledButton.icon(
                onPressed: _busy != null
                    ? null
                    : () {
                        final origin = shareOriginOf(anchor);
                        _run('link', () => share.shareText(
                              link,
                              subject: card.displayTitle,
                              origin: origin,
                            ));
                      },
                icon: const Icon(Icons.share),
                label: const Text('Share link'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Builder(
            builder: (anchor) => OutlinedButton.icon(
              onPressed: _busy != null || !qr.hasValue
                  ? null
                  : () {
                      final origin = shareOriginOf(anchor);
                      _run('qr', () async {
                        final file = await actions.qrFile(card);
                        await share.shareFiles([file], text: link, origin: origin);
                      });
                    },
              icon: _busy == 'qr' ? const _Spinner() : const Icon(Icons.qr_code_2),
              label: const Text('Share QR image'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (card.vcardEnabled)
            Builder(
              builder: (anchor) => OutlinedButton.icon(
                onPressed: _busy != null
                    ? null
                    : () {
                        final origin = shareOriginOf(anchor);
                        _run('vcard', () async {
                          final file = await actions.vcardFile(card);
                          await share.shareFiles([file], origin: origin);
                        });
                      },
                icon: _busy == 'vcard' ? const _Spinner() : const Icon(Icons.contact_page_outlined),
                label: const Text('Share / save contact (vCard)'),
              ),
            )
          else
            Text(
              'Save contact (vCard) is turned off for this card.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Anyone with this link or QR code can open the card while it is active, '
            'even if it is hidden from the people directory.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}

class _QrUnavailable extends StatelessWidget {
  const _QrUnavailable({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2, size: 48, color: Colors.black38),
            const Text(
              'QR code unavailable',
              style: TextStyle(color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: AppColors.brand),
                child: const Text('Try again'),
              ),
          ],
        ),
      );
}
