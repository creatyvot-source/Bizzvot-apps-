import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/auth/auth_user.dart';
import '../../../core/auth/session_controller.dart';
import '../../../shared/models/card.dart';
import '../../../shared/widgets/state_views.dart';
import 'cards_providers.dart';
import 'widgets/card_chips.dart';
import 'widgets/card_preview.dart';

/// Staff home tab: the signed-in staff member's assigned card.
class MyCardScreen extends ConsumerWidget {
  const MyCardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(staffCardProvider);
    final permissions =
        ref.watch(currentUserProvider.select((u) => u?.permissions)) ?? StaffPermissions.none;

    Future<void> refresh() async {
      // Permissions may have changed server-side as well.
      await ref.read(sessionControllerProvider.notifier).refreshUser();
      await ref.refresh(staffCardProvider.future);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My card')),
      body: ContentWidth(
        child: AsyncValueView<CardModel?>(
          value: async,
          loadingLabel: 'Loading your card',
          onRetry: () => ref.invalidate(staffCardProvider),
          data: (card) => RefreshIndicator(
            onRefresh: refresh,
            child: card == null
                ? LayoutBuilder(
                    builder: (context, c) => SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: c.maxHeight),
                        child: const EmptyView(
                          icon: Icons.badge_outlined,
                          title: 'No card assigned yet',
                          message:
                              'Your organization owner has not assigned a digital card to you. '
                              'Pull down to refresh once they have.',
                        ),
                      ),
                    ),
                  )
                : _MyCardBody(card: card, permissions: permissions),
          ),
        ),
      ),
    );
  }
}

class _MyCardBody extends StatelessWidget {
  const _MyCardBody({required this.card, required this.permissions});

  final CardModel card;
  final StaffPermissions permissions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canEdit = permissions.editCard || permissions.manageLinks;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppSpacing.page,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [CardStatusChip(card: card)],
        ),
        if (!card.isActive) ...[
          const SizedBox(height: AppSpacing.sm),
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              iconColor: theme.colorScheme.onSecondaryContainer,
              textColor: theme.colorScheme.onSecondaryContainer,
              title: const Text('Your card is not active'),
              subtitle: Text(
                card.disabledByBilling
                    ? 'It was disabled for billing reasons. Contact your organization owner.'
                    : 'Visitors cannot open it yet. Contact your organization owner to activate it.',
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        CardPreview(card: card),
        const SizedBox(height: AppSpacing.lg),
        if (canEdit) ...[
          FilledButton.icon(
            onPressed: () => context.push(Routes.staffCardEdit),
            icon: const Icon(Icons.edit_outlined),
            label: Text(permissions.editCard ? 'Edit card' : 'Edit links'),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        OutlinedButton.icon(
          onPressed: () => context.push(Routes.staffCardShare),
          icon: const Icon(Icons.qr_code_2),
          label: const Text('Share & QR'),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (card.slug.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.publicCard(card.slug)),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Preview public card'),
          ),
        if (!canEdit) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Editing is managed by your organization owner.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
