/// 评价统计聚合模型（来自 get_merchant_review_summary RPC）
class ReviewStatsModel {
  final double avgRating;
  final int totalCount;
  final Map<int, int> ratingDistribution; // {5: 780, 4: 300, 3: 50, 2: 10, 1: 5}
  final List<ReviewTag> topTags;

  // 维度平均分（0 表示无数据）
  final double avgOverall;
  final double avgEnvironment;
  final double avgProduct;
  final double avgService;

  const ReviewStatsModel({
    required this.avgRating,
    required this.totalCount,
    required this.ratingDistribution,
    required this.topTags,
    this.avgOverall = 0,
    this.avgEnvironment = 0,
    this.avgProduct = 0,
    this.avgService = 0,
  });

  factory ReviewStatsModel.fromJson(Map<String, dynamic> json) {
    // 解析评分分布
    final distRaw = json['distribution'] as Map<String, dynamic>? ?? {};
    final distribution = <int, int>{};
    for (final entry in distRaw.entries) {
      final key = int.tryParse(entry.key);
      if (key != null) {
        distribution[key] = (entry.value as num).toInt();
      }
    }

    // 解析热门标签
    final tagsRaw = json['top_tags'] as List? ?? [];
    final tags = tagsRaw
        .map((t) => ReviewTag(
              tag: t['tag'] as String? ?? '',
              count: (t['count'] as num?)?.toInt() ?? 0,
            ))
        .where((t) => t.tag.isNotEmpty)
        .toList();

    return ReviewStatsModel(
      avgRating: (json['avg_rating'] as num?)?.toDouble() ?? 0.0,
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      ratingDistribution: distribution,
      topTags: tags,
      avgOverall: (json['avg_overall'] as num?)?.toDouble() ?? 0.0,
      avgEnvironment: (json['avg_environment'] as num?)?.toDouble() ?? 0.0,
      avgProduct: (json['avg_product'] as num?)?.toDouble() ?? 0.0,
      avgService: (json['avg_service'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// 空状态
  static const empty = ReviewStatsModel(
    avgRating: 0,
    totalCount: 0,
    ratingDistribution: {},
    topTags: [],
  );
}

/// 评价标签
class ReviewTag {
  final String tag;
  final int count;

  const ReviewTag({required this.tag, required this.count});
}
