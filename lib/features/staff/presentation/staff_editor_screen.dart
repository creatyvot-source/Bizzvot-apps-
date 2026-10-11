import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/auth/auth_user.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utilities/validators.dart';
import '../../../shared/models/card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../auth/presentation/widgets/callout.dart';
import '../../auth/presentation/widgets/cooldown.dart';
import '../../auth/presentation/widgets/password_field.dart';
import '../domain/staff_draft.dart';
import 'staff_providers.dart';
import 'widgets/staff_card_chip.dart';

/// Owner: add a staff member (`staffId == null`) or manage one.
///
/// Adding creates the staff sign-in, then (optionally) their digital card
/// via `POST /organization/cards`, which is then assigned to them. Editing
/// covers what the API supports: permissions, sign-in access and assigned
/// cards. Name, login email and phone are read-only until the backend
/// accepts them on `PATCH /organization/staff/:id`.
class StaffEditorScreen extends ConsumerStatefulWidget {
  const StaffEditorScreen({super.key, this.staffId});

  final String? staffId;

  @override
  ConsumerState<StaffEditorScreen> createState() => _StaffEditorScreenState();
}

class _StaffEditorScreenState extends ConsumerState<StaffEditorScreen> {
  /// Captured once so the form survives list refreshes (e.g. right after a
  /// delete), or set after "add" when the card step needs attention.
  StaffEntry? _member;
  Object? _cardError;

  @override
  Widget build(BuildContext context) {
    final id = widget.staffId;
    if (_member == null && id == null) {
      return _CreateStaffForm(
        onCardProblem: (entry, error) => setState(() {
          _member = entry;
          _cardError = error;
        }),
      );
    }
    if (_member == null) {
      final async = ref.watch(staffMemberProvider(id!));
      final loaded = async.value;
      if (loaded == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Staff member')),
          body: async.isLoading
              ? const SkeletonList(count: 4)
              : AsyncValueView<StaffEntry>(
                  value: async,
                  onRetry: () => ref.invalidate(staffMemberProvider(id)),
                  data: (_) => const SizedBox.shrink(),
                ),
        );
      }
      _member = loaded;
    }
    return _EditStaffForm(
      key: ValueKey(_member!.id),
      member: _member!,
      initialCardError: _cardError,
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits

class _PermissionInfo {
  const _PermissionInfo(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;
}

const _editCard = _PermissionInfo(
  'Edit their card',
  'Update their own card details, photo and layout.',
  Icons.edit_note_outlined,
);
const _manageLinks = _PermissionInfo(
  'Manage links',
  'Add, edit and remove links on their card. Turns on Edit their card.',
  Icons.link,
);
const _viewReviews = _PermissionInfo(
  'View reviews',
  'See reviews left on their card.',
  Icons.reviews_outlined,
);
const _replyReviews = _PermissionInfo(
  'Reply to and moderate reviews',
  'Reply publicly and change review visibility. Turns on View reviews.',
  Icons.reply_outlined,
);

/// Applies a toggle, keeping dependent permissions consistent: replying
/// needs viewing, and link changes go through the card editor.
StaffPermissions _applyPermission(
  StaffPermissions p,
  _PermissionInfo which,
  bool on,
) => switch (which) {
  _editCard =>
    on
        ? p.copyWith(editCard: true)
        : p.copyWith(editCard: false, manageLinks: false),
  _manageLinks =>
    on
        ? p.copyWith(manageLinks: true, editCard: true)
        : p.copyWith(manageLinks: false),
  _viewReviews =>
    on
        ? p.copyWith(viewReviews: true)
        : p.copyWith(viewReviews: false, replyReviews: false),
  _replyReviews =>
    on
        ? p.copyWith(replyReviews: true, viewReviews: true)
        : p.copyWith(replyReviews: false),
  _ => p,
};

class _PermissionsSection extends StatelessWidget {
  const _PermissionsSection({required this.value, required this.onChanged});

  final StaffPermissions value;
  final ValueChanged<StaffPermissions> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tile(_PermissionInfo info, bool on) => SwitchListTile(
      secondary: Icon(info.icon),
      title: Text(info.title),
      subtitle: Text(info.subtitle),
      value: on,
      onChanged: (v) => onChanged(_applyPermission(value, info, v)),
    );
    return Column(
      children: [
        tile(_editCard, value.editCard),
        tile(_manageLinks, value.manageLinks),
        tile(_viewReviews, value.viewReviews),
        tile(_replyReviews, value.replyReviews),
      ],
    );
  }
}

/// Explains a seat / staff-limit failure with a route to buy more.
class _LimitCallout extends StatelessWidget {
  const _LimitCallout({required this.problem, this.prefix});

  final StaffSaveProblem problem;

  /// e.g. "Priya was added, but their card couldn't be created."
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final staffLimit = problem == StaffSaveProblem.staffLimit;
    final body = staffLimit
        ? 'Your plan’s staff limit has been reached. Upgrade your plan or '
              'remove a staff member, then try again.'
        : 'No paid card slot is available. Every active card needs a paid '
              'seat once your trial ends. Purchase more seats or deactivate '
              'another card, then try again.';
    return Callout(
      tone: CalloutTone.warning,
      title: staffLimit ? 'Staff limit reached' : 'No paid card slot available',
      message: prefix == null ? body : '$prefix $body',
      action: FilledButton.tonal(
        onPressed: () => context.push(Routes.ownerSeats),
        child: Text(staffLimit ? 'View plans & seats' : 'Purchase seats'),
      ),
    );
  }
}

void _closeEditor(BuildContext context) {
  // Navigator.pop (not maybePop) bypasses the unsaved-changes guard.
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
  } else {
    context.go(Routes.ownerStaff);
  }
}

