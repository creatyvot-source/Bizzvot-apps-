import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/auth/auth_user.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utilities/json.dart';
import '../../../core/utilities/validators.dart';
import '../../../shared/models/card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/media_picker.dart';
import '../domain/card_edit_sections.dart';
import '../domain/display_sections.dart';
import '../domain/media_rules.dart';
import 'cards_providers.dart';
import 'widgets/card_preview.dart';
import 'widgets/editor_widgets.dart';

/// Edits a card. Owners edit any card (`/organization/cards/:id`); staff edit
/// their own card (`/staff/card`) limited to the sections their permissions
/// allow (`editCard` → content, `manageLinks` → links).
class CardEditorScreen extends ConsumerWidget {
  const CardEditorScreen({super.key, this.cardId, this.staffMode = false});

  final String? cardId;
  final bool staffMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = (cardId: cardId, staffMode: staffMode);
    final sections = staffMode
        ? CardEditSection.forStaff(
            ref.watch(currentUserProvider.select((u) => u?.permissions)) ??
                StaffPermissions.none,
          )
        : CardEditSection.ownerSections;

    if (sections.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit card')),
        body: const EmptyView(
          icon: Icons.lock_outline,
          title: 'You can’t edit this card',
          message:
              'Your organization owner has not given you permission to edit your card '
              'or manage its links.',
        ),
      );
    }

    final async = ref.watch(cardForProvider(target));
    final card = async.value;
    if (card != null) {
      return CardEditorForm(
        key: ValueKey('editor-${card.id}'),
        initial: card,
        target: target,
        sections: sections,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Edit card')),
      body: AsyncValueView<CardModel?>(
        value: async,
        loadingLabel: 'Loading card',
        onRetry: () => ref.invalidate(cardForProvider(target)),
        data: (_) => const EmptyView(
          icon: Icons.badge_outlined,
          title: 'No card assigned',
          message: 'There is no card to edit yet.',
        ),
      ),
    );
  }
}

/// The stateful editor for a loaded card.
class CardEditorForm extends ConsumerStatefulWidget {
  const CardEditorForm({
    super.key,
    required this.initial,
    required this.target,
    required this.sections,
  });

  final CardModel initial;
  final CardRef target;
  final Set<CardEditSection> sections;

  @override
  ConsumerState<CardEditorForm> createState() => _CardEditorFormState();
}

class _CardEditorFormState extends ConsumerState<CardEditorForm> {
  static const _textKeys = [
    'title',
    'designation',
    'company',
    'pronouns',
    'bio',
    'phone',
    'companyPhone',
    'whatsapp',
    'email',
    'website',
    'address',
    'mapLink',
    'fatherName',
    'motherName',
    'brandColor',
    'googleReviewUrl',
  ];
  static const bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _dirty = ValueNotifier(false);
  final _serverErrors = <String, String>{};
  final _uploads = <String, double>{};
  final _cancelTokens = <String, CancelToken>{};
  final _removedLibraryUrls = <String>{};

  late CardModel _baseline;
  String? _profilePhoto;
  String? _coverImage;
  String? _logo;
  String? _bloodGroup;
  late List<CardLink> _social;
  late List<CardLink> _custom;
  late List<MediaItem> _gallery;
  late List<MediaItem> _pdfs;
  late List<MediaItem> _videos;
  late CardTemplate _template;
  late List<String> _sectionOrder;
  late Map<String, bool> _toggles;
  late bool _vcard;
  late CardVisibility _visibility;
  bool _saving = false;
  int _uploadSeq = 0;

