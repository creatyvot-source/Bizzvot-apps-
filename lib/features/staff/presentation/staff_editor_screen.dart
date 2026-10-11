import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/auth/auth_user.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utilities/validators.dart';
import '../../../shared/models/organization.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/presentation/widgets/callout.dart';
import '../../auth/presentation/widgets/cooldown.dart';
import '../../auth/presentation/widgets/password_field.dart';
import '../domain/staff_draft.dart';
import 'staff_providers.dart';
import 'widgets/staff_card_chip.dart';

/// Owner: add a staff member (`staffId == null`) or edit/remove one.
/// Creating a staff member also creates their assigned card server-side.
class StaffEditorScreen extends ConsumerStatefulWidget {
  const StaffEditorScreen({super.key, this.staffId});

  final String? staffId;

  @override
  ConsumerState<StaffEditorScreen> createState() => _StaffEditorScreenState();
}

class _StaffEditorScreenState extends ConsumerState<StaffEditorScreen> {
  /// Captured on first load so the form survives list refreshes (e.g. the
  /// member disappearing from the list right after a delete).
  StaffMember? _member;

  @override
  Widget build(BuildContext context) {
    final id = widget.staffId;
    if (id == null) return const _StaffForm(member: null);

    if (_member == null) {
      final async = ref.watch(staffMemberProvider(id));
      final loaded = async.value;
      if (loaded != null) {
        _member = loaded;
      } else {
        return Scaffold(
          appBar: AppBar(title: const Text('Staff member')),
          body: AsyncValueView<StaffMember>(
            value: async,
            loadingLabel: 'Loading…',
            onRetry: () => ref.invalidate(staffListProvider),
            data: (_) => const SizedBox.shrink(),
          ),
        );
      }
    }
    return _StaffForm(member: _member);
  }
}

class _PermissionInfo {
  const _PermissionInfo(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;
}

const _editCard = _PermissionInfo(
  'Edit their card',
  'Update their own card details, photos, template and layout.',
  Icons.edit_note_outlined,
);
const _manageLinks = _PermissionInfo(
  'Manage links',
  'Add, edit and remove social and custom links on their card.',
  Icons.link,
);
const _viewReviews = _PermissionInfo(
  'View reviews',
  'See reviews left on their card.',
  Icons.reviews_outlined,
);
const _replyReviews = _PermissionInfo(
  'Reply to reviews',
  'Reply publicly and change review visibility. Turns on View reviews.',
  Icons.reply_outlined,
);

class _StaffForm extends ConsumerStatefulWidget {
  const _StaffForm({required this.member});

  final StaffMember? member;

  @override
  ConsumerState<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<_StaffForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _designation = TextEditingController();
  final _password = TextEditingController();
  final _cooldown = Cooldown();

  StaffMember? _baseline;
  StaffPermissions _permissions = StaffPermissions.none;
  Map<String, String> _fieldErrors = const {};
  String? _error;
  bool _seatProblem = false;
  bool _busy = false;
  bool _finished = false;

  bool get _isCreate => widget.member == null;

  List<TextEditingController> get _controllers =>
      [_name, _email, _phone, _designation, _password];

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    _baseline = m;
    if (m != null) {
      final d = StaffDraft.fromMember(m);
      _name.text = d.name;
      _email.text = d.email;
      _phone.text = d.phone;
      _designation.text = d.designation;
      _permissions = d.permissions;
    }
    for (final c in _controllers) {
      c.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _cooldown.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  StaffDraft get _draft => StaffDraft(
        name: _name.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        designation: _designation.text.trim(),
        password: _password.text,
        permissions: _permissions,
      );

  bool get _isDirty {
    if (_finished) return false;
    final base = _baseline;
    if (base == null) {
      final d = _draft;
      return d.name.isNotEmpty ||
          d.email.isNotEmpty ||
          d.phone.isNotEmpty ||
          d.designation.isNotEmpty ||
          d.password.isNotEmpty ||
          d.permissions != StaffPermissions.none;
    }
    return _draft.changesFrom(base).isNotEmpty;
  }

  void _clearFieldError(String key) {
    if (_fieldErrors.containsKey(key)) {
      setState(() => _fieldErrors = Map.of(_fieldErrors)..remove(key));
    }
  }

  void _setPermission(_PermissionInfo which, bool on) {
    setState(() {
      final p = _permissions;
      _permissions = switch (which) {
        _editCard => p.copyWith(editCard: on),
        _manageLinks => p.copyWith(manageLinks: on),
        // Replying requires seeing reviews.
        _viewReviews => on
            ? p.copyWith(viewReviews: true)
            : p.copyWith(viewReviews: false, replyReviews: false),
        _replyReviews => on
            ? p.copyWith(replyReviews: true, viewReviews: true)
            : p.copyWith(replyReviews: false),
        _ => p,
      };
    });
  }

  /// Navigator.pop (not maybePop) so the unsaved-changes guard is bypassed
  /// after a successful save.
  void _close() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      context.go(Routes.ownerStaff);
    }
  }

