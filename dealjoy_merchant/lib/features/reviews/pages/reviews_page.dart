// 评价管理主页面
// 结构:
//   顶部 SliverAppBar — 页面标题
//   SliverToBoxAdapter — 评分统计卡片（平均分 + 星分布 + 关键词）
//   SliverToBoxAdapter — 筛选行（All / 5★ / 4★ / 3★ / 2★ / 1★）
//   SliverList         — 评价列表（ReviewCard）
//   加载更多 / 空状态 / 错误状态

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/merchant_review.dart';
import '../providers/reviews_provider.dart';
import '../widgets/rating_distribution_bar.dart';
import '../widgets/review_card.dart';

class ReviewsPage extends ConsumerWidget {
  const ReviewsPage({super.key});

  static const Color _primaryColor = Color(0xFFFF6B35);
  static const Color _bgColor      = Color(0xFFF8F9FA);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(reviewsProvider);
    final statsAsync   = ref.watch(reviewStatsProvider);
    final filter       = ref.watch(reviewsFilterProvider);

    return Scaffold(
      backgroundColor: _bgColor,
      body: RefreshIndicator(
        color:        _primaryColor,
        onRefresh: () async {
          // 同时刷新列表和统计
          await ref.read(reviewsProvider.notifier).refresh();
          ref.invalidate(reviewStatsProvider);
        },
        child: CustomScrollView(
          slivers: [
            // -------------------------------------------------------
            // AppBar
            // -------------------------------------------------------
            SliverAppBar(
              title: const Text(
                'Reviews',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize:   20,
                  color:      Color(0xFF1A1A1A),
                ),
              ),
              backgroundColor:    Colors.white,
              surfaceTintColor:   Colors.white,
              elevation:          0,
              pinned:             true,
              forceElevated:      true,
              shadowColor: Colors.black.withValues(alpha: 0.08),
            ),

            // -------------------------------------------------------
            // 评分统计卡片
            // -------------------------------------------------------
            SliverToBoxAdapter(
              child: statsAsync.when(
                loading: () => _buildStatsShimmer(),
                error:   (e, _) => const SizedBox.shrink(),
                data:    (stats) => _StatsCard(stats: stats),
              ),
            ),

            // -------------------------------------------------------
            // 星级筛选行
            // -------------------------------------------------------
            SliverToBoxAdapter(
              child: _FilterRow(
                currentFilter: filter.ratingFilter,
                onFilterChanged: (rating) =>
                    ref.read(reviewsProvider.notifier).applyRatingFilter(rating),
              ),
            ),

            // -------------------------------------------------------
            // 评价列表
            // -------------------------------------------------------
            reviewsAsync.when(
              loading: () => _buildListShimmer(),
              error: (e, _) => SliverFillRemaining(
                child: _ErrorState(
                  message: e.toString().replaceFirst(RegExp(r'^.*?: '), ''),
                  onRetry: () => ref.read(reviewsProvider.notifier).refresh(),
                ),
              ),
              data: (paged) {
                if (paged.data.isEmpty) {
                  return SliverFillRemaining(
                    child: _EmptyState(
                      hasFilter: filter.hasFilter,
                      onClearFilter: () =>
                          ref.read(reviewsProvider.notifier).applyRatingFilter(null),
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      // 最后一项：加载更多提示
                      if (index == paged.data.length) {
                        return _buildLoadMore(paged, ref);
                      }
                      return ReviewCard(review: paged.data[index]);
                    },
                    childCount: paged.data.length + 1,
                  ),
                );
              },
            ),

            // 底部安全区留白
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  // =============================================================
  // 统计卡片骨架屏
  // =============================================================
  Widget _buildStatsShimmer() {
    return Container(
      margin:  const EdgeInsets.fromLTRB(16, 12, 16, 0),
      height:  160,
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const _ShimmerBox(),
    );
  }

  // =============================================================
  // 列表骨架屏
  // =============================================================
  Widget _buildListShimmer() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, idx) => Container(
          margin:  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          height:  120,
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const _ShimmerBox(),
        ),
        childCount: 4,
      ),
    );
  }

  // =============================================================
  // 加载更多 / 已全部加载
  // =============================================================
  Widget _buildLoadMore(PagedReviews paged, WidgetRef ref) {
    if (!paged.hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'All reviews loaded',
            style: TextStyle(fontSize: 13, color: Color(0xFFAAAAAA)),
          ),
        ),
      );
    }
    // 触底自动加载下一页
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(reviewsProvider.notifier).loadNextPage();
    });
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Color(0xFFFF6B35),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// _StatsCard — 评分统计卡片（平均分 + 进度条 + 关键词）
// =============================================================
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final ReviewStats stats;

  static const Color _primaryColor = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          const Text(
            'Rating Overview',
            style: TextStyle(
              fontSize:   15,
              fontWeight: FontWeight.w700,
              color:      Color(0xFF1A1A1A),
            ),
          ),

          const SizedBox(height: 14),

          // 平均分 + 分布条并排
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 左侧: 大字平均分
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    stats.totalCount == 0
                        ? '—'
                        : stats.avgRating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize:   48,
                      fontWeight: FontWeight.w800,
                      color:      _primaryColor,
                      height:     1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (i) {
                      final filled = i < stats.avgRating.round();
                      return Icon(
                        filled ? Icons.star_rounded : Icons.star_outline_rounded,
                        size:  16,
                        color: filled ? _primaryColor : const Color(0xFFE0E0E0),
                      );
                    }),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${stats.totalCount} reviews',
                    style: const TextStyle(
                      fontSize: 12,
                      color:    Color(0xFF888888),
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 20),

              // 右侧: 分布进度条
              Expanded(
                child: RatingDistributionBar(
                  ratingDistribution: stats.ratingDistribution,
                  totalCount:         stats.totalCount,
                ),
              ),
            ],
          ),

          // 关键词标签（若有）
          if (stats.topKeywords.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Keywords',
              style: TextStyle(
                fontSize:   13,
                fontWeight: FontWeight.w600,
                color:      Color(0xFF555555),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing:   6,
              runSpacing: 6,
              children: stats.topKeywords.map((kw) => _KeywordChip(kw)).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================
// _KeywordChip — 关键词标签（内部组件）
// =============================================================
class _KeywordChip extends StatelessWidget {
  const _KeywordChip(this.keyword);

  final String keyword;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        const Color(0xFFFFF3EE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFF6B35).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        keyword,
        style: const TextStyle(
          fontSize: 12,
          color:    Color(0xFFFF6B35),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// =============================================================
// _FilterRow — 星级筛选按钮行
// =============================================================
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.currentFilter,
    required this.onFilterChanged,
  });

  final int? currentFilter;
  final void Function(int? rating) onFilterChanged;

  static const Color _primaryColor = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context) {
    final filters = <int?>[null, 5, 4, 3, 2, 1];
    final labels  = <String>['All', '5★', '4★', '3★', '2★', '1★'];

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding:         const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount:       filters.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isSelected = currentFilter == filters[index];
          return GestureDetector(
            onTap: () => onFilterChanged(filters[index]),
            child: AnimatedContainer(
              duration:    const Duration(milliseconds: 180),
              padding:     const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? _primaryColor : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? _primaryColor : const Color(0xFFE0E0E0),
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color:      _primaryColor.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset:     const Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: Text(
                labels[index],
                style: TextStyle(
                  fontSize:   13,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF555555),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================
// _EmptyState — 无评价时的空状态
// =============================================================
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.hasFilter,
    required this.onClearFilter,
  });

  final bool hasFilter;
  final VoidCallback onClearFilter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.rate_review_outlined,
              size:  72,
              color: Color(0xFFCCCCCC),
            ),
            const SizedBox(height: 16),
            Text(
              hasFilter ? 'No reviews with this rating' : 'No reviews yet',
              style: const TextStyle(
                fontSize:   18,
                fontWeight: FontWeight.w600,
                color:      Color(0xFF555555),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? 'Try selecting a different rating filter.'
                  : 'Your reviews will appear here once customers start reviewing.',
              style: const TextStyle(fontSize: 14, color: Color(0xFF888888)),
              textAlign: TextAlign.center,
            ),
            if (hasFilter) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: onClearFilter,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6B35),
                  side: const BorderSide(color: Color(0xFFFF6B35)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Show All Reviews'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================
// _ErrorState — 加载失败错误状态
// =============================================================
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size:  64,
              color: Color(0xFFCCCCCC),
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to load reviews',
              style: TextStyle(
                fontSize:   18,
                fontWeight: FontWeight.w600,
                color:      Color(0xFF555555),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(fontSize: 13, color: Color(0xFF888888)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed:  onRetry,
              icon:       const Icon(Icons.refresh_rounded),
              label:      const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// _ShimmerBox — 骨架屏占位组件（简单灰色动画）
// =============================================================
class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox();

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: Color.fromRGBO(
              224, 224, 224,
              _animation.value,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
        );
      },
    );
  }
}
