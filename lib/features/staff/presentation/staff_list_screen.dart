import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/staff_draft.dart';
import 'staff_providers.dart';
import 'widgets/staff_card_chip.dart';

/// Owner "People" tab: staff members with their card status, search, and
/// an entry point to add staff.
class StaffListScreen extends ConsumerStatefulWidget {
  const StaffListScreen({super.key});

  @override
  ConsumerState<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends ConsumerState<StaffListScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() => ref.refresh(staffListProvider.future);

  static bool _matches(StaffEntry m, String q) {
    if (q.isEmpty) return true;
    return [
      m.name,
      m.email,
      m.designation ?? '',
      m.phone ?? '',
    ].any((f) => f.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('People')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.ownerStaffNew),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add staff'),
      ),
      body: staff.isLoading && !staff.hasValue
          ? const SkeletonList()
          : AsyncValueView<List<StaffEntry>>(
              value: staff,
              onRetry: () => ref.invalidate(staffListProvider),
              data: (all) {
                final q = _query.trim().toLowerCase();
                final visible = all.where((m) => _matches(m, q)).toList()
                  ..sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (all.isNotEmpty)
                        SliverToBoxAdapter(
                          child: ContentWidth(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.md,
                                AppSpacing.sm,
                                AppSpacing.md,
                                AppSpacing.sm,
                              ),
                              child: _SearchField(
                                controller: _search,
                                onChanged: (v) => setState(() => _query = v),
                                onClear: () => setState(() {
                                  _search.clear();
                                  _query = '';
                                }),
                              ),
                            ),
                          ),
                        ),
                      if (all.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyView(
                            icon: Icons.group_add_outlined,
                            title: 'No staff yet',
                            message: 'Add your team members. Each one gets a staff sign-in and, optionally, their own digital card.',
                            action: FilledButton.icon(
                              onPressed: () =>
                                  context.push(Routes.ownerStaffNew),
                              icon: const Icon(Icons.person_add_alt_1_outlined),
                              label: const Text('Add staff'),
                            ),
                          ),
                        )
                      else if (visible.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyView(
                            icon: Icons.search_off_outlined,
                            title: 'No matches',
                            message: 'No staff match “${_query.trim()}”.',
                          ),
                        )
                      else ...[
                        SliverToBoxAdapter(
                          child: ContentWidth(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  q.isEmpty
                                      ? '${all.length} ${all.length == 1 ? 'person' : 'people'}'
                                      : '${visible.length} of ${all.length}',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SliverList.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, i) => ContentWidth(
                            child: _StaffTile(member: visible[i]),
                          ),
                        ),
                        // Keep the last row clear of the FAB.
                        const SliverToBoxAdapter(child: SizedBox(height: 96)),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      decoration: InputDecoration(
        hintText: 'Search by name, email or role',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: onClear,
              ),
      ),
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({required this.member});

  final StaffEntry member;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final card = m.primaryCard;
    final cardState = StaffCardState.of(m);
    final secondary = [
      if (card?.designation != null) card!.designation!,
      if (m.email.isNotEmpty) m.email,
    ].join(' · ');
    return ListTile(
      leading: ExcludeSemantics(
        child: InitialsAvatar(name: m.name, imageUrl: card?.profilePhoto),
      ),
      title: Text(m.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (secondary.isNotEmpty) Text(secondary),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (m.isSuspended)
                const StatusChip(
                  'Sign-in suspended',
                  tone: StatusTone.danger,
                  icon: Icons.lock_outline,
                ),
              if (cardState != null) StaffCardChip(state: cardState),
              if (m.cards.length > 1)
                StatusChip(
                  '${m.cards.length} cards',
                  icon: Icons.style_outlined,
                ),
              if (card != null) CardVisibilityChip(visibility: card.visibility),
            ],
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(Routes.ownerStaffEdit(m.id)),
    );
  }
}
