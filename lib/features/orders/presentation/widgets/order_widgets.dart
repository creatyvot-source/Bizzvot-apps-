import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../shared/widgets/feedback.dart';
import '../../../catalog/data/link_launcher.dart';
import '../../../catalog/domain/commerce_models.dart';
import '../../../catalog/domain/formatting.dart';
import '../../../catalog/domain/physical_models.dart';
import '../../../catalog/presentation/common/commerce_widgets.dart';

StatusTone toneForOutcome(PaymentOutcome o) => switch (o) {
      PaymentOutcome.paid => StatusTone.success,
      PaymentOutcome.failed || PaymentOutcome.cancelled || PaymentOutcome.expired => StatusTone.danger,
      PaymentOutcome.refunded => StatusTone.neutral,
      PaymentOutcome.pending || PaymentOutcome.processing => StatusTone.warning,
    };

StatusTone toneForOrder(Order o) => switch (o.status) {
      OrderStatus.completed || OrderStatus.fulfilled || OrderStatus.paid => StatusTone.success,
      OrderStatus.processing => StatusTone.info,
      OrderStatus.paymentFailed || OrderStatus.cancelled || OrderStatus.expired => StatusTone.danger,
      OrderStatus.pendingPayment || OrderStatus.draft => StatusTone.warning,
      _ => StatusTone.neutral,
    };

class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order, required this.onTap});
  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = order.lines.isEmpty
        ? null
        : order.lines.length == 1
            ? order.lines.first.title
            : '${order.lines.first.title} + ${order.lines.length - 1} more';
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        child: const Icon(Icons.receipt_long_outlined),
      ),
      title: Text('Order #${order.displayNumber}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items != null) Text(items, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(formatDate(order.createdAt)),
          const SizedBox(height: AppSpacing.xs),
          StatusChip(order.statusLabel, tone: toneForOrder(order)),
        ],
      ),
      trailing: MoneyText(order.total, style: theme.textTheme.titleSmall),
    );
  }
}

/// Placed → paid → design/proof → printing → NFC programmed → shipped →
/// delivered, with courier/AWB tracking (https links only).
class FulfilmentTimeline extends ConsumerWidget {
  const FulfilmentTimeline({super.key, required this.fulfilment, this.paid = false, this.placedAt});

  final Fulfilment fulfilment;
  final bool paid;
  final DateTime? placedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final f = fulfilment;
    bool reached(FulfilmentStep s) =>
        f.isReached(s) ||
        s == FulfilmentStep.placed ||
        (s == FulfilmentStep.paid && paid);
    final steps = FulfilmentStep.values;
    final lastReached = steps.lastWhere(reached, orElse: () => FulfilmentStep.placed);
    final tracking = f.safeTrackingUri;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(
            label: steps[i].label,
            done: reached(steps[i]),
            current: steps[i] == lastReached && steps[i] != FulfilmentStep.delivered,
            last: i == steps.length - 1,
            at: steps[i] == FulfilmentStep.placed ? (f.reached[steps[i]] ?? placedAt) : f.reached[steps[i]],
            detail: steps[i] == FulfilmentStep.shipped && (f.courier != null || f.awb != null)
                ? [f.courier, if (f.awb != null) 'AWB ${f.awb}'].whereType<String>().join(' · ')
                : null,
          ),
        if (f.note != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(f.note!, style: theme.textTheme.bodySmall),
          ),
        if (tracking != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: OutlinedButton.icon(
              onPressed: () async {
                final ok = await ref.read(linkLauncherProvider).openWeb(tracking.toString());
                if (!ok && context.mounted) showMessage(context, 'Couldn’t open the tracking page.');
              },
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Track shipment'),
            ),
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.label,
    required this.done,
    required this.current,
    required this.last,
    this.at,
    this.detail,
  });

  final String label;
  final bool done;
  final bool current;
  final bool last;
  final DateTime? at;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = done ? theme.colorScheme.primary : theme.colorScheme.outlineVariant;
    return Semantics(
      label: '$label, ${done ? 'done' : 'pending'}${at != null ? ', ${formatDate(at)}' : ''}',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  Icon(
                    done ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 22,
                    color: color,
                  ),
                  if (!last)
                    Expanded(
                      child: Container(width: 2, color: color),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: current ? FontWeight.w700 : null,
                        color: done ? null : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (at != null)
                      Text(formatDateTime(at), style: theme.textTheme.bodySmall),
                    if (detail != null) Text(detail!, style: theme.textTheme.bodySmall),
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
