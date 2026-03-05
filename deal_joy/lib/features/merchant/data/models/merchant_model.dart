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
  });

  factory MerchantModel.fromJson(Map<String, dynamic> json) {
    // 聚合关联 deals 数据
    double? avgRating;
    int? totalReviewCount;
    int? activeDealCount;
    double? bestDiscount;

    final deals = json['deals'];
    if (deals is List && deals.isNotEmpty) {
      final active = deals.where((d) => d['is_active'] == true).toList();
      activeDealCount = active.length;
      if (active.isNotEmpty) {
        final ratings = active
            .map((d) => (d['rating'] as num?)?.toDouble())
            .whereType<double>()
            .toList();
        if (ratings.isNotEmpty) {
          avgRating = ratings.reduce((a, b) => a + b) / ratings.length;
        }
        totalReviewCount = active.fold<int>(
            0, (sum, d) => sum + ((d['review_count'] as num?)?.toInt() ?? 0));
        final prices = active
            .map((d) => (d['discount_price'] as num?)?.toDouble())
            .whereType<double>()
            .toList();
        if (prices.isNotEmpty) {
          bestDiscount = prices.reduce((a, b) => a < b ? a : b);
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
    );
  }
}
