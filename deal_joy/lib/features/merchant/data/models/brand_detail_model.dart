// V2.4 品牌详情数据模型
// 品牌聚合页展示用

class BrandDetailModel {
  final String id;
  final String name;
  final String? logoUrl;
  final String? description;
  final String? category;
  final String? website;
  final int storeCount;
  final List<BrandStoreModel> stores;

  const BrandDetailModel({
    required this.id,
    required this.name,
    this.logoUrl,
    this.description,
    this.category,
    this.website,
    this.storeCount = 0,
    this.stores = const [],
  });

  factory BrandDetailModel.fromJson(Map<String, dynamic> json) {
    // 门店列表解析
    final storesJson = json['merchants'] as List<dynamic>? ?? [];
    final stores = storesJson
        .map((e) => BrandStoreModel.fromJson(e as Map<String, dynamic>))
        .toList();

    return BrandDetailModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      logoUrl: json['logo_url'] as String?,
      description: json['description'] as String?,
      category: json['category'] as String?,
      website: json['website'] as String?,
      storeCount: stores.length,
      stores: stores,
    );
  }

  /// 所有门店的平均评分
  double get averageRating {
    if (stores.isEmpty) return 0;
    final total = stores.fold<double>(0, (sum, s) => sum + s.avgRating);
    return total / stores.length;
  }

  /// 所有门店的总评价数
  int get totalReviews =>
      stores.fold<int>(0, (sum, s) => sum + s.reviewCount);

  /// 所有门店的活跃 deal 数
  int get totalActiveDeals =>
      stores.fold<int>(0, (sum, s) => sum + s.activeDealCount);
}

/// 品牌下单个门店摘要
class BrandStoreModel {
  final String id;
  final String name;
  final String? address;
  final String? city;
  final String? phone;
  final String? logoUrl;
  final String? homepageCoverUrl;
  final double avgRating;
  final int reviewCount;
  final int activeDealCount;
  final double? lat;
  final double? lng;

  const BrandStoreModel({
    required this.id,
    required this.name,
    this.address,
    this.city,
    this.phone,
    this.logoUrl,
    this.homepageCoverUrl,
    this.avgRating = 0,
    this.reviewCount = 0,
    this.activeDealCount = 0,
    this.lat,
    this.lng,
  });

  factory BrandStoreModel.fromJson(Map<String, dynamic> json) {
    // 从 deals join 计算评分和活跃 deal 数
    final deals = json['deals'] as List<dynamic>? ?? [];
    double totalRating = 0;
    int totalReviews = 0;
    int activeCount = 0;

    for (final d in deals) {
      final deal = d as Map<String, dynamic>;
      if (deal['is_active'] == true) activeCount++;
      final r = (deal['rating'] as num?)?.toDouble() ?? 0;
      final rc = (deal['review_count'] as num?)?.toInt() ?? 0;
      if (rc > 0) {
        totalRating += r * rc;
        totalReviews += rc;
      }
    }

    return BrandStoreModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      address: json['address'] as String?,
      city: json['city'] as String?,
      phone: json['phone'] as String?,
      logoUrl: json['logo_url'] as String?,
      homepageCoverUrl: json['homepage_cover_url'] as String?,
      avgRating: totalReviews > 0 ? totalRating / totalReviews : 0,
      reviewCount: totalReviews,
      activeDealCount: activeCount,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
    );
  }
}
