import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/providers.dart';
import '../../../shared/models/card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/external_actions.dart';
import '../data/public_card_repository.dart';
import '../domain/contact_links.dart';
import '../domain/public_card.dart';
import 'public_card_providers.dart';
import 'widgets/card_hero.dart';
import 'widgets/card_sections.dart';
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
      loading: () => Scaffold(appBar: AppBar(), body: const _CardSkeleton()),
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
      ref
          .read(publicCardRepositoryProvider)
          .trackClick(slug: slug, type: type, target: target),
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
      await ref
          .read(externalActionsProvider)
          .shareText(
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
      await ref
          .read(externalActionsProvider)
          .shareFile(
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
    ref.invalidate(publicCardProvider(widget.slug));
    try {
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
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final onHero = card.template != CardTemplate.minimal;

    // Floating app-bar buttons sit on a translucent disc so they stay
    // legible over any cover photo or gradient.
    final barButtonStyle = IconButton.styleFrom(
      backgroundColor: Colors.black.withValues(alpha: 0.28),
      foregroundColor: Colors.white,
    );

    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            systemOverlayStyle: onHero ? SystemUiOverlayStyle.light : null,
            automaticallyImplyLeading: false,
            leading: Navigator.of(context).canPop()
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .backButtonTooltip,
                      style: onHero ? barButtonStyle : null,
                      icon: const BackButtonIcon(),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  )
                : null,
            actions: [
              Builder(
                builder: (btn) => Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: IconButton(
                    tooltip: 'Share card',
                    style: onHero ? barButtonStyle : null,
                    icon: const Icon(Icons.ios_share),
                    onPressed: () => _share(btn),
                  ),
                ),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            edgeOffset: topInset,
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              children: [
                CardHero(card: card, topInset: topInset),
                ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _quickActions(),
                        if (googleReview != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          FilledButton.icon(
                            key: const ValueKey('google-review'),
                            onPressed: () =>
                                _open(googleReview, TrackType.googleReview),
                            icon: const Icon(
                              Icons.star_rounded,
                              color: AppColors.star,
                            ),
                            label: const Text('Review us on Google'),
                          ),
                        ],
                        for (final section in card.sectionOrder)
                          if (card.showsSection(section)) ..._section(section),
                        const SizedBox(height: AppSpacing.xl),
                        ExcludeSemantics(
                          child: Text(
                            'Digital card by Bizzvot',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickActions() {
    final call = card.shows(const ['phone'])
        ? ContactLinks.tel(card.phone)
        : null;
    final wa = card.shows(const ['whatsapp'])
        ? ContactLinks.whatsapp(card.whatsapp)
        : null;
    final mail = card.shows(const ['email'])
        ? ContactLinks.mailto(card.email)
        : null;
    return QuickActionsRow(
      children: [
        if (call != null)
          QuickActionButton(
            icon: Icons.call_rounded,
            label: 'Call',
            onPressed: () => _open(call, TrackType.phone),
          ),
        if (wa != null)
          QuickActionButton(
            icon: Icons.chat_rounded,
            label: 'WhatsApp',
            onPressed: () => _open(wa, TrackType.whatsapp),
          ),
        if (mail != null)
          QuickActionButton(
            icon: Icons.mail_rounded,
            label: 'Email',
            onPressed: () => _open(mail, TrackType.email),
          ),
        if (card.canSaveContact)
          Builder(
            builder: (btn) => QuickActionButton(
              key: const ValueKey('save-contact'),
              icon: Icons.person_add_alt_1_rounded,
              label: 'Save contact',
              primary: true,
              busy: _savingContact,
              onPressed: () => _saveContact(btn),
            ),
          ),
      ],
    );
  }

  List<Widget> _section(PublicSection section) {
    final hub = card.template == CardTemplate.profileHub;
    bool anySafe(List<MediaItem> items) =>
        items.any((m) => ContactLinks.web(m.url) != null);
    final Widget? child = switch (section) {
      PublicSection.contact =>
        hasContactDetails(card)
            ? ContactSection(card: card, onOpen: _open)
            : null,
      PublicSection.about =>
        card.bio == null
            ? null
            : CardSection(
                title: 'About',
                children: [
                  Text(card.bio!, style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
      PublicSection.social =>
        !hasSafeLinks(card.socialLinks)
            ? null
            : LinksSection(
                title: 'Social',
                links: card.socialLinks,
                hub: hub,
                social: true,
                onOpen: _open,
              ),
      PublicSection.links =>
        !hasSafeLinks(card.customLinks)
            ? null
            : LinksSection(
                title: 'Links',
                links: card.customLinks,
                hub: hub,
                social: false,
                onOpen: _open,
              ),
      PublicSection.gallery =>
        anySafe(card.gallery) ? GallerySection(images: card.gallery) : null,
      PublicSection.videos =>
        anySafe(card.videos)
            ? MediaListSection(
                title: 'Videos',
                items: card.videos,
                icon: Icons.play_circle_outline,
                fallbackName: 'Video',
                onTap: (m) =>
                    _open(ContactLinks.web(m.url), TrackType.video, m.name),
              )
            : null,
      PublicSection.pdfs =>
        anySafe(card.pdfs)
            ? MediaListSection(
                title: 'Documents',
                items: card.pdfs,
                icon: Icons.picture_as_pdf_outlined,
                fallbackName: 'Document',
                onTap: (m) =>
                    _open(ContactLinks.web(m.url), TrackType.pdf, m.name),
              )
            : null,
      PublicSection.reviews => PublicReviewsSection(slug: slug, card: card),
    };
    if (child == null) return const [];
    return [const SizedBox(height: AppSpacing.lg), child];
  }
}

/// First-load placeholder shaped like the card.
class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading card',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: AppSpacing.page,
        children: const [
          SizedBox(height: AppSpacing.lg),
          Center(child: SkeletonBox(height: 112, width: 112, radius: 56)),
          SizedBox(height: AppSpacing.lg),
          Center(child: SkeletonBox(height: 24, width: 200)),
          SizedBox(height: AppSpacing.sm),
          Center(child: SkeletonBox(height: 16, width: 140)),
          SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 72, radius: AppRadius.lg)),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: SkeletonBox(height: 72, radius: AppRadius.lg)),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: SkeletonBox(height: 72, radius: AppRadius.lg)),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(height: 160, radius: AppRadius.lg),
        ],
      ),
    );
  }
}
