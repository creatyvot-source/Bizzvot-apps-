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

/// Readable foreground (black/white) for content drawn on [background].
Color onColor(Color background) =>
    background.computeLuminance() > 0.45 ? Colors.black : Colors.white;

/// Template-aware, read-only rendering of a card as a premium digital
/// business card: cover image or brand gradient, avatar overlapping the
/// cover, crisp typography and brand-colored actions.
///
/// It renders public fields only and NEVER private details (blood group,
/// father's/mother's name) — they are not referenced anywhere in this file.
class CardPreview extends StatelessWidget {
  const CardPreview({super.key, required this.card});

  final CardModel card;

  static const _darkBackground = Color(0xFF0E1015);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = parseHexColor(card.brandColor) ?? AppColors.brand;
    final style = _TemplateStyle.of(card.template);
    final dark = style.dark;
    final background = dark ? _darkBackground : Colors.white;
    final foreground = dark ? Colors.white : const Color(0xFF111827);
    final muted = dark ? Colors.white70 : const Color(0xFF6B7280);
    final align = style.centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final textAlign = style.centered ? TextAlign.center : TextAlign.start;

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(
            card.displayTitle,
            textAlign: textAlign,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          if (card.pronouns != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                card.pronouns!,
                style: theme.textTheme.labelMedium?.copyWith(color: muted),
              ),
            ),
          if (card.designation != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                card.designation!,
                textAlign: textAlign,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: dark ? brand.withValues(alpha: 0.95) : brand,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (card.company != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                card.company!,
                textAlign: textAlign,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
          if (card.bio != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text(
                card.bio!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: textAlign,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  height: 1.4,
                ),
              ),
            ),
          if (card.template == CardTemplate.reviewCard)
            _ReviewStrip(card: card, brand: brand, foreground: foreground),
          const SizedBox(height: AppSpacing.lg),
          _ContactActions(
            card: card,
            brand: brand,
            centered: style.centered,
            dark: dark,
          ),
          if (card.socialLinks.isNotEmpty || card.customLinks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: _LinksSummary(card: card, color: muted),
            ),
        ],
      ),
    );

    return Semantics(
      container: true,
      label: 'Card preview, ${card.template.label} template',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: background,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            side: dark
                ? BorderSide.none
                : BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Cover(
                card: card,
                brand: brand,
                style: style,
                background: background,
              ),
              body,
            ],
          ),
        ),
      ),
    );
  }
}

/// Per-template layout knobs.
class _TemplateStyle {
  const _TemplateStyle({
    required this.coverAspect,
    required this.avatarRadius,
    this.centered = true,
    this.dark = false,
    this.softCover = false,
  });

  /// Cover width / height.
  final double coverAspect;
  final double avatarRadius;
  final bool centered;
  final bool dark;

  /// Light brand tint instead of a saturated gradient.
  final bool softCover;

