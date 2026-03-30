// 「我的评价」聚合列表页

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/my_reviews_provider.dart';

class MyReviewsScreen extends ConsumerWidget {
  const MyReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myWrittenReviewsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Reviews')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.textHint),
                const SizedBox(height: 12),
                Text(
                  'Failed to load reviews',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => ref.invalidate(myWrittenReviewsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (reviews) {
          if (reviews.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.rate_review_outlined, size: 72, color: AppColors.textHint),
                    const SizedBox(height: 16),
                    Text(
                      'No reviews yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'After you redeem a voucher, you can share your experience here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myWrittenReviewsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: reviews.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final r = reviews[i];
                final title = r.dealTitle?.isNotEmpty == true ? r.dealTitle! : 'Deal';
                final date = r.updatedAt ?? r.createdAt;
                final dateStr = DateFormat('MMM d, yyyy').format(date.toLocal());
                final stars = r.ratingOverall > 0 ? r.ratingOverall : r.rating;
                final merchantId = r.merchantId ?? '';
                final dealId = r.dealId ?? '';
                final orderItemId = r.orderItemId ?? '';

                return Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: dealId.isEmpty
                        ? null
                        : () {
                            final q = Uri(
                              path: '/review/$dealId',
                              queryParameters: {
                                if (merchantId.isNotEmpty) 'merchantId': merchantId,
                                if (orderItemId.isNotEmpty) 'orderItemId': orderItemId,
                                'reviewId': r.id,
                              },
                            );
                            context.push(q.toString());
                          },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ...List.generate(
                                5,
                                (idx) => Icon(
                                  idx < stars ? Icons.star : Icons.star_border,
                                  size: 18,
                                  color: AppColors.warning,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                dateStr,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          if (r.comment != null && r.comment!.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              r.comment!.trim(),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Tap to edit',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
