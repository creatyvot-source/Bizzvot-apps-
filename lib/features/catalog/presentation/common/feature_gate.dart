import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../shared/widgets/feedback.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/link_launcher.dart';
import '../../domain/commerce_models.dart';

/// Shows a friendly "not available" page when a server feature flag is off.
class FeatureGate extends ConsumerWidget {
  const FeatureGate({
    super.key,
    required this.flag,
    required this.title,
    required this.child,
    this.unavailableTitle = 'Shop is not available right now',
    this.unavailableMessage =
        'Please check back later. Your existing orders, '
        'invoices and subscriptions are still available from the More tab.',
  });

  final String flag;
  final String title;
  final Widget child;
  final String unavailableTitle;
  final String unavailableMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      currentConfigProvider.select((c) => c.isEnabled(flag)),
    );
    if (enabled) return child;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: EmptyView(
        icon: Icons.storefront_outlined,
        title: unavailableTitle,
        message: unavailableMessage,
      ),
    );
  }
}

/// Opens a server-approved hosted checkout page (https only). Returns true
/// when the external browser was opened. Never implies payment success.
Future<bool> openHostedCheckout(
  BuildContext context,
  WidgetRef ref,
  PaymentSession session,
) async {
  final uri = session.safeCheckoutUri;
  if (uri == null) {
    if (session.checkoutUrl != null && context.mounted) {
      showError(
        context,
        const AppException(
          AppErrorKind.unknown,
          'We couldn’t open a secure payment page. Please try again or contact support.',
        ),
      );
    }
    return false;
  }
  final ok = await ref.read(linkLauncherProvider).openCheckout(uri.toString());
  if (!ok && context.mounted) {
    showMessage(
      context,
      'We couldn’t open the payment page. Use “Open payment page” to try again.',
    );
  }
  return ok;
}