  static _TemplateStyle of(CardTemplate t) => switch (t) {
    CardTemplate.minimal => const _TemplateStyle(
      coverAspect: 4,
      avatarRadius: 44,
      softCover: true,
    ),
    CardTemplate.corporate => const _TemplateStyle(
      coverAspect: 3.2,
      avatarRadius: 42,
      centered: false,
    ),
    CardTemplate.modernDark => const _TemplateStyle(
      coverAspect: 2.6,
      avatarRadius: 46,
      dark: true,
    ),
    CardTemplate.profileHub => const _TemplateStyle(
      coverAspect: 2.4,
      avatarRadius: 54,
    ),
    CardTemplate.coverCard => const _TemplateStyle(
      coverAspect: 16 / 9,
      avatarRadius: 46,
    ),
    CardTemplate.reviewCard => const _TemplateStyle(
      coverAspect: 3,
      avatarRadius: 44,
      softCover: true,
    ),
  };
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.card,
    required this.brand,
    required this.style,
    required this.background,
  });

  final CardModel card;
  final Color brand;
  final _TemplateStyle style;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final r = style.avatarRadius;
    final gradient = style.softCover
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              brand.withValues(alpha: 0.22),
              brand.withValues(alpha: 0.06),
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              brand,
              Color.lerp(
                brand,
                style.dark ? Colors.black : const Color(0xFF7C3AED),
                0.45,
              )!,
            ],
          );
    final cover = card.coverImage;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: style.coverAspect,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
                  if (cover != null)
                    Image.network(
                      cover,
                      fit: BoxFit.cover,
                      semanticLabel: 'Cover image',
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  // Soft fade into the card body for a crisp edge.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.55, 1],
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.18),
                        ],
                      ),
                    ),
                  ),
                  if (card.logo != null)
                    Positioned(
                      top: AppSpacing.md,
                      right: AppSpacing.md,
                      child: _Logo(url: card.logo!),
                    ),
                ],
              ),
            ),
            SizedBox(height: r + AppSpacing.xs),
          ],
        ),
        Positioned(
          bottom: AppSpacing.xs,
          left: style.centered ? 0 : AppSpacing.lg,
          right: style.centered ? 0 : null,
          child: style.centered
              ? Center(
                  child: _Avatar(
                    card: card,
                    radius: r,
                    ring: background,
                    brand: brand,
                  ),
                )
              : _Avatar(card: card, radius: r, ring: background, brand: brand),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.card,
    required this.radius,
    required this.ring,
    required this.brand,
  });

  final CardModel card;
  final double radius;
  final Color ring;
  final Color brand;

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
      image: photo != null,
      label: photo == null ? null : 'Profile photo of ${card.displayTitle}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: ring,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: CircleAvatar(
          radius: radius - 4,
          backgroundColor: Color.alphaBlend(
            brand.withValues(alpha: 0.14),
            Colors.white,
          ),
          foregroundImage: photo == null ? null : NetworkImage(photo),
          onForegroundImageError: photo == null ? null : (_, _) {},
          child: Text(
            initials.isEmpty ? '?' : initials,
            style: TextStyle(
              color: brand,
              fontWeight: FontWeight.w700,
              fontSize: radius * 0.6,
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.xs),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.md),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Image.network(
        url,
        width: 36,
        height: 36,
        fit: BoxFit.contain,
        semanticLabel: 'Company logo',
        errorBuilder: (_, _, _) => const SizedBox.square(dimension: 36),
      ),
    ),
  );
}

class _ContactActions extends StatelessWidget {
  const _ContactActions({
    required this.card,
    required this.brand,
    required this.centered,
    required this.dark,
  });

  final CardModel card;
  final Color brand;
  final bool centered;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String)>[
      if (card.phone != null || card.companyPhone != null)
        (Icons.call_rounded, 'Call'),
      if (card.whatsapp != null) (Icons.chat_rounded, 'WhatsApp'),
      if (card.email != null) (Icons.mail_rounded, 'Email'),
      if (card.website != null) (Icons.language_rounded, 'Website'),
      if (card.mapLink != null || card.address != null)
        (Icons.place_rounded, 'Map'),
    ];
    final theme = Theme.of(context);
    final tint = dark
        ? brand.withValues(alpha: 0.22)
        : brand.withValues(alpha: 0.10);
    final iconColor = dark ? Colors.white : brand;
    final labelColor = dark ? Colors.white70 : const Color(0xFF374151);
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        if (actions.isNotEmpty)
          Wrap(
            alignment: centered ? WrapAlignment.center : WrapAlignment.start,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (icon, label) in actions)
                Semantics(
                  label: label,
                  excludeSemantics: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: tint,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        child: Icon(icon, size: 22, color: iconColor),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: labelColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        if (card.vcardEnabled) ...[
          if (actions.isNotEmpty) const SizedBox(height: AppSpacing.md),
          Semantics(
            label: 'Save contact button',
            excludeSemantics: true,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: brand,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 18,
                    color: onColor(brand),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      'Save contact',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: onColor(brand),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LinksSummary extends StatelessWidget {
  const _LinksSummary({required this.card, required this.color});

  final CardModel card;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final n = card.socialLinks.length + card.customLinks.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.link_rounded, size: 16, color: color),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            n == 1 ? '1 link' : '$n links',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _ReviewStrip extends StatelessWidget {
  const _ReviewStrip({
    required this.card,
    required this.brand,
    required this.foreground,
  });

  final CardModel card;
  final Color brand;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final rating = card.averageRating;
    final count = card.reviewCount;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          const Icon(Icons.star_rounded, color: AppColors.star, size: 22),
          Text(
            rating == null
                ? 'No reviews yet'
                : '${rating.toStringAsFixed(1)}${count == null ? '' : ' · $count reviews'}',
            style: theme.textTheme.labelLarge?.copyWith(color: foreground),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: brand),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              'Leave a review',
              style: theme.textTheme.labelMedium?.copyWith(color: brand),
            ),
          ),
        ],
      ),
    );
  }
}