  bool _can(CardEditSection s) => widget.sections.contains(s);

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    // Normalise so a merged default order does not count as a change.
    _baseline = c.copyWith(sectionOrder: DisplaySections.merge(c.sectionOrder));
    final json = _baseline.toUpdateJson();
    for (final k in _textKeys) {
      final ctl = TextEditingController(text: (json[k] as String?) ?? '');
      ctl.addListener(() {
        _serverErrors.remove(k);
        _recomputeDirty();
      });
      _controllers[k] = ctl;
    }
    _profilePhoto = c.profilePhoto;
    _coverImage = c.coverImage;
    _logo = c.logo;
    _bloodGroup = c.bloodGroup;
    _social = [...c.socialLinks];
    _custom = [...c.customLinks];
    _gallery = [...c.gallery];
    _pdfs = [...c.pdfs];
    _videos = [...c.videos];
    _template = c.template;
    _sectionOrder = [..._baseline.sectionOrder];
    _toggles = {...c.displayToggles};
    _vcard = c.vcardEnabled;
    _visibility = c.visibility;
  }

  @override
  void dispose() {
    for (final t in _cancelTokens.values) {
      t.cancel('Editor closed');
    }
    for (final c in _controllers.values) {
      c.dispose();
    }
    _dirty.dispose();
    super.dispose();
  }

  TextEditingController _c(String key) => _controllers[key]!;

  /// The card as currently edited.
  CardModel _current() {
    String? text(String k) {
      final v = _c(k).text.trim();
      return v.isEmpty ? null : v;
    }

    final clear = <String>{
      for (final k in _textKeys)
        if (text(k) == null) k,
      if (_profilePhoto == null) 'profilePhoto',
      if (_coverImage == null) 'coverImage',
      if (_logo == null) 'logo',
      if (_bloodGroup == null) 'bloodGroup',
    };
    return _baseline.copyWith(
      title: text('title'),
      designation: text('designation'),
      company: text('company'),
      pronouns: text('pronouns'),
      bio: text('bio'),
      phone: text('phone'),
      companyPhone: text('companyPhone'),
      whatsapp: text('whatsapp'),
      email: text('email'),
      website: text('website'),
      address: text('address'),
      mapLink: text('mapLink'),
      fatherName: text('fatherName'),
      motherName: text('motherName'),
      brandColor: text('brandColor')?.toUpperCase(),
      googleReviewUrl: text('googleReviewUrl'),
      bloodGroup: _bloodGroup,
      profilePhoto: _profilePhoto,
      coverImage: _coverImage,
      logo: _logo,
      socialLinks: _social,
      customLinks: _custom,
      gallery: _gallery,
      pdfs: _pdfs,
      videos: _videos,
      template: _template,
      sectionOrder: _sectionOrder,
      displayToggles: _toggles,
      vcardEnabled: _vcard,
      visibility: _visibility,
      clear: clear,
    );
  }

  Json get _patch => buildCardPatch(_baseline, _current(), widget.sections);

  void _recomputeDirty() => _dirty.value = _patch.isNotEmpty;

  void _update(VoidCallback change) {
    setState(change);
    _recomputeDirty();
  }

  // ------------------------------------------------------------ uploads

  Future<PickedFile?> _pickOne() async {
    try {
      return await ref.read(mediaPickerProvider).pickImage();
    } on PlatformException {
      if (mounted) {
        showMessage(context, 'Photo access is needed to choose an image.');
      }
      return null;
    }
  }

  /// Runs an upload under [slot] with progress; returns the URL or null.
  Future<String?> _runUpload(
    String slot,
    Future<String> Function(void Function(double) onProgress, CancelToken token)
    upload,
  ) async {
    final token = CancelToken();
    setState(() {
      _uploads[slot] = 0;
      _cancelTokens[slot] = token;
    });
    try {
      return await upload((p) {
        if (mounted) setState(() => _uploads[slot] = p);
      }, token);
    } catch (e) {
      if (mounted) showError(context, e);
      return null;
    } finally {
      _cancelTokens.remove(slot);
      if (mounted) setState(() => _uploads.remove(slot));
    }
  }

  Future<void> _pickSingleImage(String slot) async {
    final file = await _pickOne();
    if (file == null || !mounted) return;
    final error = MediaRules.validateImage(file.bytes);
    if (error != null) {
      showMessage(context, error);
      return;
    }
    final actions = ref.read(cardActionsProvider);
    final url = await _runUpload(
      slot,
      (onProgress, token) =>
          actions.uploadImage(file, onProgress: onProgress, cancelToken: token),
    );
    if (url == null || !mounted) return;
    _update(() {
      switch (slot) {
        case 'profilePhoto':
          _profilePhoto = url;
        case 'coverImage':
          _coverImage = url;
        case 'logo':
          _logo = url;
      }
    });
  }

  int _inFlight(String prefix) =>
      _uploads.keys.where((k) => k.startsWith(prefix)).length;

  Future<void> _addGalleryImages() async {
    final remaining = MediaRules.remaining(
      _gallery.length + _inFlight('gallery:'),
      CardLimits.gallery,
    );
    if (remaining == 0) return;
    List<PickedFile> files;
    try {
      files = await ref.read(mediaPickerProvider).pickImages(limit: remaining);
    } on PlatformException {
      if (mounted) {
        showMessage(context, 'Photo access is needed to choose images.');
      }
      return;
    }
    if (!mounted || files.isEmpty) return;
    if (files.length > remaining) {
      showMessage(
        context,
        'Only $remaining more image${remaining == 1 ? '' : 's'} can be added.',
      );
      files = files.take(remaining).toList();
    }
    final actions = ref.read(cardActionsProvider);
    for (final f in files) {
      final error = MediaRules.validateImage(f.bytes);
      if (error != null) {
        if (mounted) showMessage(context, '${f.name}: $error');
        continue;
      }
      final url = await _runUpload(
        'gallery:${_uploadSeq++}',
        (onProgress, token) =>
            actions.uploadImage(f, onProgress: onProgress, cancelToken: token),
      );
      if (url == null || !mounted) continue;
      _update(
        () => _gallery = [
          ..._gallery,
          MediaItem(url: url, kind: 'image', name: f.name),
        ],
      );
    }
  }

  Future<void> _addPdfs() async {
    final remaining = MediaRules.remaining(
      _pdfs.length + _inFlight('pdf:'),
      CardLimits.pdfs,
    );
    if (remaining == 0) return;
    List<PickedFile> files;
    try {
      files = await ref.read(mediaPickerProvider).pickPdfs(limit: remaining);
    } on PlatformException {
      if (mounted) {
        showMessage(context, 'File access is needed to choose a PDF.');
      }
      return;
    }
    if (!mounted || files.isEmpty) return;
    final actions = ref.read(cardActionsProvider);
    for (final f in files.take(remaining)) {
      final error = MediaRules.validatePdf(f.bytes);
      if (error != null) {
        if (mounted) showMessage(context, '${f.name}: $error');
        continue;
      }
      final url = await _runUpload(
        'pdf:${_uploadSeq++}',
        (onProgress, token) => actions.uploadDocument(
          _baseline.id,
          f,
          onProgress: onProgress,
          cancelToken: token,
        ),
      );
      if (url == null || !mounted) continue;
      _update(
        () =>
            _pdfs = [..._pdfs, MediaItem(url: url, kind: 'pdf', name: f.name)],
      );
    }
  }

  Future<void> _addVideo() async {
    if (_videos.length >= CardLimits.videos) return;
    final url = await askYoutubeUrl(context);
    if (url == null || !mounted) return;
    final id = MediaRules.youtubeId(url);
    if (_videos.any((v) => MediaRules.youtubeId(v.url) == id)) {
      showMessage(context, 'This video is already on the card.');
      return;
    }
    _update(() => _videos = [..._videos, MediaItem(url: url, kind: 'youtube')]);
  }

  void _removeLibraryItem(MediaItem item, {required bool pdf}) {
    _update(() {
      if (pdf) {
        _pdfs = [..._pdfs]..remove(item);
      } else {
        _gallery = [..._gallery]..remove(item);
      }
      _removedLibraryUrls.add(item.url);
    });
  }

  void _setToggle(String key, bool visible) {
    _update(() {
      final original = _baseline.displayToggles;
      if (!original.containsKey(key) && visible) {
        _toggles = {..._toggles}..remove(key);
      } else {
        _toggles = {..._toggles, key: visible};
      }
    });
  }

  // --------------------------------------------------------------- save

  Future<void> _save() async {
    if (_saving || _uploads.isNotEmpty) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      showMessage(context, 'Please fix the highlighted fields.');
      return;
    }
    final patch = _patch;
    if (patch.isEmpty) {
      showMessage(context, 'No changes to save');
      return;
    }
    setState(() => _saving = true);
    final actions = ref.read(cardActionsProvider);
    try {
      final saved = await actions.save(widget.target, _baseline.id, patch);
      final stillUsed = {
        ...saved.gallery,
        ...saved.pdfs,
      }.map((m) => m.url).toSet();
      final toRemove = _removedLibraryUrls
          .where((u) => !stillUsed.contains(u))
          .toList();
      final failed = toRemove.isEmpty
          ? 0
          : await actions.removeLibraryFiles(_baseline.id, toRemove);
      _removedLibraryUrls.clear();
      // The edited state is now the saved state.
      _baseline = _current();
      _dirty.value = false;
      if (!mounted) return;
      showMessage(
        context,
        failed > 0
            ? 'Card saved. Some removed files could not be deleted.'
            : 'Card saved',
      );
      if (context.canPop()) context.pop();
    } on AppException catch (e) {
      if (!mounted) return;
      if (e.fieldErrors.isNotEmpty) {
        _serverErrors
          ..clear()
          ..addAll(e.fieldErrors);
        _formKey.currentState?.validate();
      }
      showError(context, e);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await confirmAction(
      context,
      title: 'Discard changes?',
      message: 'You have unsaved changes to this card. They will be lost.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  // ----------------------------------------------------------------- UI

  FormFieldValidator<String> _v(
    String key, [
    FormFieldValidator<String>? base,
  ]) =>
      (value) => _serverErrors[key] ?? base?.call(value);

  Widget _field(
    String key,
    String label, {
    FormFieldValidator<String>? validator,
    TextInputType? keyboard,
    int? maxLength,
    int maxLines = 1,
    String? helper,
    IconData? icon,
    Iterable<String>? autofill,
    TextCapitalization caps = TextCapitalization.none,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: TextFormField(
      controller: _c(key),
      keyboardType: maxLines > 1 ? TextInputType.multiline : keyboard,
      maxLength: maxLength,
      minLines: maxLines > 1 ? 2 : 1,
      maxLines: maxLines,
      textCapitalization: caps,
      autofillHints: autofill,
      autocorrect:
          keyboard != TextInputType.url &&
          keyboard != TextInputType.emailAddress,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        prefixIcon: icon == null ? null : Icon(icon),
      ),
      validator: _v(key, validator),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _uploads.isNotEmpty;
    return ValueListenableBuilder<bool>(
      valueListenable: _dirty,
      builder: (context, dirty, child) => PopScope(
        canPop: !dirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmDiscard();
        },
        child: child!,
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.target.staffMode ? 'Edit my card' : 'Edit card'),
          actions: [
            ValueListenableBuilder<bool>(
              valueListenable: _dirty,
              builder: (context, dirty, _) => Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: _saving
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton(
                        onPressed: dirty && !busy ? _save : null,
                        child: const Text('Save'),
                      ),
              ),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ContentWidth(
            child: AbsorbPointer(
              absorbing: _saving,
              child: SingleChildScrollView(
                padding: AppSpacing.page,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_uploads.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: Text(
                          'Uploading… you can save when uploads finish.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    for (final section in _orderedSections()) ...[
                      section,
                      const SizedBox(height: AppSpacing.md),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _orderedSections() => [
    if (_can(CardEditSection.appearance)) _appearanceSection(),
    if (_can(CardEditSection.identity)) _identitySection(),
    if (_can(CardEditSection.images)) _imagesSection(),
    if (_can(CardEditSection.contact)) _contactSection(),
    if (_can(CardEditSection.links)) _linksSection(),
    if (_can(CardEditSection.media)) _mediaSection(),
    if (_can(CardEditSection.privateDetails)) _privateSection(),
    if (_can(CardEditSection.visibility)) _visibilitySection(),
  ];

  Widget _identitySection() => EditorSection(
    title: 'Identity',
    icon: Icons.person_outline,
    children: [
      _field(
        'title',
        'Name on card',
        maxLength: 80,
        autofill: const [AutofillHints.name],
        caps: TextCapitalization.words,
      ),
      _field(
        'designation',
        'Designation',
        maxLength: 80,
        autofill: const [AutofillHints.jobTitle],
        caps: TextCapitalization.words,
      ),
      _field(
        'company',
        'Company',
        maxLength: 80,
        autofill: const [AutofillHints.organizationName],
        caps: TextCapitalization.words,
      ),
      _field(
        'pronouns',
        'Pronouns',
        maxLength: 30,
        helper: 'Optional, e.g. she/her',
      ),
      _field(
        'bio',
        'Bio',
        maxLength: 500,
        maxLines: 6,
        caps: TextCapitalization.sentences,
      ),
    ],
  );

  Widget _imagesSection() => EditorSection(
    title: 'Images',
    icon: Icons.image_outlined,
    subtitle: 'JPG, PNG or WebP, up to 5 MB each.',
    children: [
      for (final (slot, label, url) in [
        ('profilePhoto', 'Profile photo', _profilePhoto),
        ('coverImage', 'Cover image', _coverImage),
        ('logo', 'Logo', _logo),
      ])
        ImageSlotTile(
          label: label,
          url: url,
          progress: _uploads[slot],
          enabled: !_saving,
          onPick: () => _pickSingleImage(slot),
          onRemove: () => _update(() {
            switch (slot) {
              case 'profilePhoto':
                _profilePhoto = null;
              case 'coverImage':
                _coverImage = null;
              case 'logo':
                _logo = null;
            }
          }),
        ),
    ],
  );

  Widget _contactSection() => EditorSection(
    title: 'Contact',
    icon: Icons.contact_phone_outlined,
    children: [
      _field(
        'phone',
        'Phone',
        keyboard: TextInputType.phone,
        icon: Icons.call_outlined,
        validator: Validators.optionalPhone,
        autofill: const [AutofillHints.telephoneNumber],
        helper: 'Include the country code, e.g. +91 98765 43210',
      ),
      _field(
        'companyPhone',
        'Company phone',
        keyboard: TextInputType.phone,
        icon: Icons.business_outlined,
        validator: Validators.optionalPhone,
      ),
      _field(
        'whatsapp',
        'WhatsApp number',
        keyboard: TextInputType.phone,
        icon: Icons.chat_outlined,
        validator: Validators.optionalPhone,
      ),
      _field(
        'email',
        'Email',
        keyboard: TextInputType.emailAddress,
        icon: Icons.mail_outline,
        validator: Validators.optionalEmail,
        autofill: const [AutofillHints.email],
      ),
      _field(
        'website',
        'Website',
        keyboard: TextInputType.url,
        icon: Icons.language,
        validator: Validators.optionalUrl,
        autofill: const [AutofillHints.url],
      ),
      _field(
        'address',
        'Address',
        maxLines: 3,
        maxLength: 300,
        icon: Icons.place_outlined,
      ),
      _field(
        'mapLink',
        'Map link',
        keyboard: TextInputType.url,
        icon: Icons.map_outlined,
        validator: Validators.optionalUrl,
        helper: 'A Google Maps or Apple Maps share link',
      ),
    ],
  );

  Widget _privateSection() {
    final scheme = Theme.of(context).colorScheme;
    final groups = {...bloodGroups, ?_bloodGroup}.toList();
    return EditorSection(
      title: 'Private details',
      subtitle: 'Private · never shown publicly. Only your organization can see these.',
      icon: Icons.lock_outline,
      color: scheme.surfaceContainerHigh,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: DropdownButtonFormField<String?>(
            initialValue: _bloodGroup,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Blood group (private)',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Not set'),
              ),
              for (final g in groups)
                DropdownMenuItem<String?>(value: g, child: Text(g)),
            ],
            onChanged: (v) => _update(() => _bloodGroup = v),
          ),
        ),
        _field(
          'fatherName',
          'Father’s name (private)',
          maxLength: 80,
          caps: TextCapitalization.words,
        ),
        _field(
          'motherName',
          'Mother’s name (private)',
          maxLength: 80,
          caps: TextCapitalization.words,
        ),
      ],
    );
  }

  Widget _linksSection() => EditorSection(
    title: 'Social & custom links',
    icon: Icons.link,
    subtitle: 'Secure https:// links only. Drag to change the order.',
    children: [
      LinkListEditor(
        title: 'Social links',
        social: true,
        links: _social,
        onChanged: (l) => _update(() => _social = l),
      ),
      const Divider(height: AppSpacing.lg),
      LinkListEditor(
        title: 'Custom links',
        social: false,
        links: _custom,
        onChanged: (l) => _update(() => _custom = l),
      ),
    ],
  );

  Widget _mediaSection() {
    final theme = Theme.of(context);
    final galleryUploads = _uploads.entries
        .where((e) => e.key.startsWith('gallery:'))
        .toList();
    final pdfUploads = _uploads.entries
        .where((e) => e.key.startsWith('pdf:'))
        .toList();
    final galleryCount = _gallery.length + galleryUploads.length;
    final pdfCount = _pdfs.length + pdfUploads.length;
    Widget counter(String label, int n, int max) => Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
        Text('$n of $max', style: theme.textTheme.labelMedium),
      ],
    );
    return EditorSection(
      title: 'Gallery, documents & videos',
      icon: Icons.perm_media_outlined,
      children: [
        counter('Gallery', galleryCount, CardLimits.gallery),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (i, item) in _gallery.indexed)
              _GalleryThumb(
                item: item,
                index: i,
                onRemove: _saving
                    ? null
                    : () => _removeLibraryItem(item, pdf: false),
              ),
            for (final u in galleryUploads)
              SizedBox.square(
                dimension: 88,
                child: Center(
                  child: CircularProgressIndicator(
                    value: u.value > 0 ? u.value : null,
                    semanticsLabel: 'Uploading gallery image',
                  ),
                ),
              ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: galleryCount >= CardLimits.gallery || _saving
                ? null
                : _addGalleryImages,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              galleryCount >= CardLimits.gallery
                  ? 'Gallery is full'
                  : 'Add images',
            ),
          ),
        ),
        const Divider(height: AppSpacing.lg),
        counter('PDF documents', pdfCount, CardLimits.pdfs),
        for (final item in _pdfs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(
              item.name ??
                  Uri.tryParse(item.url)?.pathSegments.lastOrNull ??
                  'Document',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: 'Remove document',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving
                  ? null
                  : () => _removeLibraryItem(item, pdf: true),
            ),
          ),
        for (final u in pdfUploads)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_file),
            title: LinearProgressIndicator(
              value: u.value > 0 ? u.value : null,
              semanticsLabel: 'Uploading document',
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: pdfCount >= CardLimits.pdfs || _saving ? null : _addPdfs,
            icon: const Icon(Icons.note_add_outlined),
            label: Text(
              pdfCount >= CardLimits.pdfs
                  ? 'Document limit reached'
                  : 'Add PDF (up to 10 MB)',
            ),
          ),
        ),
        const Divider(height: AppSpacing.lg),
        counter('YouTube videos', _videos.length, CardLimits.videos),
        for (final (i, item) in _videos.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.smart_display_outlined),
            title: Text('Video ${i + 1}'),
            subtitle: Text(
              item.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: 'Remove video ${i + 1}',
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  _update(() => _videos = [..._videos]..removeAt(i)),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _videos.length >= CardLimits.videos ? null : _addVideo,
            icon: const Icon(Icons.add_link),
            label: Text(
              _videos.length >= CardLimits.videos
                  ? 'Video limit reached'
                  : 'Add YouTube video',
            ),
          ),
        ),
      ],
    );
  }

  Widget _appearanceSection() {
    final previewListenable = Listenable.merge([
      _c('title'),
      _c('designation'),
      _c('company'),
      _c('pronouns'),
      _c('bio'),
      _c('brandColor'),
      _c('phone'),
      _c('email'),
      _c('website'),
      _c('whatsapp'),
    ]);
    return EditorSection(
      title: 'Template & layout',
      icon: Icons.palette_outlined,
      children: [
        ListenableBuilder(
          listenable: previewListenable,
          builder: (_, _) => CardPreview(card: _current()),
        ),
        fieldGap,
        Text('Template', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final t in CardTemplate.values)
              ChoiceChip(
                label: Text(t.label),
                selected: _template == t,
                onSelected: (_) => _update(() => _template = t),
              ),
          ],
        ),
        fieldGap,
        BrandColorPicker(
          controller: _c('brandColor'),
          onChanged: () => setState(() {}),
        ),
        _field(
          'googleReviewUrl',
          'Google review link',
          keyboard: TextInputType.url,
          validator: MediaRules.optionalHttpsLink,
          helper: 'Shown as a button on the Review card template.',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Save contact (vCard)'),
          subtitle: const Text('Let visitors download your contact details.'),
          value: _vcard,
          onChanged: (v) => _update(() => _vcard = v),
        ),
        const Divider(height: AppSpacing.lg),
        Text('Sections', style: Theme.of(context).textTheme.titleSmall),
        Text(
          'Drag to change the order on the public card. Switch off to hide a section.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SectionOrderEditor(
          order: _sectionOrder,
          toggles: _toggles,
          onReorder: (o) => _update(() => _sectionOrder = o),
          onToggle: _setToggle,
        ),
      ],
    );
  }

  Widget _visibilitySection() => EditorSection(
    title: 'Directory visibility',
    icon: Icons.visibility_outlined,
    subtitle:
        'Controls whether this card is listed in your public people directory.',
    children: [
      VisibilitySelector(
        value: _visibility,
        onChanged: (v) => _update(() => _visibility = v),
      ),
    ],
  );
}

class _GalleryThumb extends StatelessWidget {
  const _GalleryThumb({
    required this.item,
    required this.index,
    required this.onRemove,
  });

  final MediaItem item;
  final int index;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 88,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Image.network(
                item.url,
                fit: BoxFit.cover,
                semanticLabel: 'Gallery image ${index + 1}',
                errorBuilder: (_, _, _) =>
                    Icon(Icons.broken_image_outlined, color: scheme.outline),
              ),
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: IconButton(
              tooltip: 'Remove gallery image ${index + 1}',
              onPressed: onRemove,
              style: IconButton.styleFrom(
                backgroundColor: scheme.surface.withValues(alpha: 0.85),
              ),
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
