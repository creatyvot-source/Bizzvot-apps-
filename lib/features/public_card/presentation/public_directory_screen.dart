import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/public_directory.dart';
import 'public_card_providers.dart';
import 'widgets/public_widgets.dart';

/// Public cards & people directory screen at `/directory/:orgSlug` or `/o/directory`
/// or `/s/directory` in the floating navigation menu.
///
/// Allows browsing public digital business cards, individual staff cards,
/// with 1-tap Call (`tel:`), 1-tap WhatsApp (`wa.me/`), and View Card actions.
class PublicDirectoryScreen extends ConsumerStatefulWidget {
  const PublicDirectoryScreen({super.key, this.orgSlug = 'bizzvot'});

  final String orgSlug;

  @override
  ConsumerState<PublicDirectoryScreen> createState() =>
      _PublicDirectoryScreenState();
}

class _PublicDirectoryScreenState extends ConsumerState<PublicDirectoryScreen> {
  final _searchController = TextEditingController();
  String _searchFilter = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _makeCall(String? phone) async {
    final raw = phone ?? '+91 89215 04090';
    final cleaned = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    HapticFeedback.lightImpact();
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _openWhatsApp(String? phone, String name) async {
    final raw = phone ?? '+91 89215 04090';
    final cleaned = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final msg = Uri.encodeComponent(
      'Hi $name, connecting with you via Bizzvot Digital Business Card!',
    );
    final uri = Uri.parse('https://wa.me/$cleaned?text=$msg');
    HapticFeedback.lightImpact();
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(currentConfigProvider).isEnabled(Flags.directory)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Directory')),
        body: const UnavailableView(title: "This directory isn't available"),
      );
    }

    final slug = widget.orgSlug.isEmpty ? 'bizzvot' : widget.orgSlug;
    final provider = publicDirectoryProvider(slug);
    final async = ref.watch(provider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Future<void> refresh() async {
      ref.invalidate(provider);
      try {
        await ref.read(provider.future);
      } catch (_) {}
    }

    final title = async.value?.organizationName ?? 'Cards & People Directory';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: const [
          ThemeToggleActionButton(),
          SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: async.when(
        skipLoadingOnRefresh: true,
        loading: () => const SkeletonList(count: 5),
        error: (e, _) => isUnavailableError(e)
            ? const UnavailableView(title: "This directory isn't available")
            : ErrorView(error: e, onRetry: () => ref.invalidate(provider)),
        data: (dir) {
          var items = dir.list.items;
          if (items.isEmpty && (widget.orgSlug == 'bizzvot' || widget.orgSlug.isEmpty)) {
            items = DirectoryEntry.defaultEntries;
          }

          if (items.isEmpty) {
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

          if (_searchFilter.isNotEmpty) {
            final q = _searchFilter.toLowerCase();
            items = items
                .where((item) =>
                    item.name.toLowerCase().contains(q) ||
                    (item.designation?.toLowerCase().contains(q) ?? false) ||
                    (item.company?.toLowerCase().contains(q) ?? false))
                .toList();
          }

          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                110,
              ),
              children: [
                // Search field
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchFilter = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search people, designation, or company...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchFilter.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchFilter = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark
                        ? theme.colorScheme.surfaceContainerHigh
                        : Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Count & quick filter indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${items.length} ${items.length == 1 ? 'Digital Card' : 'Digital Cards'} Available',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.contactless,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'NFC Enabled',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: EmptyView(
                      icon: Icons.search_off,
                      title: 'No cards found',
                      message: 'Try searching with a different keyword.',
                    ),
                  )
                else
                  for (final entry in items) ...[
                    _DirectoryCardTile(
                      entry: entry,
                      onCall: () => _makeCall(entry.phone),
                      onWhatsApp: () =>
                          _openWhatsApp(entry.whatsapp ?? entry.phone, entry.name),
                      onViewCard: () =>
                          context.push(Routes.publicCard(entry.slug)),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DirectoryCardTile extends StatelessWidget {
  const _DirectoryCardTile({
    required this.entry,
    required this.onCall,
    required this.onWhatsApp,
    required this.onViewCard,
  });

  final DirectoryEntry entry;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final VoidCallback onViewCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.3)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      color: isDark
          ? theme.colorScheme.surfaceContainerHigh
          : Colors.white,
      child: InkWell(
        onTap: onViewCard,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PersonAvatar(
                    name: entry.name,
                    url: entry.photo,
                    size: 52,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                entry.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.verified,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ),
                        if (entry.designation != null &&
                            entry.designation!.isNotEmpty)
                          Text(
                            entry.designation!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (entry.company != null && entry.company!.isNotEmpty)
                          Text(
                            entry.company!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (entry.badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        entry.badge!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 0.5),
              const SizedBox(height: 8),

              // Action buttons row: Call, WhatsApp, View Card
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      onPressed: onCall,
                      icon: const Icon(Icons.call, size: 16, color: Colors.blue),
                      label: const Text(
                        'Call',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.15),
                        foregroundColor: const Color(0xFF1E8E42),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: onWhatsApp,
                      icon: const Icon(Icons.chat_bubble_outline, size: 16),
                      label: const Text(
                        'WhatsApp',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'View Card & Details',
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: onViewCard,
                    icon: const Icon(Icons.badge_outlined, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
