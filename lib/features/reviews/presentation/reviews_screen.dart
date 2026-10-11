import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/auth/session_controller.dart';
import '../../../shared/models/review.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../public_card/presentation/widgets/star_rating.dart';
import '../data/reviews_repository.dart';
import 'reviews_providers.dart';

/// Review moderation. Owners see every review in their organization; staff
/// (with `viewReviews`) see their own card's reviews and may reply/moderate
/// only with `replyReviews`.
class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key, this.staffMode = false});

  final bool staffMode;

  static const replyMaxLength = 1000;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (staffMode && !(user?.permissions.viewReviews ?? false)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reviews')),
        body: const EmptyView(
          icon: Icons.lock_outline,
          title: "You don't have access to reviews",
          message: 'Ask your organization owner to turn on review access for your account.',
        ),
      );
    }
    final canModerate = !staffMode || (user?.permissions.replyReviews ?? false);
    final scope = staffMode ? ReviewScope.staff : ReviewScope.owner;
    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: _ReviewsBody(scope: scope, canModerate: canModerate),
    );
  }
}

class _ReviewsBody extends ConsumerWidget {
  const _ReviewsBody({required this.scope, required this.canModerate});

  final ReviewScope scope;
  final bool canModerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reviewFilterProvider(scope));
    final provider = reviewsControllerProvider(scope);
    final async = ref.watch(provider);

    Future<void> refresh() async {
      ref.invalidate(provider);
      try {
        await ref.read(provider.future);
      } catch (_) {}
    }

    return Column(
      children: [
        ContentWidth(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                for (final f in ReviewFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: f == filter,
                      onSelected: (_) => ref
                          .read(reviewFilterProvider(scope).notifier)
                          .select(f),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (async.isLoading && async.hasValue) const LinearProgressIndicator(),
        Expanded(
          child: !async.hasValue && !async.hasError
              ? const SkeletonList(count: 4)
              : AsyncValueView(
                  value: async,
                  loadingLabel: 'Loading reviews',
                  onRetry: () => ref.invalidate(provider),
                  data: (state) {
                    final items = state.visible(filter);
                    if (items.isEmpty) {
                      return RefreshIndicator(
                        onRefresh: refresh,
                        child: ListView(
                          children: [
                            const SizedBox(height: AppSpacing.xl),
                            _emptyFor(filter),
                          ],
                        ),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: refresh,
                      child: ListView.separated(
                        padding: AppSpacing.page,
                        itemCount: items.length + (state.hasMore ? 1 : 0),
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.md),
                        itemBuilder: (context, i) {
                          if (i >= items.length) {
                            return Center(
                              child: state.loadingMore
                                  ? const CircularProgressIndicator()
                                  : OutlinedButton(
                                      onPressed: () async {
                                        try {
                                          await ref
                                              .read(provider.notifier)
                                              .loadMore();
                                        } catch (e) {
                                          if (context.mounted)
                                            showError(context, e);
                                        }
                                      },
                                      child: const Text('Load more'),
                                    ),
                            );
                          }
                          final review = items[i];
                          return ContentWidth(
                            child: ReviewCard(
                              review: review,
                              canModerate: canModerate,
                              busy: state.busyIds.contains(review.id),
                              onStatus: (s) =>
                                  _setStatus(context, ref, review, s),
                              onReply: () => _reply(context, ref, review),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _emptyFor(ReviewFilter f) => switch (f) {
    ReviewFilter.all => const EmptyView(
      icon: Icons.reviews_outlined,
      title: 'No reviews yet',
      message: 'Reviews left on your cards will appear here.',
    ),
    ReviewFilter.pending => const EmptyView(
      icon: Icons.task_alt,
      title: 'Nothing waiting for approval',
      message: 'New reviews that need moderation will appear here.',
    ),
    ReviewFilter.approved => const EmptyView(
      icon: Icons.visibility_outlined,
      title: 'No approved reviews',
      message: 'Approved reviews are shown publicly on cards.',
    ),
    ReviewFilter.hidden => const EmptyView(
      icon: Icons.visibility_off_outlined,
      title: 'No hidden reviews',
      message: 'Reviews you hide will appear here.',
    ),
  };

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    Review review,
    ReviewStatus status,
  ) async {
    try {
      await ref
          .read(reviewsControllerProvider(scope).notifier)
          .setStatus(review.id, status);
      if (context.mounted) {
        showMessage(context, switch (status) {
          ReviewStatus.approved => 'Review approved',
          ReviewStatus.hidden => 'Review hidden',
          ReviewStatus.pending => 'Review moved to pending',
        });
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _reply(
    BuildContext context,
    WidgetRef ref,
    Review review,
  ) async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReplyComposer(initial: review.reply?.text),
    );
    if (text == null || !context.mounted) return;
    try {
      await ref
          .read(reviewsControllerProvider(scope).notifier)
          .reply(review.id, text);
      if (context.mounted) showMessage(context, 'Reply posted');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

class ReviewCard extends StatelessWidget {
  const ReviewCard({
    super.key,
    required this.review,
    required this.canModerate,
    required this.busy,
    required this.onStatus,
    required this.onReply,
  });

  final Review review;
  final bool canModerate;
  final bool busy;
  final void Function(ReviewStatus) onStatus;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final date = review.createdAt;
    final s = review.status;

    final actions = <Widget>[
      if (s == ReviewStatus.pending)
        _action('Approve', Icons.check, () => onStatus(ReviewStatus.approved)),
      if (s == ReviewStatus.hidden)
        _action(
          'Unhide',
          Icons.visibility_outlined,
          () => onStatus(ReviewStatus.approved),
        ),
      if (s != ReviewStatus.hidden)
        _action(
          'Hide',
          Icons.visibility_off_outlined,
          () => onStatus(ReviewStatus.hidden),
        ),
      if (s != ReviewStatus.pending)
        _action(
          'Move to pending',
          Icons.schedule,
          () => onStatus(ReviewStatus.pending),
        ),
      _action(
        review.reply == null ? 'Reply' : 'Edit reply',
        Icons.reply_outlined,
        onReply,
      ),
    ];

    return Card(
      child: Padding(
        padding: AppSpacing.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    review.cardTitle ?? 'Card',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ReviewStatusChip(status: s),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                ExcludeSemantics(
                  child: InitialsAvatar(
                    name: review.reviewerName ?? 'Anonymous',
                    radius: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.reviewerName ?? 'Anonymous',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StarRating(
                            rating: review.rating.toDouble(),
                            size: 16,
                          ),
                          if (date != null)
                            Text(DateFormat.yMMMd().format(date), style: muted),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (review.comment != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(review.comment!, style: theme.textTheme.bodyMedium),
            ],
            if (review.reply != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md - 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your reply',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(review.reply!.text, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
            if (canModerate) ...[
              const SizedBox(height: AppSpacing.sm),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: LinearProgressIndicator(),
                )
              else
                Wrap(spacing: AppSpacing.xs, children: actions),
            ],
          ],
        ),
      ),
    );
  }

  Widget _action(String label, IconData icon, VoidCallback onPressed) =>
      TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}

/// Review status pill built on the shared [StatusChip].
class ReviewStatusChip extends StatelessWidget {
  const ReviewStatusChip({super.key, required this.status});

  final ReviewStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, tone, icon) = switch (status) {
      ReviewStatus.pending => ('Pending', StatusTone.warning, Icons.schedule),
      ReviewStatus.approved => ('Approved', StatusTone.success, Icons.check),
      ReviewStatus.hidden => (
        'Hidden',
        StatusTone.neutral,
        Icons.visibility_off_outlined,
      ),
    };
    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: StatusChip(label, tone: tone, icon: icon),
    );
  }
}

/// Bottom-sheet reply composer. Pops with the trimmed text.
class ReplyComposer extends StatefulWidget {
  const ReplyComposer({super.key, this.initial});

  final String? initial;

  @override
  State<ReplyComposer> createState() => _ReplyComposerState();
}

class _ReplyComposerState extends State<ReplyComposer> {
  final _formKey = GlobalKey<FormState>();
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_text.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.initial == null ? 'Reply to review' : 'Edit reply',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Your reply is shown publicly under the review once it is approved.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const ValueKey('reply-text'),
                controller: _text,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                maxLength: ReviewsScreen.replyMaxLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reply',
                  alignLabelWithHint: true,
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Write a reply first';
                  if (t.length > ReviewsScreen.replyMaxLength) {
                    return 'Keep it under ${ReviewsScreen.replyMaxLength} characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                key: const ValueKey('reply-submit'),
                onPressed: _submit,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Post reply'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
