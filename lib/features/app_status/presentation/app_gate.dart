import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/utilities/validators.dart';

/// Wraps the whole app (via `MaterialApp.builder`) and blocks it when the
/// server reports maintenance or this version is below the minimum.
/// Shows a dismissible banner when a newer optional version exists.
class AppGate extends ConsumerStatefulWidget {
  const AppGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> with WidgetsBindingObserver {
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-check when the app returns to foreground (maintenance may have ended).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(appConfigProvider);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(currentConfigProvider);
    final version = ref.watch(appVersionProvider).value;

    if (config.maintenance) {
      return _BlockingScreen(
        icon: Icons.construction_outlined,
        title: 'We’ll be right back',
        message: config.maintenanceMessage ??
            'Bizzvot is undergoing scheduled maintenance. Please try again shortly.',
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(appConfigProvider),
      );
    }

    final requirement =
        version == null ? UpdateRequirement.none : updateRequirement(config, version);

    if (requirement == UpdateRequirement.required) {
      return _BlockingScreen(
        icon: Icons.system_update_outlined,
        title: 'Update required',
        message: 'This version of Bizzvot is no longer supported. '
            'Please update to continue.',
        actionLabel: 'Update now',
        onAction: () => _openStore(config),
      );
    }

    if (requirement == UpdateRequirement.optional && !_bannerDismissed) {
      return Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.system_update_outlined),
                    const SizedBox(width: AppSpacing.sm),
                    const Expanded(child: Text('A new version of Bizzvot is available.')),
                    TextButton(
                      onPressed: () => _openStore(config),
                      child: const Text('Update'),
                    ),
                    IconButton(
                      tooltip: 'Dismiss',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _bannerDismissed = true),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: widget.child,
            ),
          ),
        ],
      );
    }

    return widget.child;
  }

  Future<void> _openStore(AppConfig config) async {
    final url = _isIOS ? config.iosStoreUrl : config.androidStoreUrl;
    if (url == null || !Validators.isSafeWebUrl(url)) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  static bool get _isIOS {
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  }
}

class _BlockingScreen extends StatelessWidget {
  const _BlockingScreen({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 72, color: theme.colorScheme.primary),
                const SizedBox(height: AppSpacing.lg),
                Text(title,
                    style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                Text(message,
                    style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(onPressed: onAction, child: Text(actionLabel)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
