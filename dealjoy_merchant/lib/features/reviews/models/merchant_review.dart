// 评价管理模块数据模型
// 包含: MerchantReview（单条评价） + ReviewStats（统计数据）
//       PagedReviews（分页评价列表） + ReviewsFilter（筛选条件）

// =============================================================
// MerchantReview — 单条评价
// =============================================================
class MerchantReview {
  final String id;            // 评价 UUID
  final String userName;      // 用户显示名
  final String? avatarUrl;    // 用户头像（可为 null）
  final int rating;           // 1-5 星
  final String? content;      // 评价文本（可为 null）
  final List<String> imageUrls;  // 图片 URL 列表（暂时为空，后续支持）
  final String? merchantReply;   // 商家回复（null 表示未回复）
  final DateTime? repliedAt;     // 回复时间（null 表示未回复）
  final DateTime createdAt;      // 评价创建时间

  const MerchantReview({
    required this.id,
    required this.userName,
    this.avatarUrl,
    required this.rating,
    this.content,
    this.imageUrls = const [],
    this.merchantReply,
    this.repliedAt,
    required this.createdAt,
  });

  /// 是否已回复
  bool get hasReply => merchantReply != null && merchantReply!.isNotEmpty;

  /// 从 Edge Function JSON 解析
  factory MerchantReview.fromJson(Map<String, dynamic> json) {
    // 解析图片 URL 列表
    final rawImages = json['image_urls'];
    final imageUrls = rawImages is List
        ? rawImages.map((e) => e.toString()).toList()
        : <String>[];

    return MerchantReview(
      id:             json['id'] as String? ?? '',
      userName:       json['user_name'] as String? ?? 'Anonymous',
      avatarUrl:      json['avatar_url'] as String?,
      rating:         (json['rating'] as num?)?.toInt() ?? 1,
      content:        json['comment'] as String?,
      imageUrls:      imageUrls,
      merchantReply:  json['merchant_reply'] as String?,
      repliedAt:      json['replied_at'] != null
          ? DateTime.tryParse(json['replied_at'] as String)
          : null,
      createdAt:      DateTime.tryParse(json['created_at'] as String? ?? '') ??
                      DateTime.now(),
    );
  }

  /// 返回附带新回复的副本（本地乐观更新用）
  MerchantReview copyWithReply(String reply, DateTime repliedAt) {
    return MerchantReview(
      id:             id,
      userName:       userName,
      avatarUrl:      avatarUrl,
      rating:         rating,
      content:        content,
      imageUrls:      imageUrls,
      merchantReply:  reply,
      repliedAt:      repliedAt,
      createdAt:      createdAt,
    );
  }
}

// =============================================================
// ReviewStats — 评价统计数据
// =============================================================
class ReviewStats {
  final double avgRating;                // 平均评分（0.0 - 5.0）
  final int totalCount;                  // 评价总数
  final Map<int, int> ratingDistribution; // 各星评价数量 {1: n, 2: n, ..., 5: n}
  final List<String> topKeywords;        // 高频关键词（最多10个）

  const ReviewStats({
    required this.avgRating,
    required this.totalCount,
    required this.ratingDistribution,
    required this.topKeywords,
  });

  /// 获取指定星级的评价数量（1-5）
  int countForRating(int star) => ratingDistribution[star] ?? 0;

  /// 获取指定星级的百分比（0.0 - 1.0）
  double percentForRating(int star) {
    if (totalCount == 0) return 0.0;
    return countForRating(star) / totalCount;
  }

  /// 从 Edge Function JSON 解析
  factory ReviewStats.fromJson(Map<String, dynamic> json) {
    // 解析评分分布（key 为字符串数字）
    final rawDist = json['rating_distribution'] as Map<String, dynamic>? ?? {};
    final distribution = <int, int>{};
    for (var i = 1; i <= 5; i++) {
      distribution[i] = (rawDist[i.toString()] as num?)?.toInt() ?? 0;
    }

    // 解析关键词列表
    final rawKeywords = json['top_keywords'];
    final keywords = rawKeywords is List
        ? rawKeywords.map((e) => e.toString()).toList()
        : <String>[];

    return ReviewStats(
      avgRating:          (json['avg_rating'] as num?)?.toDouble() ?? 0.0,
      totalCount:         (json['total_count'] as num?)?.toInt() ?? 0,
      ratingDistribution: distribution,
      topKeywords:        keywords,
    );
  }

  /// 空统计（尚无评价时的默认值）
  factory ReviewStats.empty() {
    return ReviewStats(
      avgRating:          0.0,
      totalCount:         0,
      ratingDistribution: {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
      topKeywords:        [],
    );
  }
}

// =============================================================
// PagedReviews — 分页评价列表
// =============================================================
class PagedReviews {
  final List<MerchantReview> data;  // 当前页数据
  final int page;                   // 当前页码
  final int perPage;                // 每页条数
  final int total;                  // 总条数
  final bool hasMore;               // 是否还有更多

  const PagedReviews({
    required this.data,
    required this.page,
    required this.perPage,
    required this.total,
    required this.hasMore,
  });

  /// 从 Edge Function JSON 解析
  factory PagedReviews.fromJson(Map<String, dynamic> json) {
    final rawList = json['data'] as List<dynamic>? ?? [];
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};

    return PagedReviews(
      data: rawList
          .map((item) =>
              MerchantReview.fromJson(item as Map<String, dynamic>))
          .toList(),
      page:    (pagination['page'] as num?)?.toInt() ?? 1,
      perPage: (pagination['per_page'] as num?)?.toInt() ?? 20,
      total:   (pagination['total'] as num?)?.toInt() ?? 0,
      hasMore: pagination['has_more'] as bool? ?? false,
    );
  }

  /// 空列表（无评价时的默认值）
  factory PagedReviews.empty() {
    return const PagedReviews(
      data:    [],
      page:    1,
      perPage: 20,
      total:   0,
      hasMore: false,
    );
  }

  /// 将指定评价替换为新版本（本地乐观更新用）
  PagedReviews replaceReview(MerchantReview updated) {
    final newData = data.map((r) => r.id == updated.id ? updated : r).toList();
    return PagedReviews(
      data:    newData,
      page:    page,
      perPage: perPage,
      total:   total,
      hasMore: hasMore,
    );
  }
}

// =============================================================
// ReviewsFilter — 评价列表筛选条件
// =============================================================
class ReviewsFilter {
  final int? ratingFilter; // null = 全部；1-5 = 筛选对应星级
  final int page;          // 当前页码

  const ReviewsFilter({
    this.ratingFilter,
    this.page = 1,
  });

  /// 是否有筛选条件
  bool get hasFilter => ratingFilter != null;

  ReviewsFilter copyWith({
    int? ratingFilter,
    bool clearRating = false,
    int? page,
  }) {
    return ReviewsFilter(
      ratingFilter: clearRating ? null : (ratingFilter ?? this.ratingFilter),
      page:         page ?? this.page,
    );
  }
}
