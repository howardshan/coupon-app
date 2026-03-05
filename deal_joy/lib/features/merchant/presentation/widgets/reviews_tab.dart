import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/store_detail_provider.dart';
import 'review_card.dart';
import 'review_stats_header.dart';

/// Reviews Tab 组件
/// 复用 ReviewStatsHeader + ReviewCard
class ReviewsTab extends ConsumerStatefulWidget {
  final String merchantId;

  const ReviewsTab({super.key, required this.merchantId});

  @override
  ConsumerState<ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends ConsumerState<ReviewsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final statsAsync = ref.watch(reviewStatsProvider(widget.merchantId));
    final reviewsAsync =
        ref.watch(merchantReviewsProvider(widget.merchantId));

    return CustomScrollView(
      slivers: [
        // 评价统计头部
        SliverToBoxAdapter(
          child: statsAsync.when(
            data: (stats) => ReviewStatsHeader(stats: stats),
            loading: () => const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ),

        const SliverToBoxAdapter(
          child: Divider(height: 1, indent: 16, endIndent: 16),
        ),

        // 评价列表
        reviewsAsync.when(
          data: (reviews) {
            if (reviews.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'No reviews yet',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              );
            }

            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  // 最后一项触发加载更多
                  if (index == reviews.length - 1) {
                    final notifier = ref.read(
                        merchantReviewsProvider(widget.merchantId)
                            .notifier);
                    if (notifier.hasMore) {
                      notifier.loadMore();
                    }
                  }
                  return ReviewCard(review: reviews[index]);
                },
                childCount: reviews.length,
              ),
            );
          },
          loading: () => const SliverToBoxAdapter(
            child: SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (_, _) => SliverToBoxAdapter(
            child: Center(
              child: Text('Failed to load reviews',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}
