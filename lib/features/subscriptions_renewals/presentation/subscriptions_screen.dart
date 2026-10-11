import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../shared/widgets/state_views.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/formatting.dart';
import '../../catalog/presentation/common/commerce_widgets.dart';
import '../../catalog/presentation/common/paged_list.dart';
import 'subscriptions_providers.dart';

StatusTone toneForSubscription(SubscriptionStatus s) => switch (s) {
      SubscriptionStatus.active || SubscriptionStatus.trialing => StatusTone.success,
      SubscriptionStatus.pending => StatusTone.info,
      SubscriptionStatus.pastDue || SubscriptionStatus.gracePeriod => StatusTone.warning,
      SubscriptionStatus.expired => StatusTone.danger,
      SubscriptionStatus.cancelled || SubscriptionStatus.unknown => StatusTone.neutral,
    };

class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(subscriptionsListProvider);
    final notifier = ref.read(subscriptionsListProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Subscriptions & renewals')),
      body: ContentWidth(
        child: PagedListView<Subscription>(
          value: value,
          onRefresh: notifier.refresh,
          onLoadMore: notifier.loadMore,
          empty: EmptyView(
            icon: Icons.autorenew,
            title: 'No subscriptions',
            message: 'Buy seats to start a subscription for your organization.',
            action: FilledButton(
              onPressed: () => context.push(Routes.ownerSeats),
              child: const Text('Buy seats'),
            ),
          ),
          itemBuilder: (context, s) {
            final when = s.status == SubscriptionStatus.gracePeriod && s.graceUntil != null
                ? 'Grace period ends ${formatDate(s.graceUntil)}'
                : s.cancelAtPeriodEnd
                    ? 'Ends ${formatDate(s.currentPeriodEnd)}'
                    : s.nextRenewalAt != null
                        ? 'Renews ${formatDate(s.nextRenewalAt)}'
                        : null;
            return ListTile(
              onTap: () => context.push(Routes.ownerSubscription(s.id)),
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(s.title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (s.quantity != null) Text('${s.quantity} seats'),
                  ?when == null ? null : Text(when),
                  const SizedBox(height: 4),
                  StatusChip(s.statusLabel, tone: toneForSubscription(s.status)),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
            );
          },
        ),
      ),
    );
  }
}
