// ============================================================
// DealOptionItem — 选项项（用户端）
// ============================================================
class DealOptionItem {
  final String id;
  final String name;
  final double price;
  final int sortOrder;

  const DealOptionItem({
    required this.id,
    required this.name,
    required this.price,
    this.sortOrder = 0,
  });

  factory DealOptionItem.fromJson(Map<String, dynamic> json) => DealOptionItem(
    id:        json['id'] as String? ?? '',
    name:      json['name'] as String? ?? '',
    price:     (json['price'] as num?)?.toDouble() ?? 0,
    sortOrder: json['sort_order'] as int? ?? 0,
  );
}

// ============================================================
// DealOptionGroup — 选项组（用户端）
// ============================================================
class DealOptionGroup {
  final String id;
  final String name;
  final int selectMin;
  final int selectMax;
  final int sortOrder;
  final List<DealOptionItem> items;

  const DealOptionGroup({
    required this.id,
    required this.name,
    required this.selectMin,
    required this.selectMax,
    this.sortOrder = 0,
    this.items = const [],
  });

  factory DealOptionGroup.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['deal_option_items'] as List<dynamic>? ?? [];
    final items = itemsJson
        .map((e) => DealOptionItem.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return DealOptionGroup(
      id:        json['id'] as String? ?? '',
      name:      json['name'] as String? ?? '',
      selectMin: json['select_min'] as int? ?? 1,
      selectMax: json['select_max'] as int? ?? 1,
      sortOrder: json['sort_order'] as int? ?? 0,
      items:     items,
    );
  }

  /// 显示标签，如 "Pick 3 from 8"
  String get displayLabel => 'Pick $selectMin${selectMin != selectMax ? '-$selectMax' : ''} from ${items.length}';
}

// ============================================================
// DealModel
// ============================================================
class DealModel {
  final String id;
  final String merchantId;
  final String title;
  final String description;
  final String category;
  final double originalPrice;
  final double discountPrice;
  final int discountPercent;
  final String discountLabel; // e.g. "40% OFF", "BUY 1 GET 1"
  final List<String> imageUrls;
  final List<String> products; // included products list
  final double rating;
  final int reviewCount;
  final int totalSold;
  final int stockLimit;
  final DateTime expiresAt;
  final bool isFeatured;
  final String refundPolicy;
  final double? lat;
  final double? lng;
  final String? address;
  final String? merchantHours;
  final MerchantSummary? merchant;
  // 搜索结果附加字段
  final double? distanceMeters;
  final String? merchantCity;
  // V2 新增字段
  final String dealType; // 'voucher' | 'regular'
  final String? dealCategoryId;
  final String? badgeText; // 自定义角标，如 "Best Value"
  final int? sortOrder; // 首页展示排序，NULL 表示不展示
  // 多店通用：适用门店 ID 列表（null = 仅创建门店，直接表查询时才有）
  final List<String>? applicableMerchantIds;
  // RPC 搜索结果：active 门店数（search_deals_nearby/search_deals_by_city 返回）
  final int? activeStoreCount;
  // 套餐短名称（用于变体选择器横向展示）
  final String? shortName;
  // 商家填写的使用须知
  final String usageNotes;
  // 选项组（"几选几"功能，如 "Side: pick 2 from 4"）
  final List<DealOptionGroup> optionGroups;

  const DealModel({
    required this.id,
    required this.merchantId,
    required this.title,
    required this.description,
    required this.category,
    required this.originalPrice,
    required this.discountPrice,
    required this.discountPercent,
    this.discountLabel = '',
    required this.imageUrls,
    this.products = const [],
    this.rating = 0.0,
    this.reviewCount = 0,
    this.totalSold = 0,
    required this.stockLimit,
    required this.expiresAt,
    this.isFeatured = false,
    this.refundPolicy = 'Refund anytime before use, refund when expired',
    this.lat,
    this.lng,
    this.address,
    this.merchantHours,
    this.merchant,
    this.distanceMeters,
    this.merchantCity,
    this.dealType = 'regular',
    this.dealCategoryId,
    this.badgeText,
    this.sortOrder,
    this.applicableMerchantIds,
    this.activeStoreCount,
    this.shortName,
    this.usageNotes = '',
    this.optionGroups = const [],
  });

