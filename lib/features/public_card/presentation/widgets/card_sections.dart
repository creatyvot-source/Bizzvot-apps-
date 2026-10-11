import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../shared/models/card.dart';
import '../../data/public_card_repository.dart';
import '../../domain/contact_links.dart';
import '../../domain/public_card.dart';
import 'public_widgets.dart';

typedef OpenLink = Future<void> Function(
  Uri? uri,
  String type, [
  String? target,
]);

bool hasSafeLinks(List<CardLink> links) =>
    links.any((l) => ContactLinks.web(l.url) != null);

bool hasContactDetails(PublicCard c) => [
  c.phone,
  c.companyPhone,
  c.whatsapp,
  c.email,
  c.website,
  c.address,
  c.mapLink,
].any((v) => v != null);

/// Rounded surface with a section title.
class CardSection extends StatelessWidget {
  const CardSection({
    super.key,
    required this.title,
    required this.children,
    this.flush = false,
  });

  final String title;
  final List<Widget> children;

  /// List-style content that manages its own horizontal padding.
  final bool flush;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: AppSpacing.md,
          horizontal: flush ? 0 : AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: flush ? AppSpacing.pageH : EdgeInsets.zero,
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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

/// List row with a tonal icon badge.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing = Icons.chevron_right,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final IconData trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(icon, color: scheme.onPrimaryContainer, size: 20),
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: onTap == null ? null : Icon(trailing, size: 20),
      onTap: onTap,
    );
  }
}

class ContactSection extends StatelessWidget {
  const ContactSection({super.key, required this.card, required this.onOpen});

  final PublicCard card;
  final OpenLink onOpen;

  @override
  Widget build(BuildContext context) {
    Widget tile(
      IconData icon,
      String label,
      String value,
      Uri? uri,
      String type,
    ) => _ActionTile(
      icon: icon,
      title: value,
      subtitle: label,
      onTap: uri == null ? null : () => onOpen(uri, type),
    );

    final map = card.shows(const ['map', 'maplink', 'address'])
        ? ContactLinks.map(mapLink: card.mapLink, address: card.address)
        : null;
    final tiles = <Widget>[
      if (card.phone != null && card.shows(const ['phone']))
        tile(
          Icons.call_outlined,
          'Mobile',
          card.phone!,
          ContactLinks.tel(card.phone),
          TrackType.phone,
        ),
      if (card.companyPhone != null &&
          card.shows(const ['companyPhone', 'officePhone']))
        tile(
          Icons.business_outlined,
          'Office',
          card.companyPhone!,
          ContactLinks.tel(card.companyPhone),
          TrackType.companyPhone,
        ),
      if (card.whatsapp != null && card.shows(const ['whatsapp']))
        tile(
          Icons.chat_outlined,
          'WhatsApp',
          card.whatsapp!,
          ContactLinks.whatsapp(card.whatsapp),
          TrackType.whatsapp,
        ),
      if (card.email != null && card.shows(const ['email']))
        tile(
          Icons.mail_outline,
          'Email',
          card.email!,
          ContactLinks.mailto(card.email),
          TrackType.email,
        ),
      if (card.website != null && card.shows(const ['website']))
        tile(
          Icons.language,
          'Website',
          card.website!,
          ContactLinks.web(card.website),
          TrackType.website,
        ),
      if (card.address != null && card.shows(const ['address']))
        tile(Icons.place_outlined, 'Address', card.address!, map, TrackType.map)
      else if (map != null)
        tile(Icons.map_outlined, 'Map', 'Open in maps', map, TrackType.map),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return CardSection(title: 'Contact', flush: true, children: tiles);
  }
}

String platformLabel(String type) {
  final t = type.trim().toLowerCase();
  return switch (t) {
    'x' || 'twitter' => 'X (Twitter)',
    'linkedin' => 'LinkedIn',
    'youtube' => 'YouTube',
    'tiktok' => 'TikTok',
    'whatsapp' => 'WhatsApp',
    'github' => 'GitHub',
    '' || 'custom' => 'Link',
    _ => t[0].toUpperCase() + t.substring(1),
  };
}

IconData _platformIcon(String type) => switch (type.trim().toLowerCase()) {
  'instagram' => Icons.camera_alt_outlined,
  'facebook' => Icons.facebook,
  'linkedin' => Icons.work_outline,
  'youtube' => Icons.smart_display_outlined,
  'x' || 'twitter' || 'threads' => Icons.alternate_email,
  'tiktok' => Icons.music_note_outlined,
  'telegram' => Icons.send_outlined,
  _ => Icons.public,
};

class LinksSection extends StatelessWidget {
  const LinksSection({
    super.key,
    required this.title,
    required this.links,
    required this.hub,
    required this.social,
    required this.onOpen,
  });

  final String title;
  final List<CardLink> links;

  /// profile_hub: links are the hero — large full-width buttons.
  final bool hub;
  final bool social;
  final OpenLink onOpen;

  @override
  Widget build(BuildContext context) {
    final safe = [
      for (final l in links)
        if (ContactLinks.web(l.url) case final uri?) (link: l, uri: uri),
    ];
    if (safe.isEmpty) return const SizedBox.shrink();

    String labelOf(CardLink l, Uri uri) =>
        l.label ?? (social ? platformLabel(l.type) : uri.host);
    IconData iconOf(CardLink l) => social ? _platformIcon(l.type) : Icons.link;
    void tap(CardLink l, Uri uri) => onOpen(
      uri,
      social ? TrackType.social : TrackType.custom,
      social ? l.type : (l.label ?? uri.host),
    );

    if (hub) {
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
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
                onPressed: () => tap(e.link, e.uri),
                icon: Icon(iconOf(e.link)),
                label: Text(labelOf(e.link, e.uri)),
              ),
            ),
        ],
      );
    }

    return CardSection(
      title: title,
      flush: true,
      children: [
        for (final e in safe)
          _ActionTile(
            icon: iconOf(e.link),
            title: labelOf(e.link, e.uri),
            trailing: Icons.open_in_new,
            onTap: () => tap(e.link, e.uri),
          ),
      ],
    );
  }
}

class GallerySection extends StatelessWidget {
  const GallerySection({super.key, required this.images});

  final List<MediaItem> images;

  void _view(BuildContext context, MediaItem m, int index) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: AppSpacing.page,
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
            PositionedDirectional(
              top: AppSpacing.xs,
              end: AppSpacing.xs,
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
    final safe = images.where((m) => ContactLinks.web(m.url) != null).toList();
    if (safe.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Gallery',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: safe.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) => Semantics(
              container: true,
              button: true,
              label: '${safe[i].name ?? 'Gallery image ${i + 1}'}, open',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () => _view(context, safe[i], i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: SafeNetworkImage(
                    url: safe[i].url,
                    width: 140,
                    height: 140,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MediaListSection extends StatelessWidget {
  const MediaListSection({
    super.key,
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
    return CardSection(
      title: title,
      flush: true,
      children: [
        for (var i = 0; i < safe.length; i++)
          _ActionTile(
            icon: icon,
            title: safe[i].name ?? '$fallbackName ${i + 1}',
            trailing: Icons.open_in_new,
            onTap: () => onTap(safe[i]),
          ),
      ],
    );
  }
}
