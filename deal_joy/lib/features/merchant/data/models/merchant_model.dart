class MerchantModel {
  final String id;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? homepageCoverUrl;
  final String? address;
  final String? phone;
  final double? lat;
  final double? lng;
  // 聚合字段（来自关联 deals）
  final double? avgRating;
  final int? totalReviewCount;
  final int? activeDealCount;
  final double? bestDiscount;
  // Near Me 模式下的距离（英里）
  final double? distanceMiles;
  // 主分类（取第一个 active deal 的 category）
  final String? primaryCategory;
  // 广告投放标记
  final bool isSponsored;
  final String? campaignId;

  MerchantModel({
    required this.id,
    required this.name,
    this.description,
    this.logoUrl,
    this.homepageCoverUrl,
    this.address,
    this.phone,
    this.lat,
    this.lng,
    this.avgRating,
    this.totalReviewCount,
    this.activeDealCount,
    this.bestDiscount,
    this.distanceMiles,
    this.primaryCategory,
    this.isSponsored = false,
    this.campaignId,
  });

  /// 复制并设置距离
  MerchantModel copyWith({double? distanceMiles, String? primaryCategory}) {
    return MerchantModel(
      id: id,
      name: name,
      description: description,
      logoUrl: logoUrl,
      homepageCoverUrl: homepageCoverUrl,
      address: address,
      phone: phone,
      lat: lat,
      lng: lng,
      avgRating: avgRating,
      totalReviewCount: totalReviewCount,
      activeDealCount: activeDealCount,
      bestDiscount: bestDiscount,
      distanceMiles: distanceMiles ?? this.distanceMiles,
      primaryCategory: primaryCategory ?? this.primaryCategory,
      isSponsored: isSponsored,
      campaignId: campaignId,
    );
  }

  /// 复制并标记为广告投放商家
  MerchantModel copyWithSponsored({required bool isSponsored, String? campaignId}) {
    return MerchantModel(
      id: id,
      name: name,
      description: description,
      logoUrl: logoUrl,
      homepageCoverUrl: homepageCoverUrl,
      address: address,
      phone: phone,
      lat: lat,
      lng: lng,
      avgRating: avgRating,
      totalReviewCount: totalReviewCount,
      activeDealCount: activeDealCount,
      bestDiscount: bestDiscount,
      distanceMiles: distanceMiles,
      primaryCategory: primaryCategory,
      isSponsored: isSponsored,
      campaignId: campaignId ?? this.campaignId,
    );
  }

  factory MerchantModel.fromJson(Map<String, dynamic> json) {
    double? avgRating;
    int? totalReviewCount;
    int? activeDealCount;
    double? bestDiscount;
    String? primaryCategory;

    // 评分从 reviews 直接聚合，不随 deal 过期而消失
    final reviews = json['reviews'];
    if (reviews is List && reviews.isNotEmpty) {
      final ratings = reviews
          .map((r) => (r['rating'] as num?)?.toDouble())
          .whereType<double>()
          .toList();
      if (ratings.isNotEmpty) {
        avgRating = ratings.reduce((a, b) => a + b) / ratings.length;
        totalReviewCount = ratings.length;
      }
    }

    // deals 只用于 activeDealCount / bestDiscount / primaryCategory
    final deals = json['deals'];
    if (deals is List && deals.isNotEmpty) {
      final active = deals.where((d) => d['is_active'] == true).toList();
      activeDealCount = active.length;
      if (active.isNotEmpty) {
        final prices = active
            .map((d) => (d['discount_price'] as num?)?.toDouble())
            .whereType<double>()
            .toList();
        if (prices.isNotEmpty) {
          bestDiscount = prices.reduce((a, b) => a < b ? a : b);
        }
        primaryCategory = active.first['category'] as String?;
        // reviews 为空时回退到 deals.rating（Near Me RPC 路径不带 reviews 字段）
        if (avgRating == null) {
          final dealRatings = active
              .map((d) => (d['rating'] as num?)?.toDouble())
              .where((r) => r != null && r > 0)
              .whereType<double>()
              .toList();
          if (dealRatings.isNotEmpty) {
            avgRating = dealRatings.reduce((a, b) => a + b) / dealRatings.length;
            totalReviewCount = active.fold<int>(
                0, (sum, d) => sum + ((d['review_count'] as num?)?.toInt() ?? 0));
          }
        }
      }
    }

    return MerchantModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      logoUrl: json['logo_url'] as String?,
      homepageCoverUrl: json['homepage_cover_url'] as String?,
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      avgRating: avgRating,
      totalReviewCount: totalReviewCount,
      activeDealCount: activeDealCount,
      bestDiscount: bestDiscount,
      distanceMiles: (json['distance_miles'] as num?)?.toDouble(),
      primaryCategory: primaryCategory,
    );
  }
}
