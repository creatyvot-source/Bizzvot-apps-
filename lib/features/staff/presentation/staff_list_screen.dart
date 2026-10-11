import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../shared/models/organization.dart';
import '../../../shared/widgets/state_views.dart';
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

  static bool _matches(StaffMember m, String q) {
    if (q.isEmpty) return true;
    return [m.name, m.email, m.designation ?? '', m.phone ?? '']
        .any((f) => f.toLowerCase().contains(q));
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
      body: AsyncValueView<List<StaffMember>>(
        value: staff,
        loadingLabel: 'Loading staff…',
        onRetry: () => ref.invalidate(staffListProvider),
        data: (all) {
          final q = _query.trim().toLowerCase();
          final visible = all.where((m) => _matches(m, q)).toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
                      message:
                          'Add your team members. Each one gets their own digital card and staff sign-in.',
                      action: FilledButton.icon(
                        onPressed: () => context.push(Routes.ownerStaffNew),
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

  final StaffMember member;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final initial = m.name.trim().isEmpty ? '?' : m.name.trim().characters.first.toUpperCase();
    final secondary = [
      if (m.designation != null) m.designation!,
      if (m.email.isNotEmpty) m.email,
    ].join(' · ');
    return ListTile(
      leading: ExcludeSemantics(child: CircleAvatar(child: Text(initial))),
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
              StaffCardChip(state: StaffCardState.of(m)),
              if (m.card != null) CardVisibilityChip(visibility: m.card!.visibility),
            ],
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(Routes.ownerStaffEdit(m.id)),
    );
  }
}
