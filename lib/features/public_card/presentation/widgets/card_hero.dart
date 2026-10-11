import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../shared/models/card.dart';
import '../../domain/public_card.dart';
import 'public_reviews_section.dart';
import 'public_widgets.dart';

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
/// dark. Without a brand color the app theme is used unchanged.
ThemeData cardThemeFor(PublicCard card, ThemeData base) {
  final seed = parseHexColor(card.brandColor);
  final dark = card.template == CardTemplate.modernDark;
  if (seed == null && !dark) return base;
  final brightness = dark ? Brightness.dark : base.brightness;
  final themeBase = brightness == Brightness.dark
      ? AppTheme.dark()
      : AppTheme.light();
  if (seed == null) return themeBase;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    surface: themeBase.colorScheme.surface,
  );
  return themeBase.copyWith(
    colorScheme: scheme,
    progressIndicatorTheme: themeBase.progressIndicatorTheme.copyWith(
      color: scheme.primary,
      linearTrackColor: scheme.primaryContainer,
    ),
  );
}

/// Full-bleed hero background derived from the card's brand color.
Gradient heroGradientFor(PublicCard card) {
  final seed = parseHexColor(card.brandColor);
  final dark = card.template == CardTemplate.modernDark;
  if (seed == null) {
    return dark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF111827), Color(0xFF312E81)],
          )
        : AppColors.heroGradient;
  }
  final hsl = HSLColor.fromColor(seed);
  final shifted = hsl
      .withHue((hsl.hue + 28) % 360)
      .withLightness((hsl.lightness * (dark ? 0.55 : 0.85)).clamp(0.12, 0.6))
      .toColor();
  final start = dark
      ? hsl.withLightness((hsl.lightness * 0.45).clamp(0.08, 0.3)).toColor()
      : seed;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [start, shifted],
  );
}

/// Template-aware header: full-bleed cover or gradient, overlapping avatar,
/// identity block.
class CardHero extends StatelessWidget {
  const CardHero({super.key, required this.card, required this.topInset});

  final PublicCard card;

  /// Status bar + app bar height, so the hero extends behind them.
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = card.template;
    final corporate = t == CardTemplate.corporate;
    final hub = t == CardTemplate.profileHub;
    final avatarSize = hub ? 128.0 : (corporate ? 96.0 : 112.0);
    final bandHeight =
        topInset +
        (t == CardTemplate.coverCard
            ? 168
            : (t == CardTemplate.minimal ? 72 : 120));
    final useCover =
        t == CardTemplate.coverCard ||
        (card.coverImage != null && t != CardTemplate.minimal && !corporate);
    final logo = card.organizationLogo ?? card.logo;
    final avg = card.averageRating;

    final background = DecoratedBox(
      decoration: BoxDecoration(
        gradient: t == CardTemplate.minimal ? null : heroGradientFor(card),
        color: t == CardTemplate.minimal
            ? scheme.primaryContainer.withValues(alpha: 0.6)
            : null,
      ),
      child: useCover
          ? Stack(
              fit: StackFit.expand,
              children: [
                SafeNetworkImage(
                  url: card.coverImage,
                  fallback: const SizedBox.shrink(),
                ),
                // Scrim keeps the app-bar icons legible over photos.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x66000000), Color(0x00000000)],
                      stops: [0, 0.6],
                    ),
                  ),
                ),
              ],
            )
          : const SizedBox.expand(),
    );

    return Column(
      crossAxisAlignment: corporate
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: corporate
              ? AlignmentDirectional.bottomStart
              : AlignmentDirectional.bottomCenter,
          children: [
            SizedBox(
              height: bandHeight,
              width: double.infinity,
              child: background,
            ),
            if (corporate && (logo != null || card.organizationName != null))
              PositionedDirectional(
                start: AppSpacing.md,
                end: AppSpacing.md,
                top: topInset + AppSpacing.xs,
                child: _OrgBadge(logo: logo, name: card.organizationName),
              ),
            PositionedDirectional(
              start: corporate ? AppSpacing.md : null,
              bottom: -avatarSize / 2,
              child: PersonAvatar(
                name: card.displayName,
                url: card.profilePhoto,
                size: avatarSize,
                ringColor: scheme.surface,
              ),
            ),
          ],
        ),
        SizedBox(height: avatarSize / 2 + AppSpacing.md),
        Padding(
          padding: AppSpacing.pageH,
          child: CardIdentity(card: card, center: !corporate),
        ),
        if (t == CardTemplate.reviewCard &&
            avg != null &&
            avg > 0 &&
            (card.reviewCount ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: RatingSummary(average: avg, count: card.reviewCount!),
          ),
      ],
    );
  }
}

class _OrgBadge extends StatelessWidget {
  const _OrgBadge({required this.logo, required this.name});

  final String? logo;
  final String? name;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logo != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: SafeNetworkImage(
                    url: logo,
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                    fallback: const SizedBox.shrink(),
                  ),
                ),
              ),
            if (name != null)
              Flexible(
                child: Text(
                  name!,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: const Color(0xFF111827)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CardIdentity extends StatelessWidget {
  const CardIdentity({super.key, required this.card, required this.center});

  final PublicCard card;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final muted = theme.colorScheme.onSurfaceVariant;
    final align = center ? TextAlign.center : TextAlign.start;
    final orgLine = [
      card.company,
      if (card.organizationName != null &&
          card.organizationName != card.company)
        card.organizationName,
    ].whereType<String>().join(' · ');
    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            card.displayName,
            textAlign: align,
            style: t.headlineMedium,
          ),
        ),
        if (card.pronouns != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              card.pronouns!,
              textAlign: align,
              style: t.bodySmall?.copyWith(color: muted),
            ),
          ),
        if (card.designation != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              card.designation!,
              textAlign: align,
              style: t.titleMedium?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
        if (orgLine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              orgLine,
              textAlign: align,
              style: t.bodyMedium?.copyWith(color: muted),
            ),
          ),
      ],
    );
  }
}

/// One prominent quick action (Call, WhatsApp, Email, Save contact).
class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = primary
        ? scheme.primary
        : scheme.primaryContainer.withValues(alpha: 0.7);
    final fg = primary ? scheme.onPrimary : scheme.onPrimaryContainer;
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: busy ? '$label, in progress' : label,
      excludeSemantics: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: busy ? null : onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 72,
              minWidth: AppSpacing.minTap,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.sm + 4,
                horizontal: AppSpacing.xs,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  busy
                      ? SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: fg,
                          ),
                        )
                      : Icon(icon, color: fg, size: 24),
                  const SizedBox(height: AppSpacing.xs + 2),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: fg, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Row of equal-width quick actions; wraps into two rows on narrow screens
/// or large text.
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final perRow = (scale > 1.5 || c.maxWidth < 300)
            ? 2
            : children.length.clamp(1, 4);
        const gap = AppSpacing.sm;
        final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          alignment: WrapAlignment.center,
          children: [
            for (final child in children) SizedBox(width: w, child: child),
          ],
        );
      },
    );
  }
}
