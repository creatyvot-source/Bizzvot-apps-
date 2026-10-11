import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/public_card_repository.dart';
import '../domain/public_review.dart';
import 'public_card_providers.dart';
import 'widgets/star_rating.dart';

/// Public review form at `/card/:slug/review`. No sign-in required.
class WriteReviewScreen extends ConsumerStatefulWidget {
  const WriteReviewScreen({super.key, required this.slug});

  final String slug;

  static const nameMaxLength = 60;
  static const commentMaxLength = 1000;
  static const defaultCooldown = Duration(seconds: 60);

  @override
  ConsumerState<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends ConsumerState<WriteReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _comment = TextEditingController();

  int _rating = 0;
  bool _ratingTouched = false;
  bool _submitting = false;
  bool _alreadyReviewed = false;
  DateTime? _cooldownUntil;
  Timer? _ticker;
  ReviewSubmissionResult? _result;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _ticker?.cancel();
    _name.dispose();
    _comment.dispose();
    super.dispose();
  }

  Duration get _cooldownLeft {
    final until = _cooldownUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get _blocked => _alreadyReviewed || _cooldownLeft > Duration.zero;

  void _startCooldown(Duration d) {
    _ticker?.cancel();
    setState(() => _cooldownUntil = DateTime.now().add(d));
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_cooldownLeft == Duration.zero) {
        t.cancel();
        setState(() => _cooldownUntil = null);
      } else {
        setState(() {});
      }
    });
  }

  String? get _ratingError {
    if (_fieldErrors['rating'] case final e?) return e;
    if (_ratingTouched && (_rating < 1 || _rating > 5)) {
      return 'Choose a rating from 1 to 5 stars';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting || _blocked) return;
    setState(() {
      _ratingTouched = true;
      _fieldErrors = const {};
    });
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk || _rating < 1 || _rating > 5) return;

    setState(() => _submitting = true);
    try {
      final result = await ref
          .read(publicCardRepositoryProvider)
          .submitReview(
            widget.slug,
            ReviewSubmission(
              rating: _rating,
              name: _name.text,
              comment: _comment.text,
            ),
          );
      if (!mounted) return;
      if (result.isApproved) ref.invalidate(publicReviewsProvider(widget.slug));
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      final err = AppException.from(e);
      switch (err.kind) {
        case AppErrorKind.conflict:
          setState(() => _alreadyReviewed = true);
        case AppErrorKind.rateLimited:
          _startCooldown(
            (err.retryAfter == null || err.retryAfter == Duration.zero)
                ? WriteReviewScreen.defaultCooldown
                : err.retryAfter!,
          );
        case AppErrorKind.validation:
          setState(() => _fieldErrors = err.fieldErrors);
          _formKey.currentState?.validate();
          showError(context, err);
        default:
          showError(context, err);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _backToCard() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.publicCard(widget.slug));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardName = ref.watch(publicCardProvider(widget.slug)).value?.name;
    return Scaffold(
      appBar: AppBar(title: const Text('Write a review')),
      body: SafeArea(
        child: _result != null
            ? _SuccessView(result: _result!, onDone: _backToCard)
            : _form(context, cardName),
      ),
    );
  }

  Widget _form(BuildContext context, String? cardName) {
    final theme = Theme.of(context);
    final left = _cooldownLeft;
    final disabled = _submitting || _blocked;
    return ListView(
      padding: AppSpacing.page,
      children: [
        ContentWidth(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  cardName == null
                      ? 'How was your experience?'
                      : 'How was your experience with $cardName?',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your name, rating and comment may be shown publicly on this card.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_alreadyReviewed)
                  const _Banner(
                    key: ValueKey('already-reviewed'),
                    icon: Icons.info_outline,
                    text: 'You have already reviewed this person.',
                  ),
                if (left > Duration.zero)
                  _Banner(
                    key: const ValueKey('cooldown'),
                    icon: Icons.hourglass_empty,
                    text:
                        'Too many attempts. You can try again in ${_fmt(left)}.',
                    liveRegion: false,
                  ),
                StarRatingInput(
                  value: _rating,
                  enabled: !disabled,
                  errorText: _ratingError,
                  onChanged: (v) => setState(() {
                    _rating = v;
                    _ratingTouched = true;
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('review-name'),
                  controller: _name,
                  enabled: !disabled,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  maxLength: WriteReviewScreen.nameMaxLength,
                  decoration: const InputDecoration(labelText: 'Your name'),
                  validator: (v) {
                    if (_fieldErrors['name'] case final e?) return e;
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const ValueKey('review-comment'),
                  controller: _comment,
                  enabled: !disabled,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: WriteReviewScreen.commentMaxLength,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Comment (optional)',
                    alignLabelWithHint: true,
                  ),
                  validator: (_) => _fieldErrors['comment'],
                ),
                const SizedBox(height: AppSpacing.lg),
                BusyButton(
                  key: const ValueKey('submit-review'),
                  label: left > Duration.zero
                      ? 'Try again in ${_fmt(left)}'
                      : 'Submit review',
                  icon: Icons.send_outlined,
                  onPressed: disabled ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _fmt(Duration d) {
    final s = d.inSeconds + (d.inMilliseconds % 1000 > 0 ? 1 : 0);
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.icon,
    required this.text,
    this.liveRegion = true,
  });

  final IconData icon;
  final String text;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Semantics(
        liveRegion: liveRegion,
        child: Container(
          padding: AppSpacing.page,
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: scheme.onSecondaryContainer),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.result, required this.onDone});

  final ReviewSubmissionResult result;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: EmptyView(
        icon: Icons.check_circle_outline,
        title: result.isApproved
            ? 'Thanks for your review'
            : 'Thanks! Your review will appear after approval',
        action: FilledButton(
          onPressed: onDone,
          child: const Text('Back to card'),
        ),
      ),
    );
  }
}