  factory DealModel.fromJson(Map<String, dynamic> json) => DealModel(
        id: json['id'] as String,
        merchantId: json['merchant_id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        category: json['category'] as String,
        originalPrice: (json['original_price'] as num).toDouble(),
        discountPrice: (json['discount_price'] as num).toDouble(),
        discountPercent: json['discount_percent'] as int? ??
            ((1 - (json['discount_price'] as num) / (json['original_price'] as num)) * 100).round(),
        discountLabel: json['discount_label'] as String? ?? '',
        imageUrls: List<String>.from(json['image_urls'] as List? ?? []),
        products: _parseProducts(json),
        rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
        reviewCount: json['review_count'] as int? ?? 0,
        totalSold: json['total_sold'] as int? ?? 0,
        stockLimit: json['stock_limit'] as int? ?? 100,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        isFeatured: json['is_featured'] as bool? ?? false,
        refundPolicy: json['refund_policy'] as String? ??
            'Refund anytime before use, refund when expired',
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        address: json['address'] as String?,
        merchantHours: json['merchant_hours'] as String?,
        merchant: json['merchants'] != null
            ? MerchantSummary.fromJson(
                json['merchants'] as Map<String, dynamic>)
            : null,
        dealType: json['deal_type'] as String? ?? 'regular',
        dealCategoryId: json['deal_category_id'] as String?,
        badgeText: json['badge_text'] as String?,
        sortOrder: json['sort_order'] as int?,
        applicableMerchantIds: (json['applicable_merchant_ids'] as List?)
            ?.map((e) => e?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList(),
        activeStoreCount: null, // 直接表查询不返回此字段
        shortName: json['short_name'] as String?,
        usageNotes: json['usage_notes'] as String? ?? '',
        optionGroups: _parseOptionGroups(json),
      );

  // RPC 搜索结果（search_deals_nearby / search_deals_by_city）解析
  factory DealModel.fromSearchJson(Map<String, dynamic> json) => DealModel(
        id: json['id'] as String,
        merchantId: json['merchant_id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        category: json['category'] as String,
        originalPrice: (json['original_price'] as num).toDouble(),
        discountPrice: (json['discount_price'] as num).toDouble(),
        discountPercent: json['discount_percent'] as int? ?? 0,
        discountLabel: json['discount_label'] as String? ?? '',
        imageUrls: List<String>.from(json['image_urls'] as List? ?? []),
        isFeatured: json['is_featured'] as bool? ?? false,
        rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
        reviewCount: json['review_count'] as int? ?? 0,
        totalSold: json['total_sold'] as int? ?? 0,
        stockLimit: 100,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        merchant: MerchantSummary(
          id: json['merchant_id'] as String,
          name: json['merchant_name'] as String? ?? '',
          logoUrl: json['merchant_logo_url'] as String?,
          homepageCoverUrl: json['merchant_homepage_cover_url'] as String?,
          brandName: json['merchant_brand_name'] as String?,
        ),
        distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
        merchantCity: json['merchant_city'] as String?,
        dealType: json['deal_type'] as String? ?? 'regular',
        dealCategoryId: json['deal_category_id'] as String?,
        badgeText: json['badge_text'] as String?,
        sortOrder: json['sort_order'] as int?,
        applicableMerchantIds: null, // RPC 不再返回此字段，改为 active_store_count
        activeStoreCount: (json['active_store_count'] as num?)?.toInt(),
        shortName: json['short_name'] as String?,
      );

  /// 解析产品列表：优先读 products 数组，为空时从 package_contents 文本按行解析
  static List<String> _parseProducts(Map<String, dynamic> json) {
    final raw = json['dishes'] as List? ?? [];
    if (raw.isNotEmpty) return List<String>.from(raw);
    // fallback: 从 package_contents 文本按行拆分
    final pc = json['package_contents'] as String? ?? '';
    if (pc.isEmpty) return [];
    return pc
        .split('\n')
        .map((line) {
          var s = line.replaceFirst(RegExp(r'^[•\-\*]\s*'), '').trim();
          // 提取数量前缀 "2× " / "2x "
          int qty = 1;
          final qtyMatch = RegExp(r'^(\d+)\s*[×xX]\s*').firstMatch(s);
          if (qtyMatch != null) {
            qty = int.parse(qtyMatch.group(1)!);
            s = s.substring(qtyMatch.end).trim();
          }
          // 提取尾部单价 " @15.0"
          double? unitPrice;
          final priceMatch = RegExp(r'\s+@([\d.]+)$').firstMatch(s);
          if (priceMatch != null) {
            unitPrice = double.tryParse(priceMatch.group(1)!);
            s = s.substring(0, priceMatch.start).trim();
          }
          // 格式: "name::qty::subtotal"
          final subtotal = unitPrice != null ? (unitPrice * qty).toStringAsFixed(0) : '';
          return '$s::$qty::$subtotal';
        })
        .where((line) => line.isNotEmpty)
        .toList();
  }

  /// 解析选项组列表
  static List<DealOptionGroup> _parseOptionGroups(Map<String, dynamic> json) {
    final raw = json['deal_option_groups'] as List<dynamic>?;
    if (raw == null || raw.isEmpty) return [];
    final list = raw
        .map((e) => DealOptionGroup.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get timeLeft => expiresAt.difference(DateTime.now());

  double get savingsAmount => originalPrice - discountPrice;

  String get effectiveDiscountLabel => discountLabel.isNotEmpty
      ? discountLabel
      : '$discountPercent% OFF';
}

class MerchantSummary {
  final String id;
  final String name;
  final String? logoUrl;
  final String? phone;
  final String? address;
  final String? hours;
  final String? homepageCoverUrl;
  final double rating;
  final int reviewCount;
  // 品牌信息（连锁店才有）
  final String? brandName;
  final String? brandLogoUrl;

  const MerchantSummary({
    required this.id,
    required this.name,
    this.logoUrl,
    this.phone,
    this.address,
    this.hours,
    this.homepageCoverUrl,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.brandName,
    this.brandLogoUrl,
  });

  /// 是否为连锁店品牌
  bool get isChainStore => brandName != null && brandName!.isNotEmpty;

  factory MerchantSummary.fromJson(Map<String, dynamic> json) =>
      MerchantSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        logoUrl: json['logo_url'] as String?,
        phone: json['phone'] as String?,
        address: json['address'] as String?,
        hours: json['hours'] as String?,
        homepageCoverUrl: json['homepage_cover_url'] as String?,
        rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
        reviewCount: json['review_count'] as int? ?? 0,
        // 品牌信息从 brands join 获取
        brandName: (json['brands'] as Map<String, dynamic>?)?['name'] as String?,
        brandLogoUrl: (json['brands'] as Map<String, dynamic>?)?['logo_url'] as String?,
      );
}