Future<bool> _confirmDiscard(BuildContext context, String message) =>
    confirmAction(
      context,
      title: 'Discard changes?',
      message: message,
      confirmLabel: 'Discard',
      destructive: true,
    );

Widget _page(List<Widget> children) => ContentWidth(
  child: Padding(
    padding: AppSpacing.pageH,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  ),
);

// ---------------------------------------------------------------------------
// Add staff

class _CreateStaffForm extends ConsumerStatefulWidget {
  const _CreateStaffForm({required this.onCardProblem});

  /// The staff member was created but the card step failed.
  final void Function(StaffEntry entry, Object error) onCardProblem;

  @override
  ConsumerState<_CreateStaffForm> createState() => _CreateStaffFormState();
}

class _CreateStaffFormState extends ConsumerState<_CreateStaffForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _designation = TextEditingController();
  final _password = TextEditingController();
  final _cooldown = Cooldown();

  StaffPermissions _permissions = StaffPermissions.none;
  bool _createCard = true;
  Map<String, String> _fieldErrors = const {};
  String? _error;
  StaffSaveProblem? _limit;
  bool _done = false;

  List<TextEditingController> get _controllers => [
    _name,
    _email,
    _phone,
    _designation,
    _password,
  ];

  @override
  void initState() {
    super.initState();
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

  bool get _dirty =>
      !_done &&
      (_controllers.any((c) => c.text.trim().isNotEmpty) ||
          _permissions != StaffPermissions.none);

  void _clearFieldError(String key) {
    if (_fieldErrors.containsKey(key)) {
      setState(() => _fieldErrors = Map.of(_fieldErrors)..remove(key));
    }
  }

  Future<void> _save() async {
    if (_cooldown.active) return;
    setState(() {
      _error = null;
      _fieldErrors = const {};
      _limit = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final draft = StaffDraft(
      name: _name.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      designation: _designation.text.trim(),
      password: _password.text,
      permissions: _permissions,
      createCard: _createCard,
    );
    try {
      final result = await ref.read(staffMutationsProvider).create(draft);
      if (!mounted) return;
      _done = true;
      final cardError = result.cardError;
      if (cardError != null) {
        widget.onCardProblem(result.staff, cardError);
        return;
      }
      showMessage(
        context,
        result.card != null
            ? '${result.staff.name} was added with their own card.'
            : '${result.staff.name} was added.',
      );
      _closeEditor(context);
    } catch (error) {
      if (!mounted) return;
      final e = AppException.from(error);
      setState(() {
        if (e.kind == AppErrorKind.rateLimited) {
          _cooldown.startFrom(e);
          return;
        }
        final problem = classifyStaffSaveError(e);
        switch (problem) {
          case StaffSaveProblem.noSeat:
          case StaffSaveProblem.staffLimit:
            _limit = problem;
          case StaffSaveProblem.duplicateEmail:
            _fieldErrors = {
              'email':
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const gap = SizedBox(height: AppSpacing.md);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard(
          context,
          'This staff member hasn’t been added yet.',
        );
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Add staff')),
        body: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(
              top: AppSpacing.md,
              bottom: AppSpacing.xxl,
            ),
            children: [
              _page([
                if (_limit != null) ...[_LimitCallout(problem: _limit!), gap],
                if (_error != null) ...[
                  Callout(tone: CalloutTone.error, message: _error!),
                  gap,
                ],
                const SectionHeader('Details'),
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
                const SectionHeader(
                  'Sign-in',
                  subtitle: 'They’ll use these with Staff sign-in.',
                ),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  validator: Validators.email,
                  forceErrorText: _fieldErrors['email'],
                  onChanged: (_) => _clearFieldError('email'),
                  decoration: const InputDecoration(
                    labelText: 'Login email',
                    prefixIcon: Icon(Icons.alternate_email),
                    errorMaxLines: 3,
                  ),
                ),
                gap,
                PasswordField(
                  controller: _password,
                  label: 'Initial password',
                  isNewPassword: true,
                  textInputAction: TextInputAction.next,
                  validator: Validators.password,
                  errorText: _fieldErrors['password'],
                  onChanged: (_) => _clearFieldError('password'),
                  helperText: 'Share it with them privately. They can change it after signing in.',
                ),
                const SectionHeader('Digital card'),
              ]),
              ContentWidth(
                child: SwitchListTile(
                  secondary: const Icon(Icons.badge_outlined),
                  title: const Text('Create their digital card'),
                  subtitle: const Text(
                    'Uses one card slot. You can add details and a photo later.',
                  ),
                  value: _createCard,
                  onChanged: (v) => setState(() => _createCard = v),
                ),
              ),
              if (_createCard)
                _page([
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _designation,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.jobTitle],
                    decoration: const InputDecoration(
                      labelText: 'Designation on card (optional)',
                      hintText: 'e.g. Sales Manager',
                      prefixIcon: Icon(Icons.work_outline),
                    ),
                  ),
                ]),
              _page([
                const SectionHeader('Permissions'),
                Text(
                  'Everything is off by default. Staff can always view and '
                  'share their own card.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ]),
              ContentWidth(
                child: _PermissionsSection(
                  value: _permissions,
                  onChanged: (p) => setState(() => _permissions = p),
                ),
              ),
              _page([
                const SizedBox(height: AppSpacing.lg),
                CooldownSubmitButton(
                  label: 'Add staff member',
                  cooldown: _cooldown,
                  onPressed: _save,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manage existing staff

class _EditStaffForm extends ConsumerStatefulWidget {
  const _EditStaffForm({
    super.key,
    required this.member,
    this.initialCardError,
  });

  final StaffEntry member;

  /// Card step failure carried over from "Add staff".
  final Object? initialCardError;

  @override
  ConsumerState<_EditStaffForm> createState() => _EditStaffFormState();
}

class _EditStaffFormState extends ConsumerState<_EditStaffForm> {
  final _cooldown = Cooldown();
  late StaffEntry _baseline = widget.member;
  late StaffSettings _settings = StaffSettings.of(widget.member);
  String? _error;
  StaffSaveProblem? _limit;
  String? _limitPrefix;
  bool _busy = false;
  bool _creatingCard = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    final e = widget.initialCardError;
    if (e != null) _showCardError(e, justAdded: true);
  }

  @override
  void dispose() {
    _cooldown.dispose();
    super.dispose();
  }

  bool get _dirty => !_finished && _settings.changesFrom(_baseline).isNotEmpty;

  void _showCardError(Object error, {bool justAdded = false}) {
    final e = AppException.from(error);
    final problem = classifyStaffSaveError(e);
    final prefix = justAdded
        ? '${_baseline.name} was added, but their card couldn’t be created.'
        : null;
    if (problem == StaffSaveProblem.noSeat ||
        problem == StaffSaveProblem.staffLimit) {
      _limit = StaffSaveProblem.noSeat;
      _limitPrefix = prefix;
      _error = null;
    } else {
      _limit = null;
      _error = prefix == null ? e.message : '$prefix ${e.message}';
    }
  }

  Future<void> _save() async {
    if (_cooldown.active || _busy) return;
    final changes = _settings.changesFrom(_baseline);
    if (changes.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _limit = null;
    });
    try {
      await ref.read(staffMutationsProvider).update(_baseline.id, changes);
      if (!mounted) return;
      _finished = true;
      showMessage(context, 'Changes saved');
      _closeEditor(context);
    } catch (error) {
      if (!mounted) return;
      final e = AppException.from(error);
      setState(() {
        if (e.kind == AppErrorKind.rateLimited) {
          _cooldown.startFrom(e);
        } else if (e.kind == AppErrorKind.forbidden ||
            e.kind == AppErrorKind.conflict) {
          _limit = classifyStaffSaveError(e);
          _limitPrefix = null;
        } else {
          _error = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createCard() async {
    if (_creatingCard) return;
    setState(() {
      _creatingCard = true;
      _error = null;
      _limit = null;
    });
    try {
      final (entry, _) = await ref
          .read(staffMutationsProvider)
          .createCardFor(_baseline);
      if (!mounted) return;
      setState(() {
        // Keep pending edits; the new card is now part of the baseline.
        _baseline = entry;
        _settings = _settings.copyWith(
          assignedCardIds: {
            ..._settings.assignedCardIds,
            ...entry.assignedCardIds,
          }.toList(),
        );
      });
      showMessage(context, 'Card created and assigned');
    } catch (error) {
      if (mounted) setState(() => _showCardError(error));
    } finally {
      if (mounted) setState(() => _creatingCard = false);
    }
  }

  Future<void> _pickCards() async {
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (_) => _AssignCardsDialog(selected: _settings.assignedCardIds),
    );
    if (picked != null && mounted) {
      setState(() => _settings = _settings.copyWith(assignedCardIds: picked));
    }
  }

  Future<void> _toggleAccess(bool allow) async {
    if (!allow) {
      final ok = await confirmAction(
        context,
        title: 'Suspend sign-in?',
        message:
            '${_baseline.name} will be signed out on all devices and can’t sign '
            'in until you allow access again. Their cards stay as they are.',
        confirmLabel: 'Suspend',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(
      () => _settings = _settings.copyWith(
        status: allow ? StaffStatus.active : StaffStatus.suspended,
      ),
    );
  }

  Future<void> _delete() async {
    final m = _baseline;
    if (_busy) return;
    final ok = await confirmAction(
      context,
      title: 'Remove ${m.name}?',
      message:
          'Their staff sign-in will be deleted and they’ll be signed out '
          'everywhere. Cards assigned to them are kept and can be reassigned. '
          'This can’t be undone.',
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
      _closeEditor(context);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = _baseline;
    final dirty = _dirty;
    const gap = SizedBox(height: AppSpacing.md);
    final assignedIds = _settings.assignedCardIds;
    final known = {for (final c in m.cards) c.id: c};
    final unresolved = assignedIds.where((id) => !known.containsKey(id)).length;

    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard(
          context,
          'Your changes haven’t been saved.',
        );
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Staff member'),
          actions: [
            IconButton(
              tooltip: 'Remove staff member',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : _delete,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.only(
            top: AppSpacing.md,
            bottom: AppSpacing.xxl,
          ),
          children: [
            _page([
              if (_limit != null) ...[
                _LimitCallout(problem: _limit!, prefix: _limitPrefix),
                gap,
              ],
              if (_error != null) ...[
                Callout(tone: CalloutTone.error, message: _error!),
                gap,
              ],
              _IdentityCard(member: m),
              const SectionHeader('Cards'),
            ]),
            ContentWidth(
              child: Column(
                children: [
                  for (final id in assignedIds)
                    if (known[id] != null) _AssignedCardTile(card: known[id]!),
                  if (unresolved > 0)
                    ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: Text(
                        unresolved == 1
                            ? '1 other assigned card'
                            : '$unresolved other assigned cards',
                      ),
                      subtitle: const Text('Details load after saving.'),
                    ),
                  if (assignedIds.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('No card assigned'),
                      subtitle: Text(
                        'Create a card for them or assign an existing one.',
                      ),
                    ),
                ],
              ),
            ),
            _page([
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (m.cards.isEmpty)
                    FilledButton.tonalIcon(
                      onPressed: _creatingCard ? null : _createCard,
                      icon: _creatingCard
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_card_outlined),
                      label: const Text('Create card'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _pickCards,
                    icon: const Icon(Icons.playlist_add_check),
                    label: const Text('Assign cards'),
                  ),
                ],
              ),
              const SectionHeader('Sign-in access'),
            ]),
            ContentWidth(
              child: SwitchListTile(
                secondary: Icon(
                  _settings.status == StaffStatus.active
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline,
                ),
                title: const Text('Allow sign-in'),
                subtitle: Text(
                  _settings.status == StaffStatus.active
                      ? 'They can sign in with Staff sign-in.'
                      : 'Suspended: they can’t sign in.',
                ),
                value: _settings.status == StaffStatus.active,
                onChanged: _toggleAccess,
              ),
            ),
            _page([
              const SectionHeader('Permissions'),
              Text(
                'Staff can always view and share their own card.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ]),
            ContentWidth(
              child: _PermissionsSection(
                value: _settings.permissions,
                onChanged: (p) => setState(
                  () => _settings = _settings.copyWith(permissions: p),
                ),
              ),
            ),
            _page([
              const SizedBox(height: AppSpacing.lg),
              CooldownSubmitButton(
                label: dirty ? 'Save changes' : 'No changes to save',
                cooldown: _cooldown,
                onPressed: dirty && !_busy ? _save : null,
              ),
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
            ]),
          ],
        ),
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.member});

  final StaffEntry member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = member;
    return Card(
      child: Padding(
        padding: AppSpacing.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: InitialsAvatar(
                    name: m.name,
                    imageUrl: m.primaryCard?.profilePhoto,
                    radius: 28,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name, style: theme.textTheme.titleMedium),
                      if (m.email.isNotEmpty)
                        Text(m.email, style: theme.textTheme.bodyMedium),
                      if (m.phone != null)
                        Text(m.phone!, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            if (m.isSuspended) ...[
              const SizedBox(height: AppSpacing.sm),
              const StatusChip(
                'Sign-in suspended',
                tone: StatusTone.danger,
                icon: Icons.lock_outline,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Name, login email and phone can’t be changed in the app yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignedCardTile extends StatelessWidget {
  const _AssignedCardTile({required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final state = StaffCardState.ofCard(card);
    final explanation = switch (state) {
      StaffCardState.active => 'Live and shareable.',
      StaffCardState.disabled => 'Turned off and hidden from visitors.',
      StaffCardState.disabledByBilling =>
        'Inactive: no paid seat is available. Purchase seats to reactivate.',
      StaffCardState.none => '',
    };
    return ListTile(
      leading: const Icon(Icons.badge_outlined),
      title: Text(card.displayTitle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (explanation.isNotEmpty) Text(explanation),
          const SizedBox(height: AppSpacing.xs),
          StaffCardChip(state: state),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(Routes.ownerCard(card.id)),
    );
  }
}

/// Multi-select of organization cards to assign to the staff member.
class _AssignCardsDialog extends ConsumerStatefulWidget {
  const _AssignCardsDialog({required this.selected});

  final List<String> selected;

  @override
  ConsumerState<_AssignCardsDialog> createState() => _AssignCardsDialogState();
}

class _AssignCardsDialogState extends ConsumerState<_AssignCardsDialog> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(staffAssignableCardsProvider);
    return AlertDialog(
      title: const Text('Assign cards'),
      contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      content: SizedBox(
        width: 400,
        child: AsyncValueView<List<CardModel>>(
          value: cards,
          onRetry: () => ref.invalidate(staffAssignableCardsProvider),
          data: (all) => all.isEmpty
              ? const EmptyView(
                  icon: Icons.badge_outlined,
                  title: 'No cards yet',
                  message: 'Create a card first.',
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in all)
                      CheckboxListTile(
                        value: _selected.contains(c.id),
                        title: Text(c.displayTitle),
                        subtitle: Text(StaffCardState.ofCard(c).label),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(c.id);
                          } else {
                            _selected.remove(c.id);
                          }
                        }),
                      ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected.toList()),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
