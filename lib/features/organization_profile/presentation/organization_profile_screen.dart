import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utilities/validators.dart';
import '../../../shared/models/organization.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../auth/presentation/widgets/callout.dart';
import '../../auth/presentation/widgets/cooldown.dart';
import '../domain/profile_form_values.dart';
import 'organization_profile_providers.dart';

/// Owner: view and edit the organization profile, including the
/// organization-wide people directory setting (Public presence).
class OrganizationProfileScreen extends ConsumerWidget {
  const OrganizationProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(organizationProfileProvider);
    // Once loaded, keep the form mounted (refresh errors must not wipe edits).
    final loaded = profile.value;
    if (loaded != null) return _ProfileForm(profile: loaded);
    return Scaffold(
      appBar: AppBar(title: const Text('Organization profile')),
      body: AsyncValueView<OrganizationProfile>(
        value: profile,
        loadingLabel: 'Loading profile…',
        onRetry: () => ref.invalidate(organizationProfileProvider),
        data: (p) => _ProfileForm(profile: p),
      ),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.profile});

  final OrganizationProfile profile;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _website = TextEditingController();
  final _address = TextEditingController();
  final _description = TextEditingController();
  final _industry = TextEditingController();
  final _cooldown = Cooldown();

  late OrganizationProfile _baseline;
  DirectoryVisibility _visibility = DirectoryVisibility.public;
  Map<String, String> _fieldErrors = const {};
  String? _error;
  bool _saving = false;

  List<TextEditingController> get _controllers => [
    _name,
    _email,
    _phone,
    _website,
    _address,
    _description,
    _industry,
  ];

  @override
  void initState() {
    super.initState();
    _reset(widget.profile);
    for (final c in _controllers) {
      c.addListener(_onChanged);
    }
  }

  @override
  void didUpdateWidget(covariant _ProfileForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt server data refreshed elsewhere, but never clobber edits.
    if (!identical(widget.profile, oldWidget.profile) &&
        !_saving &&
        !_isDirty) {
      _reset(widget.profile);
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

  void _reset(OrganizationProfile p) {
    _baseline = p;
    final v = ProfileFormValues.fromProfile(p);
    _name.text = v.name;
    _email.text = v.email;
    _phone.text = v.phone;
    _website.text = v.website;
    _address.text = v.address;
    _description.text = v.description;
    _industry.text = v.industry;
    _visibility = v.directoryVisibility;
  }

  void _onChanged() => setState(() {});

  ProfileFormValues get _values => ProfileFormValues(
    name: _name.text.trim(),
    email: _email.text.trim(),
    phone: _phone.text.trim(),
    website: _website.text.trim(),
    address: _address.text.trim(),
    description: _description.text.trim(),
    industry: _industry.text.trim(),
    directoryVisibility: _visibility,
  );

  bool get _isDirty => _values.changesFrom(_baseline).isNotEmpty;

  Future<void> _save() async {
    if (_cooldown.active) return;
    setState(() {
      _error = null;
      _fieldErrors = const {};
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final changes = _values.changesFrom(_baseline);
    if (changes.isEmpty) return;
    FocusScope.of(context).unfocus();
    _saving = true;
    try {
      final updated = await ref
          .read(organizationProfileProvider.notifier)
          .save(changes);
      if (!mounted) return;
      setState(() => _reset(updated));
      showMessage(context, 'Profile saved');
    } catch (error) {
      if (!mounted) return;
      final e = AppException.from(error);
      setState(() {
        if (e.kind == AppErrorKind.rateLimited) {
          _cooldown.startFrom(e);
        } else if (e.kind == AppErrorKind.validation &&
            e.fieldErrors.isNotEmpty) {
          _fieldErrors = e.fieldErrors;
          _error = 'Please fix the highlighted fields.';
        } else {
          _error = e.message;
        }
      });
    } finally {
      _saving = false;
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await confirmAction(
      context,
      title: 'Discard changes?',
      message: 'Your edits to the organization profile haven’t been saved.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  void _clearFieldError(String key) {
    if (_fieldErrors.containsKey(key)) {
      setState(() => _fieldErrors = Map.of(_fieldErrors)..remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _isDirty;
    final theme = Theme.of(context);
    const gap = SizedBox(height: AppSpacing.md);

    Widget field({
      required TextEditingController controller,
      required String label,
      required String key,
      IconData? icon,
      TextInputType? keyboardType,
      Iterable<String>? autofillHints,
      FormFieldValidator<String>? validator,
      TextCapitalization capitalization = TextCapitalization.none,
      int maxLines = 1,
      String? helperText,
    }) => TextFormField(
      controller: controller,
      keyboardType:
          keyboardType ??
          (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      textInputAction: maxLines > 1
          ? TextInputAction.newline
          : TextInputAction.next,
      textCapitalization: capitalization,
      autofillHints: autofillHints,
      minLines: maxLines > 1 ? 2 : 1,
      maxLines: maxLines,
      validator: validator,
      forceErrorText: _fieldErrors[key],
      onChanged: (_) => _clearFieldError(key),
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 2,
        errorMaxLines: 3,
        prefixIcon: icon == null ? null : Icon(icon),
        alignLabelWithHint: maxLines > 1,
      ),
    );

    final slug = _baseline.slug;
    final directoryPublic = _visibility == DirectoryVisibility.public;

    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Organization profile')),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: ContentWidth(
              child: CooldownSubmitButton(
                label: dirty ? 'Save changes' : 'No changes to save',
                cooldown: _cooldown,
                onPressed: dirty ? _save : null,
              ),
            ),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            children: [
              ContentWidth(
                child: Padding(
                  padding: AppSpacing.page,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[
                        Callout(tone: CalloutTone.error, message: _error!),
                        gap,
                      ],
                      const SectionHeader('Details'),
                      field(
                        controller: _name,
                        label: 'Organization name',
                        key: 'name',
                        icon: Icons.business_outlined,
                        capitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.organizationName],
                        validator: (v) =>
                            Validators.required(v, 'Organization name'),
                      ),
                      gap,
                      field(
                        controller: _industry,
                        label: 'Industry',
                        key: 'industry',
                        icon: Icons.category_outlined,
                        capitalization: TextCapitalization.sentences,
                      ),
                      gap,
                      field(
                        controller: _description,
                        label: 'About',
                        key: 'description',
                        capitalization: TextCapitalization.sentences,
                        maxLines: 6,
                        helperText: 'A short description of what you do.',
                      ),
                      const SectionHeader('Contact'),
                      gap,
                      field(
                        controller: _email,
                        label: 'Business email',
                        key: 'email',
                        icon: Icons.mail_outline,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        validator: Validators.optionalEmail,
                      ),
                      gap,
                      field(
                        controller: _phone,
                        label: 'Phone',
                        key: 'phone',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        validator: Validators.optionalPhone,
                      ),
                      gap,
                      field(
                        controller: _website,
                        label: 'Website',
                        key: 'website',
                        icon: Icons.language,
                        keyboardType: TextInputType.url,
                        autofillHints: const [AutofillHints.url],
                        validator: Validators.optionalUrl,
                        helperText: 'Include https://',
                      ),
                      gap,
                      field(
                        controller: _address,
                        label: 'Address',
                        key: 'address',
                        icon: Icons.place_outlined,
                        keyboardType: TextInputType.streetAddress,
                        autofillHints: const [AutofillHints.fullStreetAddress],
                        capitalization: TextCapitalization.words,
                        maxLines: 3,
                      ),
                      const SectionHeader('Public presence'),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              ),
              ContentWidth(
                child: Column(
                  children: [
                    SwitchListTile(
                      value: directoryPublic,
                      onChanged: (on) => setState(() {
                        _visibility = on
                            ? DirectoryVisibility.public
                            : DirectoryVisibility.private;
                      }),
                      secondary: const Icon(Icons.groups_outlined),
                      title: const Text('Show people directory'),
                      subtitle: Text(
                        directoryPublic
                            ? 'Visitors can browse your team’s public cards on '
                                  'your directory page.'
                            : 'Your directory page is hidden. Cards can still '
                                  'be shared by direct link or QR code.',
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.visibility_outlined),
                      title: const Text('Card visibility'),
                      subtitle: const Text(
                        'Choose which cards appear in the directory.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.ownerVisibility),
                    ),
                    if (slug != null && slug.isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.preview_outlined),
                        title: const Text('Preview public directory'),
                        subtitle: Text(
                          dirty
                              ? 'Shows the saved settings. Save to preview changes.'
                              : 'See what visitors see.',
                        ),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => context.push(Routes.publicDirectory(slug)),
                      ),
                  ],
                ),
              ),
              if (_baseline.status != null)
                ContentWidth(
                  child: Padding(
                    padding: AppSpacing.page,
                    child: Text(
                      'Organization status: ${_baseline.status}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
