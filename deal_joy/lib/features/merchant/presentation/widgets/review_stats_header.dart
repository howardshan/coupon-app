import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/review_stats_model.dart';

/// 评价统计区头部组件
/// 左侧：大字评分 + 星星 + 总数；右侧：五星分布进度条；底部：标签云
class ReviewStatsHeader extends StatelessWidget {
  final ReviewStatsModel stats;

  const ReviewStatsHeader({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    // 无评价时显示空状态
    if (stats.totalCount == 0) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'No reviews yet',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 评分 + 分布条 横排
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 左侧：大字评分、星星行、评价总数
              _buildLeftRating(),
              const SizedBox(width: 20),
              // 右侧：5→1 星分布进度条
              Expanded(child: _buildRatingBars()),
            ],
          ),
          const SizedBox(height: 16),
          // 底部标签云
          if (stats.topTags.isNotEmpty) _buildTagCloud(),
        ],
      ),
    );
  }

  /// 左侧评分区域
  Widget _buildLeftRating() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 大字评分
        Text(
          stats.avgRating.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        // 五颗星
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) {
            final filled = i < stats.avgRating.round();
            return Icon(
              Icons.star,
              size: 16,
              color: filled ? AppColors.featuredBadge : AppColors.surfaceVariant,
            );
          }),
        ),
        const SizedBox(height: 4),
        // 评价总数
        Text(
          '${stats.totalCount} reviews',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  /// 右侧维度评分进度条（Overall / Environment / Product / Service）
  Widget _buildRatingBars() {
    final dimensions = <(String, double)>[
      ('Overall', stats.avgOverall),
      ('Environment', stats.avgEnvironment),
      ('Product', stats.avgProduct),
      ('Service', stats.avgService),
    ];

    return Column(
      children: dimensions.map((d) {
        final (label, score) = d;
        final ratio = score / 5.0; // 满分 5 分
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 28,
                child: Text(
                  score > 0 ? score.toStringAsFixed(1) : '-',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 底部热门标签云（Wrap + Chip）
  Widget _buildTagCloud() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: stats.topTags.map((tag) {
        return Chip(
          label: Text(
            '${tag.tag} ${tag.count}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
            ),
          ),
          backgroundColor: AppColors.surfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide.none,
          ),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        );
      }).toList(),
    );
  }
}
