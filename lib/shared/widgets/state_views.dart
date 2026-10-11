import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/errors/app_exception.dart';

/// Consistent loading / empty / error states. Every screen that loads data
/// should go through [AsyncValueView] so behavior stays uniform.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: label ?? 'Loading',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (label != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(label!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final e = AppException.from(error);
    final (icon, title) = switch (e.kind) {
      AppErrorKind.network => (Icons.wifi_off_outlined, 'You are offline'),
      AppErrorKind.forbidden => (Icons.lock_outline, 'Access restricted'),
      AppErrorKind.notFound => (Icons.search_off_outlined, 'Not found'),
      AppErrorKind.gone => (Icons.block_outlined, 'No longer available'),
      AppErrorKind.rateLimited => (Icons.hourglass_empty, 'Slow down'),
      _ => (Icons.error_outline, 'Something went wrong'),
    };
    final retryable = switch (e.kind) {
      AppErrorKind.forbidden || AppErrorKind.notFound || AppErrorKind.gone => false,
      _ => true,
    };
    return EmptyView(
      icon: icon,
      title: title,
      message: e.message,
      action: (onRetry != null && retryable)
          ? OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            )
          : null,
    );
  }
}

/// Renders an [AsyncValue] with shared loading/error states.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.loadingLabel,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    return value.when(
      // Keep showing previous data while refreshing.
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: data,
      loading: () => LoadingView(label: loadingLabel),
      error: (e, _) => ErrorView(error: e, onRetry: onRetry),
    );
  }
}

/// Centers and width-constrains page content on tablets.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
          child: child,
        ),
      );
}
