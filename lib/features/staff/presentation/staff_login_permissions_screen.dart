import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/auth/auth_user.dart';
import '../../../core/auth/session_controller.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../domain/staff_draft.dart';
import 'staff_providers.dart';

/// Screen for managing staff login credentials, access status, and
/// organization permissions (editCard, manageLinks, viewReviews, replyReviews).
class StaffLoginPermissionsScreen extends ConsumerStatefulWidget {
  const StaffLoginPermissionsScreen({super.key, this.initialStaffId});

  final String? initialStaffId;

  @override
  ConsumerState<StaffLoginPermissionsScreen> createState() =>
      _StaffLoginPermissionsScreenState();
}

class _StaffLoginPermissionsScreenState
    extends ConsumerState<StaffLoginPermissionsScreen> {
  String? _selectedStaffId;
  final Map<String, StaffPermissions> _editedPermissions = {};
  final Map<String, StaffStatus> _editedStatuses = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedStaffId = widget.initialStaffId;
  }

  void _shareCredentials(StaffEntry staff, String orgName) {
    final message = '''
👋 Welcome to $orgName on Bizzvot!

Your staff digital card & credentials are ready:
• Login Email: ${staff.email}
• Organization: $orgName
• Portal: https://app.bizzvot.com/staff-login

Please open the Bizzvot app, choose "Staff Sign-in", and log in with your credentials.
''';

    Clipboard.setData(ClipboardData(text: message));
    HapticFeedback.mediumImpact();
    showMessage(
      context,
      'Staff login details copied to clipboard! Ready to send via WhatsApp or SMS.',
    );
  }

  Future<void> _saveStaff(StaffEntry staff) async {
    final permissions = _editedPermissions[staff.id] ?? staff.permissions;
    final status = _editedStatuses[staff.id] ?? staff.status;

    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    try {
      await ref.read(staffMutationsProvider).update(staff.id, {
        'permissions': permissions.toJson(),
        'status': status.wire,
      });
      if (mounted) {
        showMessage(context, 'Permissions & login saved for ${staff.name}');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffListProvider);
    final user = ref.watch(currentUserProvider);
    final orgName = user?.organizationName ?? 'Your Organization';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Login & Permissions'),
        actions: [
          IconButton(
            tooltip: 'Add new staff',
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () => context.push(Routes.ownerStaffNew),
          ),
          IconButton(
            tooltip: 'Purchase extra seats',
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () => context.push(Routes.ownerSeats),
          ),
        ],
      ),
      body: AsyncValueView<List<StaffEntry>>(
        value: staffAsync,
        onRetry: () => ref.invalidate(staffListProvider),
        data: (allStaff) {
          if (allStaff.isEmpty) {
            return EmptyView(
              icon: Icons.admin_panel_settings_outlined,
              title: 'No staff members yet',
              message:
                  'Add staff members to configure login credentials, role access, and card permissions.',
              action: FilledButton.icon(
                onPressed: () => context.push(Routes.ownerStaffNew),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add first staff'),
              ),
            );
          }

          final selectedId = _selectedStaffId ?? allStaff.first.id;
          final currentStaff =
              allStaff.where((s) => s.id == selectedId).firstOrNull ??
                  allStaff.first;

          final permissions =
              _editedPermissions[currentStaff.id] ?? currentStaff.permissions;
          final status =
              _editedStatuses[currentStaff.id] ?? currentStaff.status;
          final isSuspended = status == StaffStatus.suspended;

          return ContentWidth(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                // Top Info & Purchase Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                          : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white12 : const Color(0xFF93C5FD),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.security_outlined,
                            color: Color(0xFF2563EB),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Organization Access Control',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1E40AF),
                                fontSize: 14,
                              ),
                            ),
                          ),
                          FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => context.push(Routes.ownerSeats),
                            child: const Text(
                              '+ Seats',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Set granular permission toggles per employee. Staff can sign in to view and share their card, update links, or reply to reviews.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF1E3A8A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Staff member selector carousel/chips
                const Text(
                  'Select Staff Member',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: allStaff.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final staff = allStaff[i];
                      final isSelected = staff.id == currentStaff.id;
                      return ChoiceChip(
                        avatar: CircleAvatar(
                          radius: 12,
                          backgroundColor: isSelected
                              ? Colors.white
                              : theme.colorScheme.primaryContainer,
                          child: Text(
                            staff.name.isNotEmpty
                                ? staff.name[0].toUpperCase()
                                : 'S',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        label: Text(staff.name),
                        selected: isSelected,
                        onSelected: (val) {
                          if (val) {
                            setState(() => _selectedStaffId = staff.id);
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // Staff Profile & Credentials Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: theme.colorScheme.primary,
                              child: Text(
                                currentStaff.name.isNotEmpty
                                    ? currentStaff.name[0].toUpperCase()
                                    : 'S',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentStaff.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    currentStaff.email,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (currentStaff.phone != null &&
                                      currentStaff.phone!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      currentStaff.phone!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton.filledTonal(
                              tooltip: 'Copy & Share Login',
                              icon: const Icon(Icons.share_outlined, size: 20),
                              onPressed: () =>
                                  _shareCredentials(currentStaff, orgName),
                            ),
                          ],
                        ),
                        const Divider(height: 24),

                        // Login Status Toggle
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: Icon(
                            isSuspended
                                ? Icons.block_outlined
                                : Icons.check_circle_outline,
                            color: isSuspended ? Colors.red : Colors.green,
                          ),
                          title: const Text(
                            'Allow Staff Login',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            isSuspended
                                ? 'Suspended: staff cannot sign in'
                                : 'Active: staff can log in to app',
                            style: const TextStyle(fontSize: 12),
                          ),
                          value: !isSuspended,
                          onChanged: (val) {
                            setState(() {
                              _editedStatuses[currentStaff.id] = val
                                  ? StaffStatus.active
                                  : StaffStatus.suspended;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Granular Organization Permissions Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.admin_panel_settings_outlined,
                              color: Color(0xFF2563EB),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Staff Role Permissions',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Configure what ${currentStaff.name} can access in the mobile app:',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Permission 1: Edit Card
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.edit_note_outlined),
                          title: const Text(
                            'Edit Digital Card',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'Update card profile, avatar, and contact bio',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: permissions.editCard,
                          onChanged: (val) {
                            setState(() {
                              _editedPermissions[currentStaff.id] = permissions
                                  .copyWith(
                                    editCard: val,
                                    manageLinks:
                                        val ? permissions.manageLinks : false,
                                  );
                            });
                          },
                        ),
                        const Divider(height: 16),

                        // Permission 2: Manage Links
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.link),
                          title: const Text(
                            'Manage Links & Socials',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'Add, edit, or delete external links and WhatsApp',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: permissions.manageLinks,
                          onChanged: (val) {
                            setState(() {
                              _editedPermissions[currentStaff.id] = permissions
                                  .copyWith(
                                    manageLinks: val,
                                    editCard: val ? true : permissions.editCard,
                                  );
                            });
                          },
                        ),
                        const Divider(height: 16),

                        // Permission 3: View Reviews
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.reviews_outlined),
                          title: const Text(
                            'View Google & Card Reviews',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'See incoming ratings and client feedback',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: permissions.viewReviews,
                          onChanged: (val) {
                            setState(() {
                              _editedPermissions[currentStaff.id] = permissions
                                  .copyWith(
                                    viewReviews: val,
                                    replyReviews:
                                        val ? permissions.replyReviews : false,
                                  );
                            });
                          },
                        ),
                        const Divider(height: 16),

                        // Permission 4: Reply to Reviews
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.reply_outlined),
                          title: const Text(
                            'Reply & Moderate Reviews',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'Publish replies to client reviews & feedback',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: permissions.replyReviews,
                          onChanged: (val) {
                            setState(() {
                              _editedPermissions[currentStaff.id] = permissions
                                  .copyWith(
                                    replyReviews: val,
                                    viewReviews:
                                        val ? true : permissions.viewReviews,
                                  );
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Action Buttons
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _saving ? null : () => _saveStaff(currentStaff),
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_saving ? 'Saving...' : 'Save Permissions'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _shareCredentials(currentStaff, orgName),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy Credentials & Instructions'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
