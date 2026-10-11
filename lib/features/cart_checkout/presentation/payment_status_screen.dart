import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/presentation/common/commerce_widgets.dart';
import '../../catalog/presentation/common/feature_gate.dart';
import 'cart_checkout_providers.dart';

/// Shows the payment state of an order as reported by `GET /orders/:id`.
/// Polls with bounded back-off; re-checks when the app returns from the
/// browser. Nothing here marks an order paid on the client.
class PaymentStatusScreen extends ConsumerStatefulWidget {
  const PaymentStatusScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<PaymentStatusScreen> createState() =>
      _PaymentStatusScreenState();
}

class _PaymentStatusScreenState extends ConsumerState<PaymentStatusScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () =>
          ref.read(paymentStatusProvider(widget.orderId).notifier).checkNow(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    try {
      final session = await ref
          .read(paymentStatusProvider(widget.orderId).notifier)
          .retryPayment();
      if (!mounted) return;
      await openHostedCheckout(context, ref, session);
    } catch (e) {
      if (!mounted) return;
      final ex = AppException.from(e);
      showError(context, ex);
      // 409: payment already in progress/complete — re-read the truth.
      if (ex.kind == AppErrorKind.conflict) {
        ref.read(paymentStatusProvider(widget.orderId).notifier).poll();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(paymentStatusProvider(widget.orderId));
    final checkoutUri = ref.watch(
      checkoutControllerProvider.select((c) => c.checkoutUris[widget.orderId]),
    );
    final order = s.order;
    final outcome = s.outcome;

    Widget body;
    if (order == null && s.error != null) {
      body = ErrorView(
        error: s.error!,
        onRetry: () =>
            ref.read(paymentStatusProvider(widget.orderId).notifier).poll(),
      );
    } else if (order == null) {
      body = const LoadingView(label: 'Checking your payment…');
    } else {
      body = _StatusBody(
        order: order,
        state: s,
        checkoutUri: checkoutUri,
        onRetry: _retry,
        onCheckAgain: () =>
            ref.read(paymentStatusProvider(widget.orderId).notifier).poll(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment status'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => context.go(
              outcome == PaymentOutcome.paid
                  ? Routes.ownerOrders
                  : Routes.ownerShop,
            ),
          ),
        ],
      ),
      body: ContentWidth(child: body),
    );
  }
}

class _StatusBody extends StatelessWidget {
  const _StatusBody({
    required this.order,
    required this.state,
    required this.onRetry,
    required this.onCheckAgain,
    this.checkoutUri,
  });

  final Order order;
  final PaymentStatusState state;
  final Uri? checkoutUri;
  final Future<void> Function() onRetry;
  final VoidCallback onCheckAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = order.paymentOutcome;
    final stillProcessing = state.timedOut && !outcome.isTerminal;
    final (icon, color, title, message) = switch (outcome) {
      _ when stillProcessing => (
        Icons.schedule,
        AppColors.warning,
        'Still processing',
        'Your payment is taking longer than usual to confirm. We’ll notify you as '
            'soon as it’s confirmed — you can safely leave this screen.',
      ),
      PaymentOutcome.pending => (
        Icons.hourglass_top,
        theme.colorScheme.primary,
        'Waiting for payment',
        'Complete the payment on the secure page. This screen updates automatically.',
      ),
      PaymentOutcome.processing => (
        Icons.sync,
        theme.colorScheme.primary,
        'Confirming payment',
        'We’re confirming your payment with the bank. This usually takes a few seconds.',
      ),
      PaymentOutcome.paid => (
        Icons.check_circle,
        AppColors.success,
        'Payment confirmed',
        'Thank you! Your order is confirmed. We’ll keep you updated as it progresses.',
      ),
      PaymentOutcome.failed => (
        Icons.error,
        theme.colorScheme.error,
        'Payment failed',
        order.failureReason ?? 'The payment didn’t go through. No money was taken, or it will be refunded automatically.',
      ),
      PaymentOutcome.cancelled => (
        Icons.cancel,
        theme.colorScheme.error,
        'Order cancelled',
        'This order was cancelled. You can place a new order from the shop.',
      ),
      PaymentOutcome.expired => (
        Icons.timer_off,
        theme.colorScheme.error,
        'Payment window expired',
        'The payment wasn’t completed in time. Please try again.',
      ),
      PaymentOutcome.refunded => (
        Icons.currency_exchange,
        theme.colorScheme.primary,
        'Refunded',
        'This order has been refunded.',
      ),
    };
    final waiting = !outcome.isTerminal && !stillProcessing;
    final canRetry =
        (outcome == PaymentOutcome.failed ||
            outcome == PaymentOutcome.expired ||
            outcome == PaymentOutcome.pending &&
                (checkoutUri == null || !state.polling)) &&
        order.retryPaymentAllowed;

    return ListView(
      padding: AppSpacing.page,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          liveRegion: true,
          child: Column(
            children: [
              if (waiting)
                const SizedBox.square(
                  dimension: 72,
                  child: CircularProgressIndicator(strokeWidth: 5),
                )
              else
                Icon(icon, size: 72, color: color),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Card(
          child: Padding(
            padding: AppSpacing.page,
            child: Column(
              children: [
                InfoRow.text('Order', '#${order.displayNumber}'),
                InfoRow(
                  label: 'Payment',
                  value: StatusChip(
                    order.paymentStatusLabel,
                    tone: switch (outcome) {
                      PaymentOutcome.paid => StatusTone.success,
                      PaymentOutcome.failed ||
                      PaymentOutcome.cancelled ||
                      PaymentOutcome.expired => StatusTone.danger,
                      _ => StatusTone.info,
                    },
                  ),
                ),
                InfoRow.money('Total', order.total, emphasize: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (stillProcessing || state.error != null && !outcome.isTerminal)
          OutlinedButton.icon(
            onPressed: onCheckAgain,
            icon: const Icon(Icons.refresh),
            label: const Text('Check again'),
          ),
        if (outcome == PaymentOutcome.pending && checkoutUri != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _ReopenButton(uri: checkoutUri!),
        ],
        if (canRetry) ...[
          const SizedBox(height: AppSpacing.sm),
          BusyButton(
            label: outcome == PaymentOutcome.pending ? 'Pay now' : 'Retry payment',
            icon: Icons.replay,
            onPressed: onRetry,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => context.push(Routes.ownerOrder(order.id)),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('View order details'),
        ),
        if (outcome == PaymentOutcome.paid && order.invoiceId != null) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () =>
                context.push(Routes.ownerInvoice(order.invoiceId!)),
            icon: const Icon(Icons.description_outlined),
            label: const Text('View invoice'),
          ),
        ],
        if (outcome == PaymentOutcome.paid && order.subscriptionId != null) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () =>
                context.push(Routes.ownerSubscription(order.subscriptionId!)),
            icon: const Icon(Icons.autorenew),
            label: const Text('View subscription'),
          ),
        ],
      ],
    );
  }
}

class _ReopenButton extends ConsumerWidget {
  const _ReopenButton({required this.uri});
  final Uri uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) => OutlinedButton.icon(
    onPressed: () => openHostedCheckout(
      context,
      ref,
      PaymentSession(checkoutUrl: uri.toString()),
    ),
    icon: const Icon(Icons.open_in_new),
    label: const Text('Open payment page'),
  );
}
