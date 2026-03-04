// 评分分布进度条组件
// 显示 5 行（5星→1星），每行: 星数标签 + 进度条 + 评价数量
// 用于评价统计卡片内

import 'package:flutter/material.dart';

class RatingDistributionBar extends StatelessWidget {
  const RatingDistributionBar({
    super.key,
    required this.ratingDistribution,
    required this.totalCount,
  });

  /// 各星评价数量，key: 1-5
  final Map<int, int> ratingDistribution;

  /// 评价总数（用于计算百分比）
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      // 从5星到1星降序展示
      children: List.generate(5, (index) {
        final star  = 5 - index;
        final count = ratingDistribution[star] ?? 0;
        final ratio = totalCount > 0 ? count / totalCount : 0.0;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3.0),
          child: _RatingRow(
            star:  star,
            count: count,
            ratio: ratio,
          ),
        );
      }),
    );
  }
}

// =============================================================
// _RatingRow — 单行评分分布（内部组件）
// =============================================================
class _RatingRow extends StatelessWidget {
  const _RatingRow({
    required this.star,
    required this.count,
    required this.ratio,
  });

  final int star;     // 星级 (1-5)
  final int count;    // 该星级评价数
  final double ratio; // 百分比 (0.0-1.0)

  static const Color _primaryColor = Color(0xFFFF6B35);
  static const Color _emptyColor   = Color(0xFFE8E8E8);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 星级标签（固定宽度对齐）
        SizedBox(
          width: 24,
          child: Text(
            '$star',
            style: const TextStyle(
              fontSize:   13,
              fontWeight: FontWeight.w500,
              color:      Color(0xFF555555),
            ),
            textAlign: TextAlign.center,
          ),
        ),

        const SizedBox(width: 4),

        // 星星图标
        const Icon(
          Icons.star_rounded,
          size:  14,
          color: Color(0xFFFF6B35),
        ),

        const SizedBox(width: 8),

        // 进度条
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:            ratio,
              minHeight:        8,
              backgroundColor:  _emptyColor,
              valueColor:       const AlwaysStoppedAnimation<Color>(_primaryColor),
            ),
          ),
        ),

        const SizedBox(width: 8),

        // 数量标签（固定宽度对齐）
        SizedBox(
          width: 28,
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 12,
              color:    Color(0xFF888888),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
