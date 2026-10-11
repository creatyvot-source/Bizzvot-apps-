import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../shared/models/card.dart';

/// Parses `#RRGGBB` (or `RRGGBB`) into a [Color]; `null` when invalid.
Color? parseHexColor(String? hex) {
  final v = hex?.trim().replaceFirst('#', '');
  if (v == null || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(v)) return null;
  return Color(0xFF000000 | int.parse(v, radix: 16));
}

/// Formats a color as `#RRGGBB`.
String toHex(Color c) {
  final rgb = c.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Readable foreground (black/white) for text drawn on [background].
Color onColor(Color background) =>
    background.computeLuminance() > 0.45 ? Colors.black : Colors.white;

/// Template-aware, read-only rendering of a card as visitors will roughly
/// see it. It renders public fields only and NEVER private details
/// (blood group, father's/mother's name).
class CardPreview extends StatelessWidget {
  const CardPreview({super.key, required this.card});

  final CardModel card;

  static const _darkBackground = Color(0xFF121418);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = parseHexColor(card.brandColor) ?? theme.colorScheme.primary;
    final template = card.template;
    final dark = template == CardTemplate.modernDark;
    final background = dark ? _darkBackground : theme.colorScheme.surface;
    final foreground = dark ? Colors.white : theme.colorScheme.onSurface;
    final muted = dark ? Colors.white70 : theme.colorScheme.onSurfaceVariant;
    final centered = template != CardTemplate.corporate;

    final identity = <Widget>[
      Text(
        card.displayTitle,
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: theme.textTheme.titleLarge?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (card.pronouns != null)
        Text(
          card.pronouns!,
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      if (card.designation != null || card.company != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            [card.designation, card.company].whereType<String>().join(' · '),
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ),
      if (card.bio != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            card.bio!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: theme.textTheme.bodySmall?.copyWith(color: foreground),
          ),
        ),
    ];

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment:
            centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          ...identity,
          if (template == CardTemplate.reviewCard) _ReviewStrip(card: card, brand: brand),
          const SizedBox(height: AppSpacing.md),
          _ContactIcons(card: card, brand: brand, centered: centered),
          if (card.socialLinks.isNotEmpty || card.customLinks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                _linksSummary(card),
                style: theme.textTheme.labelMedium?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      container: true,
      label: 'Card preview, ${card.template.label} template',
      child: Material(
        color: background,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(card: card, brand: brand, background: background),
            body,
          ],
        ),
      ),
    );
  }

  static String _linksSummary(CardModel c) {
    final n = c.socialLinks.length + c.customLinks.length;
    return n == 1 ? '1 link' : '$n links';
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.card, required this.brand, required this.background});

  final CardModel card;
  final Color brand;
  final Color background;

  static const _avatarRadius = 40.0;

  @override
  Widget build(BuildContext context) {
    final avatar = _Avatar(card: card, radius: _avatarRadius, ring: brand, ringGap: background);
    Widget band(double height, {bool gradient = false, bool showCover = false}) {
      final cover = showCover ? card.coverImage : null;
      return SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: brand,
                gradient: gradient
                    ? LinearGradient(
                        colors: [brand, Color.lerp(brand, Colors.black, 0.35)!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
              ),
            ),
            if (cover != null)
              Image.network(
                cover,
                fit: BoxFit.cover,
                semanticLabel: 'Cover image',
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            if (card.logo != null)
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: _Logo(url: card.logo!),
              ),
          ],
        ),
      );
    }

    Widget overlapped(Widget header, {required bool center}) => Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header, const SizedBox(height: _avatarRadius)],
            ),
            Positioned(
              bottom: 0,
              left: center ? 0 : AppSpacing.md,
              right: center ? 0 : null,
              child: center ? Center(child: avatar) : avatar,
            ),
          ],
        );

    switch (card.template) {
      case CardTemplate.coverCard:
        return overlapped(
          LayoutBuilder(
            builder: (_, c) => band(c.maxWidth * 9 / 16, showCover: true),
          ),
          center: true,
        );
      case CardTemplate.corporate:
        return overlapped(band(72), center: false);
      case CardTemplate.profileHub:
        return overlapped(band(96, gradient: true, showCover: true), center: true);
      case CardTemplate.minimal:
      case CardTemplate.modernDark:
      case CardTemplate.reviewCard:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: Column(
            children: [
              if (card.logo != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _Logo(url: card.logo!),
                ),
              Center(child: avatar),
            ],
          ),
        );
    }
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.card,
    required this.radius,
    required this.ring,
    required this.ringGap,
  });

  final CardModel card;
  final double radius;
  final Color ring;
  final Color ringGap;

  @override
  Widget build(BuildContext context) {
    final initials = card.displayTitle
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first.toUpperCase())
        .join();
    final photo = card.profilePhoto;
    return Semantics(
      image: true,
      label: photo == null ? null : 'Profile photo of ${card.displayTitle}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: ringGap, shape: BoxShape.circle),
          child: CircleAvatar(
            radius: radius - 5,
            backgroundColor: ring.withValues(alpha: 0.15),
            foregroundImage: photo == null ? null : NetworkImage(photo),
            onForegroundImageError: photo == null ? null : (_, _) {},
            child: Text(
              initials.isEmpty ? '?' : initials,
              style: TextStyle(color: ring, fontWeight: FontWeight.w600, fontSize: radius * 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: Colors.white,
          child: Image.network(
            url,
            width: 40,
            height: 40,
            fit: BoxFit.contain,
            semanticLabel: 'Company logo',
            errorBuilder: (_, _, _) => const SizedBox.square(dimension: 40),
          ),
        ),
      );
}

class _ContactIcons extends StatelessWidget {
  const _ContactIcons({required this.card, required this.brand, required this.centered});

  final CardModel card;
  final Color brand;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String)>[
      if (card.phone != null || card.companyPhone != null) (Icons.call_outlined, 'Call'),
      if (card.whatsapp != null) (Icons.chat_outlined, 'WhatsApp'),
      if (card.email != null) (Icons.mail_outline, 'Email'),
      if (card.website != null) (Icons.language, 'Website'),
      if (card.mapLink != null || card.address != null) (Icons.place_outlined, 'Map'),
      if (card.vcardEnabled) (Icons.person_add_alt_outlined, 'Save contact'),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    final fg = onColor(brand);
    return Wrap(
      alignment: centered ? WrapAlignment.center : WrapAlignment.start,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final (icon, label) in actions)
          Semantics(
            label: label,
            excludeSemantics: true,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: brand, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: fg),
            ),
          ),
      ],
    );
  }
}

class _ReviewStrip extends StatelessWidget {
  const _ReviewStrip({required this.card, required this.brand});

  final CardModel card;
  final Color brand;

  @override
  Widget build(BuildContext context) {
    final rating = card.averageRating;
    final count = card.reviewCount;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.center,
        spacing: AppSpacing.sm,
        children: [
          const Icon(Icons.star, color: AppColors.star, size: 20),
          Text(
            rating == null
                ? 'No reviews yet'
                : '${rating.toStringAsFixed(1)}${count == null ? '' : ' ($count)'}',
            style: theme.textTheme.labelLarge,
          ),
          Chip(
            label: const Text('Leave a review'),
            side: BorderSide(color: brand),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
