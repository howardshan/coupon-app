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
  // 当前选中的星级筛选（null 表示 All）
  int? _selectedStar;

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

        // 星级筛选 chips 行
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _StarFilterChip(
                    label: 'All',
                    isSelected: _selectedStar == null,
                    onTap: () => setState(() => _selectedStar = null),
                  ),
                  const SizedBox(width: 8),
                  ...List.generate(5, (i) {
                    final star = 5 - i; // 5, 4, 3, 2, 1
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _StarFilterChip(
                        label: '★' * star,
                        isSelected: _selectedStar == star,
                        onTap: () => setState(() => _selectedStar = star),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),

        // 评价列表
        reviewsAsync.when(
          data: (reviews) {
            // 客户端筛选：按 ratingOverall 过滤
            final filteredReviews = _selectedStar == null
                ? reviews
                : reviews
                    .where((r) => r.ratingOverall == _selectedStar)
                    .toList();

            if (filteredReviews.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      _selectedStar == null
                          ? 'No reviews yet'
                          : 'No $_selectedStar-star reviews',
                      style:
                          const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              );
            }

            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  // 未筛选时，最后一项触发加载更多
                  if (_selectedStar == null &&
                      index == filteredReviews.length - 1) {
                    final notifier = ref.read(
                        merchantReviewsProvider(widget.merchantId)
                            .notifier);
                    if (notifier.hasMore) {
                      notifier.loadMore();
                    }
                  }
                  return ReviewCard(review: filteredReviews[index]);
                },
                childCount: filteredReviews.length,
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

/// 星级筛选 chip 组件
class _StarFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _StarFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
