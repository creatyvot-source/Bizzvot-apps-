import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/providers.dart';
import '../../../shared/models/card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/external_actions.dart';
import '../data/public_card_repository.dart';
import '../domain/contact_links.dart';
import '../domain/public_card.dart';
import 'public_card_providers.dart';
import 'widgets/public_reviews_section.dart';
import 'widgets/public_widgets.dart';

/// Public digital card at `/card/:slug`. Works signed in or signed out; all
/// requests are anonymous.
class PublicCardScreen extends ConsumerWidget {
  const PublicCardScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(publicCardProvider(slug));
    return async.when(
      skipLoadingOnRefresh: true,
      data: (card) => _PublicCardView(slug: slug, card: card),
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const LoadingView(label: 'Loading card'),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: isUnavailableError(e)
            ? const UnavailableView()
            : ErrorView(
                error: e,
                onRetry: () => ref.invalidate(publicCardProvider(slug)),
              ),
      ),
    );
  }
}

/// `#RRGGBB` / `RRGGBB` / `#AARRGGBB` → [Color].
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// Theme for a card: seeded from its brand color; `modern_dark` is always
/// dark.
ThemeData cardThemeFor(PublicCard card, ThemeData base) {
  final seed = parseHexColor(card.brandColor);
  final dark = card.template == CardTemplate.modernDark;
  if (seed == null && !dark) return base;
  final brightness = dark ? Brightness.dark : base.brightness;
  final themeBase = brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light();
  final scheme = ColorScheme.fromSeed(
    seedColor: seed ?? AppColors.brand,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  return themeBase.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: themeBase.appBarTheme.copyWith(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
    ),
    cardTheme: themeBase.cardTheme.copyWith(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}

Rect? _originOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

class _PublicCardView extends ConsumerStatefulWidget {
  const _PublicCardView({required this.slug, required this.card});

  final String slug;
  final PublicCard card;

  @override
  ConsumerState<_PublicCardView> createState() => _PublicCardViewState();
}

class _PublicCardViewState extends ConsumerState<_PublicCardView> {
  bool _savingContact = false;

  PublicCard get card => widget.card;
  String get slug => card.slug.isNotEmpty ? card.slug : widget.slug;

  void _track(String type, [String? target]) {
    // Fire-and-forget; the repository swallows failures.
    unawaited(
      ref.read(publicCardRepositoryProvider).trackClick(slug: slug, type: type, target: target),
    );
  }

  Future<void> _open(Uri? uri, String type, [String? target]) async {
    if (uri == null) return;
    _track(type, target);
    final ok = await ref.read(externalActionsProvider).open(uri);
    if (!ok && mounted) showMessage(context, "Couldn't open this link.");
  }

  Future<void> _share(BuildContext buttonContext) async {
    _track(TrackType.share);
    final url = ref.read(envProvider).publicCardUrl(slug);
    try {
      await ref.read(externalActionsProvider).shareText(
            url,
            subject: card.displayName,
            origin: _originOf(buttonContext),
          );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _saveContact(BuildContext buttonContext) async {
    final id = card.id;
    if (_savingContact || id == null) return;
    final origin = _originOf(buttonContext);
    setState(() => _savingContact = true);
    _track(TrackType.vcard);
    try {
      final bytes = await ref.read(publicCardRepositoryProvider).fetchVcard(id);
      if (bytes.isEmpty) throw StateError('empty vcard');
      await ref.read(externalActionsProvider).shareFile(
            bytes: bytes,
            fileName: vcardFileName(card.name),
            mimeType: 'text/vcard',
            subject: card.displayName,
            origin: origin,
          );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _savingContact = false);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(publicReviewsProvider(widget.slug));
    try {
      ref.invalidate(publicCardProvider(widget.slug));
      await ref.read(publicCardProvider(widget.slug).future);
    } catch (_) {
      // The error state is rendered by the screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = cardThemeFor(card, Theme.of(context));
    final googleReview = card.template == CardTemplate.reviewCard
        ? ContactLinks.web(card.googleReviewUrl)
        : null;

    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(card.displayName),
            actions: [
              Builder(
                builder: (btn) => IconButton(
                  tooltip: 'Share card',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () => _share(btn),
                ),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                ContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CardHeader(card: card),
                      Padding(
                        padding: AppSpacing.page,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _QuickActions(
                              card: card,
                              savingContact: _savingContact,
                              onOpen: _open,
                              onSaveContact: _saveContact,
                            ),
                            if (googleReview != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              FilledButton.icon(
                                key: const ValueKey('google-review'),
                                onPressed: () => _open(googleReview, TrackType.googleReview),
                                icon: const Icon(Icons.reviews_outlined),
                                label: const Text('Review us on Google'),
                              ),
                            ],
                            for (final section in card.sectionOrder)
                              if (card.showsSection(section))
                                ..._section(section),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _section(PublicSection section) {
    final Widget? child = switch (section) {
      PublicSection.contact => [
          card.phone,
          card.companyPhone,
          card.whatsapp,
          card.email,
          card.website,
          card.address,
          card.mapLink,
        ].every((v) => v == null)
          ? null
          : _ContactSection(card: card, onOpen: _open),
      PublicSection.about => card.bio == null
          ? null
          : _SectionCard(title: 'About', children: [Text(card.bio!)]),
      PublicSection.social => !_hasSafe(card.socialLinks)
          ? null
          : _LinksSection(
          title: 'Social',
          links: card.socialLinks,
          hub: card.template == CardTemplate.profileHub,
          social: true,
          onOpen: _open,
        ),
      PublicSection.links => !_hasSafe(card.customLinks)
          ? null
          : _LinksSection(
          title: 'Links',
          links: card.customLinks,
          hub: card.template == CardTemplate.profileHub,
          social: false,
          onOpen: _open,
        ),
      PublicSection.gallery =>
        card.gallery.isEmpty ? null : _GallerySection(images: card.gallery),
      PublicSection.videos => card.videos.isEmpty
          ? null
          : _MediaListSection(
              title: 'Videos',
              items: card.videos,
              icon: Icons.play_circle_outline,
              fallbackName: 'Video',
              onTap: (m) => _open(ContactLinks.web(m.url), TrackType.video, m.name),
            ),
      PublicSection.pdfs => card.pdfs.isEmpty
          ? null
          : _MediaListSection(
              title: 'Documents',
              items: card.pdfs,
              icon: Icons.picture_as_pdf_outlined,
              fallbackName: 'Document',
              onTap: (m) => _open(ContactLinks.web(m.url), TrackType.pdf, m.name),
            ),
      PublicSection.reviews => PublicReviewsSection(slug: slug, card: card),
    };
    if (child == null) return const [];
    return [const SizedBox(height: AppSpacing.lg), child];
  }
}

bool _hasSafe(List<CardLink> links) =>
    links.any((l) => ContactLinks.web(l.url) != null);

typedef _OpenFn = Future<void> Function(Uri? uri, String type, [String? target]);

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.card});

  final PublicCard card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = card.displayName;
    switch (card.template) {
      case CardTemplate.coverCard:
        return Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: SafeNetworkImage(
                    url: card.coverImage,
                    fallback: ColoredBox(color: scheme.primary),
                  ),
                ),
                Positioned(
                  bottom: -48,
                  child: PersonAvatar(
                    name: name,
                    url: card.profilePhoto,
                    ringColor: scheme.surface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 56),
            _Identity(card: card, center: true),
          ],
        );
      case CardTemplate.corporate:
        final logo = card.organizationLogo ?? card.logo;
        return Container(
          color: scheme.primaryContainer,
          padding: AppSpacing.page,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (logo != null || card.organizationName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    children: [
                      if (logo != null)
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SafeNetworkImage(
                              url: logo,
                              width: 36,
                              height: 36,
                              fit: BoxFit.contain,
                              fallback: const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      if (card.organizationName != null)
                        Expanded(
                          child: Text(
                            card.organizationName!,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
              Row(
                children: [
                  PersonAvatar(name: name, url: card.profilePhoto, size: 72),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _Identity(
                      card: card,
                      center: false,
                      color: scheme.onPrimaryContainer,
                      showOrganization: false,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      case CardTemplate.profileHub:
      case CardTemplate.modernDark:
      case CardTemplate.reviewCard:
      case CardTemplate.minimal:
        final big = card.template == CardTemplate.profileHub;
        final ring = card.template == CardTemplate.modernDark || big;
        final avg = card.averageRating;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
            0,
          ),
          child: Column(
            children: [
              PersonAvatar(
                name: name,
                url: card.profilePhoto,
                size: big ? 120 : 96,
                ringColor: ring ? scheme.primary : null,
              ),
              const SizedBox(height: AppSpacing.md),
              _Identity(card: card, center: true),
              if (card.template == CardTemplate.reviewCard &&
                  avg != null &&
                  avg > 0 &&
                  (card.reviewCount ?? 0) > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                RatingSummary(average: avg, count: card.reviewCount!),
              ],
            ],
          ),
        );
    }
  }
}

class _Identity extends StatelessWidget {
  const _Identity({
    required this.card,
    required this.center,
    this.color,
    this.showOrganization = true,
  });

  final PublicCard card;
  final bool center;
  final Color? color;
  final bool showOrganization;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final align = center ? TextAlign.center : TextAlign.start;
    final org = showOrganization && card.organizationName != card.company
        ? card.organizationName
        : null;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            card.displayName,
            textAlign: align,
            style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w600, color: color),
          ),
        ),
        if (card.pronouns != null)
          Text('(${card.pronouns})', textAlign: align, style: t.bodySmall?.copyWith(color: muted)),
        if (card.designation != null)
          Text(card.designation!, textAlign: align, style: t.titleMedium?.copyWith(color: color)),
        if (card.company != null)
          Text(card.company!, textAlign: align, style: t.bodyMedium?.copyWith(color: muted)),
        if (org != null)
          Text(org, textAlign: align, style: t.bodyMedium?.copyWith(color: muted)),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.card,
    required this.savingContact,
    required this.onOpen,
    required this.onSaveContact,
  });

  final PublicCard card;
  final bool savingContact;
  final _OpenFn onOpen;
  final Future<void> Function(BuildContext buttonContext) onSaveContact;

  @override
  Widget build(BuildContext context) {
    final call = card.shows(const ['phone']) ? ContactLinks.tel(card.phone) : null;
    final wa = card.shows(const ['whatsapp']) ? ContactLinks.whatsapp(card.whatsapp) : null;
    final mail = card.shows(const ['email']) ? ContactLinks.mailto(card.email) : null;
    final children = <Widget>[
      if (call != null)
        FilledButton.tonalIcon(
          onPressed: () => onOpen(call, TrackType.phone),
          icon: const Icon(Icons.call_outlined),
          label: const Text('Call'),
        ),
      if (wa != null)
        FilledButton.tonalIcon(
          onPressed: () => onOpen(wa, TrackType.whatsapp),
          icon: const Icon(Icons.chat_outlined),
          label: const Text('WhatsApp'),
        ),
      if (mail != null)
        FilledButton.tonalIcon(
          onPressed: () => onOpen(mail, TrackType.email),
          icon: const Icon(Icons.mail_outline),
          label: const Text('Email'),
        ),
      if (card.canSaveContact)
        Builder(
          builder: (btn) => FilledButton.icon(
            key: const ValueKey('save-contact'),
            onPressed: savingContact ? null : () => onSaveContact(btn),
            icon: savingContact
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_outlined),
            label: const Text('Save contact'),
          ),
        ),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: children,
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children, this.padded = true});

  final String title;
  final List<Widget> children;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padded
            ? AppSpacing.page
            : const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: padded
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Semantics(
                header: true,
                child: Text(title, style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ContactSection extends StatelessWidget {
  const _ContactSection({required this.card, required this.onOpen});

  final PublicCard card;
  final _OpenFn onOpen;

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String label, String value, Uri? uri, String type) => ListTile(
          leading: Icon(icon),
          title: Text(value),
          subtitle: Text(label),
          trailing: uri == null ? null : const Icon(Icons.chevron_right),
          onTap: uri == null ? null : () => onOpen(uri, type),
        );

    final map = card.shows(const ['map', 'maplink', 'address'])
        ? ContactLinks.map(mapLink: card.mapLink, address: card.address)
        : null;
    final tiles = <Widget>[
      if (card.phone != null && card.shows(const ['phone']))
        tile(Icons.call_outlined, 'Mobile', card.phone!, ContactLinks.tel(card.phone), TrackType.phone),
      if (card.companyPhone != null && card.shows(const ['companyPhone', 'officePhone']))
        tile(Icons.business_outlined, 'Office', card.companyPhone!,
            ContactLinks.tel(card.companyPhone), TrackType.companyPhone),
      if (card.whatsapp != null && card.shows(const ['whatsapp']))
        tile(Icons.chat_outlined, 'WhatsApp', card.whatsapp!,
            ContactLinks.whatsapp(card.whatsapp), TrackType.whatsapp),
      if (card.email != null && card.shows(const ['email']))
        tile(Icons.mail_outline, 'Email', card.email!, ContactLinks.mailto(card.email), TrackType.email),
      if (card.website != null && card.shows(const ['website']))
        tile(Icons.language, 'Website', card.website!, ContactLinks.web(card.website), TrackType.website),
      if (card.address != null && card.shows(const ['address']))
        tile(Icons.place_outlined, 'Address', card.address!, map, TrackType.map)
      else if (map != null)
        tile(Icons.map_outlined, 'Map', 'Open in maps', map, TrackType.map),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return _SectionCard(title: 'Contact', padded: false, children: tiles);
  }
}

String _platformLabel(String type) {
  final t = type.trim().toLowerCase();
  return switch (t) {
    'x' || 'twitter' => 'X (Twitter)',
    'linkedin' => 'LinkedIn',
    'youtube' => 'YouTube',
    'tiktok' => 'TikTok',
    'whatsapp' => 'WhatsApp',
    '' || 'custom' => 'Link',
    _ => t[0].toUpperCase() + t.substring(1),
  };
}

class _LinksSection extends StatelessWidget {
  const _LinksSection({
    required this.title,
    required this.links,
    required this.hub,
    required this.social,
    required this.onOpen,
  });

  final String title;
  final List<CardLink> links;
  final bool hub;
  final bool social;
  final _OpenFn onOpen;

  @override
  Widget build(BuildContext context) {
    final safe = [
      for (final l in links)
        if (ContactLinks.web(l.url) case final uri?) (link: l, uri: uri),
    ];
    if (safe.isEmpty) return const SizedBox.shrink();

    String labelOf(CardLink l, Uri uri) =>
        l.label ?? (social ? _platformLabel(l.type) : uri.host);
    void tap(CardLink l, Uri uri) => onOpen(
          uri,
          social ? TrackType.social : TrackType.custom,
          social ? l.type : (l.label ?? uri.host),
        );

    if (hub) {
      // profile_hub: links are the hero — full-width buttons.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final e in safe)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: OutlinedButton.icon(
                onPressed: () => tap(e.link, e.uri),
                icon: Icon(social ? Icons.public : Icons.link),
                label: Text(labelOf(e.link, e.uri)),
              ),
            ),
        ],
      );
    }

    return _SectionCard(
      title: title,
      padded: false,
      children: [
        for (final e in safe)
          ListTile(
            leading: Icon(social ? Icons.public : Icons.link),
            title: Text(labelOf(e.link, e.uri)),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => tap(e.link, e.uri),
          ),
      ],
    );
  }
}

class _GallerySection extends StatelessWidget {
  const _GallerySection({required this.images});

  final List<MediaItem> images;

  void _view(BuildContext context, MediaItem m, int index) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: SafeNetworkImage(
                  url: m.url,
                  fit: BoxFit.contain,
                  semanticLabel: m.name ?? 'Gallery image ${index + 1}',
                ),
              ),
            ),
            Positioned(
              top: AppSpacing.xs,
              right: AppSpacing.xs,
              child: IconButton.filledTonal(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Gallery', style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) => Semantics(
              button: true,
              label: '${images[i].name ?? 'Gallery image ${i + 1}'}, open',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _view(context, images[i], i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SafeNetworkImage(url: images[i].url, width: 120, height: 120),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MediaListSection extends StatelessWidget {
  const _MediaListSection({
    required this.title,
    required this.items,
    required this.icon,
    required this.fallbackName,
    required this.onTap,
  });

  final String title;
  final List<MediaItem> items;
  final IconData icon;
  final String fallbackName;
  final void Function(MediaItem) onTap;

  @override
  Widget build(BuildContext context) {
    final safe = items.where((m) => ContactLinks.web(m.url) != null).toList();
    if (safe.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: title,
      padded: false,
      children: [
        for (var i = 0; i < safe.length; i++)
          ListTile(
            leading: Icon(icon),
            title: Text(safe[i].name ?? '$fallbackName ${i + 1}'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => onTap(safe[i]),
          ),
      ],
    );
  }
}
