import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../catalog/domain/formatting.dart';
import '../../catalog/presentation/common/feature_gate.dart';
import '../../catalog/presentation/common/paged_list.dart';
import '../domain/app_notification.dart';
import 'notifications_providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);
    final unread = ref.watch(unreadNotificationsCountProvider);

    Future<void> open(AppNotification n) async {
      final route = n.route;
      if (!n.isRead) {
        try {
          await notifier.markRead(n);
        } catch (e) {
          if (context.mounted) showError(context, e);
        }
      }
      if (route != null && context.mounted) context.push(route);
    }

    return FeatureGate(
      flag: Flags.notifications,
      title: 'Notifications',
      unavailableTitle: 'Notifications are not available right now',
      unavailableMessage: 'Please check back later.',
      child: Scaffold(
        appBar: AppBar(
          title: Text(unread > 0 ? 'Notifications ($unread)' : 'Notifications'),
        ),
        body: ContentWidth(
          child: PagedListView<AppNotification>(
            value: value,
            onRefresh: notifier.refresh,
            onLoadMore: notifier.loadMore,
            empty: const EmptyView(
              icon: Icons.notifications_none,
              title: 'You’re all caught up',
              message:
                  'Order, payment, renewal and review updates appear here.',
            ),
            itemBuilder: (context, n) =>
                _NotificationTile(n: n, onTap: () => open(n)),
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap});
  final AppNotification n;
  final VoidCallback onTap;

  static IconData _icon(NotificationKind k) => switch (k) {
    NotificationKind.order => Icons.receipt_long_outlined,
    NotificationKind.payment => Icons.payments_outlined,
    NotificationKind.invoice => Icons.description_outlined,
    NotificationKind.subscription => Icons.autorenew,
    NotificationKind.billing => Icons.credit_card_outlined,
    NotificationKind.review => Icons.reviews_outlined,
    NotificationKind.card => Icons.badge_outlined,
    NotificationKind.staff => Icons.group_outlined,
    NotificationKind.other => Icons.notifications_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = !n.isRead;
    return Semantics(
      label: unread ? 'Unread' : null,
      child: ListTile(
        onTap: onTap,
        tileColor: unread
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
            : null,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Icon(_icon(n.kind), color: theme.colorScheme.primary),
        ),
        title: Text(
          n.title,
          style: unread ? const TextStyle(fontWeight: FontWeight.w700) : null,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (n.body != null) Text(n.body!),
            if (n.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text(
                  formatDateTime(n.createdAt),
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
        trailing: unread
            ? ExcludeSemantics(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : (n.route != null ? const Icon(Icons.chevron_right) : null),
      ),
    );
  }
}