  Future<void> _save() async {
    if (_cooldown.active || _busy) return;
    setState(() {
      _error = null;
      _fieldErrors = const {};
      _seatProblem = false;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final mutations = ref.read(staffMutationsProvider);
    final draft = _draft;
    _busy = true;
    try {
      if (_isCreate) {
        final created = await mutations.create(draft);
        if (!mounted) return;
        _finished = true;
        final state = created == null ? null : StaffCardState.of(created);
        showMessage(
          context,
          state == StaffCardState.disabledByBilling || state == StaffCardState.disabled
              ? 'Staff member added. Their card stays inactive until a paid seat is available.'
              : 'Staff member added with their own card.',
        );
        _close();
      } else {
        final base = _baseline!;
        final changes = draft.changesFrom(base);
        if (changes.isEmpty) return;
        await mutations.update(base.id, changes);
        if (!mounted) return;
        _finished = true;
        showMessage(context, 'Changes saved');
        _close();
      }
    } catch (error) {
      if (!mounted) return;
      _handleError(AppException.from(error));
    } finally {
      _busy = false;
    }
  }

  void _handleError(AppException e) {
    setState(() {
      if (e.kind == AppErrorKind.rateLimited) {
        _cooldown.startFrom(e);
        return;
      }
      switch (classifyStaffSaveError(e)) {
        case StaffSaveProblem.noSeat:
          _seatProblem = true;
        case StaffSaveProblem.duplicateEmail:
          _fieldErrors = {
            'email': e.fieldErrors['email'] ??
                'This login email is already in use. Use a different email.',
          };
        case StaffSaveProblem.other:
          if (e.kind == AppErrorKind.validation && e.fieldErrors.isNotEmpty) {
            _fieldErrors = e.fieldErrors;
            _error = 'Please fix the highlighted fields.';
          } else {
            _error = e.message;
          }
      }
    });
  }

  Future<void> _delete() async {
    final m = _baseline;
    if (m == null || _busy) return;
    final ok = await confirmAction(
      context,
      title: 'Remove ${m.name}?',
      message:
          'Their staff sign-in will stop working and their assigned card will '
          'no longer be available to share. This can’t be undone.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(staffMutationsProvider).delete(m.id);
      if (!mounted) return;
      _finished = true;
      showMessage(context, '${m.name} was removed');
      _close();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await confirmAction(
      context,
      title: 'Discard changes?',
      message: _isCreate
          ? 'This staff member hasn’t been added yet.'
          : 'Your changes haven’t been saved.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _isDirty;
    final theme = Theme.of(context);
    final member = _baseline;
    const gap = SizedBox(height: AppSpacing.md);

    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isCreate ? 'Add staff' : 'Edit staff'),
          actions: [
            if (!_isCreate)
              IconButton(
                tooltip: 'Remove staff member',
                icon: const Icon(Icons.delete_outline),
                onPressed: _busy ? null : _delete,
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              ContentWidth(
                child: Padding(
                  padding: AppSpacing.page,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_seatProblem) ...[
                        _SeatCallout(isCreate: _isCreate),
                        gap,
                      ],
                      if (_error != null) ...[
                        Callout(tone: CalloutTone.error, message: _error!),
                        gap,
                      ],
                      if (_isCreate)
                        const Callout(
                          message:
                              'A digital card is created for this person automatically. '
                              'They sign in with the login email and password below.',
                        )
                      else if (member != null)
                        _CardSummary(member: member),
                      const SizedBox(height: AppSpacing.lg),
                      const _SectionHeader('Details'),
                      gap,
                      TextFormField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        validator: (v) => Validators.required(v, 'Name'),
                        forceErrorText: _fieldErrors['name'],
                        onChanged: (_) => _clearFieldError('name'),
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      gap,
                      TextFormField(
                        controller: _designation,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.jobTitle],
                        forceErrorText: _fieldErrors['designation'],
                        onChanged: (_) => _clearFieldError('designation'),
                        decoration: const InputDecoration(
                          labelText: 'Designation (optional)',
                          hintText: 'e.g. Sales Manager',
                          prefixIcon: Icon(Icons.work_outline),
                        ),
                      ),
                      gap,
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        validator: Validators.optionalPhone,
                        forceErrorText: _fieldErrors['phone'],
                        onChanged: (_) => _clearFieldError('phone'),
                        decoration: const InputDecoration(
                          labelText: 'Phone (optional)',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const _SectionHeader('Sign-in'),
                      gap,
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction:
                            _isCreate ? TextInputAction.next : TextInputAction.done,
                        autocorrect: false,
                        enableSuggestions: false,
                        validator: Validators.email,
                        forceErrorText: _fieldErrors['email'],
                        onChanged: (_) => _clearFieldError('email'),
                        decoration: const InputDecoration(
                          labelText: 'Login email',
                          helperText: 'Used for staff sign-in.',
                          prefixIcon: Icon(Icons.alternate_email),
                          errorMaxLines: 3,
                        ),
                      ),
                      if (_isCreate) ...[
                        gap,
                        PasswordField(
                          controller: _password,
                          label: 'Initial password',
                          isNewPassword: true,
                          validator: Validators.password,
                          errorText: _fieldErrors['password'],
                          onChanged: (_) => _clearFieldError('password'),
                          helperText:
                              'Share it with them privately. They can change it after signing in.',
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      const _SectionHeader('Permissions'),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Everything is off by default. Staff can always view '
                        'and share their own card.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ContentWidth(
                child: Column(
                  children: [
                    _PermissionSwitch(
                      info: _editCard,
                      value: _permissions.editCard,
                      onChanged: (v) => _setPermission(_editCard, v),
                    ),
                    _PermissionSwitch(
                      info: _manageLinks,
                      value: _permissions.manageLinks,
                      onChanged: (v) => _setPermission(_manageLinks, v),
                    ),
                    _PermissionSwitch(
                      info: _viewReviews,
                      value: _permissions.viewReviews,
                      onChanged: (v) => _setPermission(_viewReviews, v),
                    ),
                    _PermissionSwitch(
                      info: _replyReviews,
                      value: _permissions.replyReviews,
                      onChanged: (v) => _setPermission(_replyReviews, v),
                    ),
                  ],
                ),
              ),
              ContentWidth(
                child: Padding(
                  padding: AppSpacing.page,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CooldownSubmitButton(
                        label: _isCreate
                            ? 'Add staff member'
                            : (dirty ? 'Save changes' : 'No changes to save'),
                        cooldown: _cooldown,
                        onPressed: (_isCreate || dirty) ? _save : null,
                      ),
                      if (!_isCreate) ...[
                        const SizedBox(height: AppSpacing.xl),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            side: BorderSide(color: theme.colorScheme.error),
                          ),
                          onPressed: _busy ? null : _delete,
                          icon: const Icon(Icons.person_remove_outlined),
                          label: const Text('Remove staff member'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

class _PermissionSwitch extends StatelessWidget {
  const _PermissionSwitch({
    required this.info,
    required this.value,
    required this.onChanged,
  });

  final _PermissionInfo info;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        secondary: Icon(info.icon),
        title: Text(info.title),
        subtitle: Text(info.subtitle),
        value: value,
        onChanged: onChanged,
      );
}

class _SeatCallout extends StatelessWidget {
  const _SeatCallout({required this.isCreate});

  final bool isCreate;

  @override
  Widget build(BuildContext context) {
    return Callout(
      tone: CalloutTone.warning,
      title: 'No paid card slot available',
      message: isCreate
          ? 'Every staff member gets a digital card, and each active card needs '
              'a paid seat once your trial has ended. Purchase more seats or '
              'deactivate another card, then try again.'
          : 'This change needs an active card, but all paid seats are in use. '
              'Purchase more seats or deactivate another card, then try again.',
      action: FilledButton.tonal(
        onPressed: () => context.push(Routes.ownerSeats),
        child: const Text('Purchase seats'),
      ),
    );
  }
}

class _CardSummary extends StatelessWidget {
  const _CardSummary({required this.member});

  final StaffMember member;

  @override
  Widget build(BuildContext context) {
    final state = StaffCardState.of(member);
    final card = member.card;
    final explanation = switch (state) {
      StaffCardState.active => 'Their card is live and can be shared.',
      StaffCardState.disabled => 'Their card is turned off and hidden from visitors.',
      StaffCardState.disabledByBilling =>
        'Their card is inactive because no paid seat is available. Purchase '
            'seats or renew your plan to reactivate it.',
      StaffCardState.none => 'No card is assigned to this person yet.',
    };
    return Card(
      child: Padding(
        padding: AppSpacing.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Assigned card',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                StaffCardChip(state: state),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(explanation),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (card != null && card.id.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => context.push(Routes.ownerCard(card.id)),
                    icon: const Icon(Icons.badge_outlined),
                    label: const Text('Open card'),
                  ),
                if (state == StaffCardState.disabledByBilling)
                  FilledButton.tonal(
                    onPressed: () => context.push(Routes.ownerSeats),
                    child: const Text('Purchase seats'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
