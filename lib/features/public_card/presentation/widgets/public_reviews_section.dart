import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../shared/widgets/feedback.dart';
import '../../domain/public_card.dart';
import '../../domain/public_review.dart';
import '../public_card_providers.dart';
import 'star_rating.dart';

/// Approved reviews with business replies + "Write a review".
class PublicReviewsSection extends ConsumerWidget {
  const PublicReviewsSection({
    super.key,
    required this.slug,
    required this.card,
  });

  final String slug;
  final PublicCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reviews = ref.watch(publicReviewsProvider(slug));
    final avg = card.averageRating;
    final count = card.reviewCount ?? reviews.value?.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Reviews', style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (avg != null && avg > 0 && (count ?? 0) > 0) ...[
          RatingSummary(average: avg, count: count ?? 0),
          const SizedBox(height: AppSpacing.sm),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => context.push(Routes.publicReview(slug)),
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('Write a review'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        reviews.when(
          skipLoadingOnRefresh: true,
          loading: () => Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Center(
              child: Semantics(
                label: 'Loading reviews',
                child: const CircularProgressIndicator(),
              ),
            ),
          ),
          error: (e, _) => _InlineError(
            message: AppException.from(e).message,
            onRetry: () => ref.invalidate(publicReviewsProvider(slug)),
          ),
          data: (list) {
            if (list.items.isEmpty) {
              return Text(
                'No reviews yet. Be the first to share your experience.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in list.items) ...[
                  PublicReviewTile(review: r),
                  const Divider(height: AppSpacing.lg),
                ],
                if (list.hasMore)
                  Center(
                    child: list.loadingMore
                        ? const Padding(
                            padding: EdgeInsets.all(AppSpacing.sm),
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : TextButton(
                            onPressed: () async {
                              try {
                                await ref
                                    .read(publicReviewsProvider(slug).notifier)
                                    .loadMore();
                              } catch (e) {
                                if (context.mounted) showError(context, e);
                              }
                            },
                            child: const Text('Show more reviews'),
                          ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class RatingSummary extends StatelessWidget {
  const RatingSummary({super.key, required this.average, required this.count});

  final double average;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avg = average.clamp(0, 5).toStringAsFixed(1);
    final reviews = count == 1 ? '1 review' : '$count reviews';
    return Semantics(
      label: 'Average rating $avg out of 5 from $reviews',
      excludeSemantics: true,
      child: Wrap(
        spacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(avg, style: theme.textTheme.headlineSmall),
          StarRating(rating: average),
          Text(
            reviews,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class PublicReviewTile extends StatelessWidget {
  const PublicReviewTile({super.key, required this.review});

  final PublicReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = review.createdAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(review.reviewerName, style: theme.textTheme.titleSmall),
            if (date != null)
              Text(
                DateFormat.yMMMd().format(date),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        StarRating(rating: review.rating.toDouble()),
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
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Response from the business',
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
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.error_outline, color: theme.colorScheme.error),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
