import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import 'public_card_providers.dart';
import 'widgets/public_widgets.dart';

/// Public people directory at `/directory/:orgSlug` (PROPOSED endpoint).
///
/// Renders exactly the server-filtered list: privacy is enforced by the
/// backend and the app never fetches or hides private entries itself.
class PublicDirectoryScreen extends ConsumerWidget {
  const PublicDirectoryScreen({super.key, required this.orgSlug});

  final String orgSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Remote kill-switch: when the directory feature is off, don't fetch.
    if (!ref.watch(currentConfigProvider).isEnabled(Flags.directory)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team directory')),
        body: const UnavailableView(title: "This directory isn't available"),
      );
    }
    final provider = publicDirectoryProvider(orgSlug);
    final async = ref.watch(provider);
    final title = async.value?.organizationName ?? 'Team directory';

    Future<void> refresh() async {
      ref.invalidate(provider);
      try {
        await ref.read(provider.future);
      } catch (_) {}
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: async.when(
        skipLoadingOnRefresh: true,
        loading: () => const SkeletonList(),
        error: (e, _) => isUnavailableError(e)
            ? const UnavailableView(title: "This directory isn't available")
            : ErrorView(error: e, onRetry: () => ref.invalidate(provider)),
        data: (dir) {
          final list = dir.list;
          if (list.items.isEmpty) {
            return RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                children: const [
                  SizedBox(height: AppSpacing.xl),
                  EmptyView(
                    icon: Icons.people_outline,
                    title: 'No one is listed yet',
                    message: 'Check back later.',
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView.builder(
              itemCount: list.items.length + 1 + (list.hasMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return ContentWidth(
                    child: Padding(
                      padding: AppSpacing.page,
                      child: Row(
                        children: [
                          if (dir.organizationLogo != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                right: AppSpacing.md,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SafeNetworkImage(
                                  url: dir.organizationLogo,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.contain,
                                  fallback: const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              list.items.length == 1
                                  ? '1 person'
                                  : '${list.items.length}${list.hasMore ? '+' : ''} people',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final idx = i - 1;
                if (idx >= list.items.length) {
                  return ContentWidth(
                    child: Padding(
                      padding: AppSpacing.page,
                      child: Center(
                        child: list.loadingMore
                            ? const CircularProgressIndicator()
                            : OutlinedButton(
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(provider.notifier)
                                        .loadMore();
                                  } catch (e) {
                                    if (context.mounted) showError(context, e);
                                  }
                                },
                                child: const Text('Load more'),
                              ),
                      ),
                    ),
                  );
                }
                final entry = list.items[idx];
                final subtitle = [
                  entry.designation,
                  entry.company,
                ].whereType<String>().join(' · ');
                return ContentWidth(
                  child: ListTile(
                    leading: PersonAvatar(
                      name: entry.name,
                      url: entry.photo,
                      size: 48,
                    ),
                    title: Text(entry.name),
                    subtitle: subtitle.isEmpty ? null : Text(subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.publicCard(entry.slug)),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
