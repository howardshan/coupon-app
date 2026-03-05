// Deal管理模块数据模型
// 包含 DealStatus、ValidityType 枚举，DealImage 和 MerchantDeal 类

// ============================================================
// DealStatus — Deal审核/上下架状态枚举
// ============================================================
enum DealStatus {
  /// 待审核（新建或修改后等待平台审核）
  pending,

  /// 已上架（审核通过且商家手动上架）
  active,

  /// 已下架（商家手动下架或售罄）
  inactive,

  /// 已拒绝（平台审核拒绝，含拒绝原因）
  rejected;

  /// 转换为 API 字符串
  String get value => name;

  /// 从 API 字符串解析
  static DealStatus fromString(String? value) {
    return DealStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => DealStatus.pending,
    );
  }

  /// 用户友好的显示标签
  String get displayLabel {
    switch (this) {
      case DealStatus.pending:
        return 'Pending Review';
      case DealStatus.active:
        return 'Active';
      case DealStatus.inactive:
        return 'Inactive';
      case DealStatus.rejected:
        return 'Rejected';
    }
  }
}

// ============================================================
// ValidityType — 有效期类型枚举
// ============================================================
enum ValidityType {
  /// 固定日期范围（有明确的开始日期和结束日期）
  fixedDate,

  /// 购买后X天内有效（过期自动退款，DealJoy特色）
  daysAfterPurchase;

  /// 转换为 API 字符串
  String get value {
    switch (this) {
      case ValidityType.fixedDate:
        return 'fixed_date';
      case ValidityType.daysAfterPurchase:
        return 'days_after_purchase';
    }
  }

  /// 从 API 字符串解析
  static ValidityType fromString(String? value) {
    switch (value) {
      case 'fixed_date':
        return ValidityType.fixedDate;
      case 'days_after_purchase':
        return ValidityType.daysAfterPurchase;
      default:
        return ValidityType.fixedDate;
    }
  }

  /// 用户友好的显示标签
  String get displayLabel {
    switch (this) {
      case ValidityType.fixedDate:
        return 'Fixed Date Range';
      case ValidityType.daysAfterPurchase:
        return 'Days After Purchase';
    }
  }
}

// ============================================================
// DealImage — 单张 Deal 图片
// ============================================================
class DealImage {
  const DealImage({
    required this.id,
    required this.dealId,
    required this.imageUrl,
    required this.sortOrder,
    required this.isPrimary,
    required this.createdAt,
  });

  final String id;
  final String dealId;
  final String imageUrl;
  final int sortOrder;

  /// 是否为主图（封面图）
  final bool isPrimary;
  final DateTime createdAt;

  /// 从 Supabase JSON 构造
  factory DealImage.fromJson(Map<String, dynamic> json) {
    return DealImage(
      id:         json['id'] as String,
      dealId:     json['deal_id'] as String? ?? '',
      imageUrl:   json['image_url'] as String,
      sortOrder:  json['sort_order'] as int? ?? 0,
      isPrimary:  json['is_primary'] as bool? ?? false,
      createdAt:  DateTime.parse(json['created_at'] as String),
    );
  }

  /// 转为 API 请求 JSON
  Map<String, dynamic> toJson() => {
        'id':         id,
        'deal_id':    dealId,
        'image_url':  imageUrl,
        'sort_order': sortOrder,
        'is_primary': isPrimary,
        'created_at': createdAt.toIso8601String(),
      };

  /// 复制并修改部分字段
  DealImage copyWith({
    String? id,
    String? dealId,
    String? imageUrl,
    int? sortOrder,
    bool? isPrimary,
    DateTime? createdAt,
  }) {
    return DealImage(
      id:         id ?? this.id,
      dealId:     dealId ?? this.dealId,
      imageUrl:   imageUrl ?? this.imageUrl,
      sortOrder:  sortOrder ?? this.sortOrder,
      isPrimary:  isPrimary ?? this.isPrimary,
      createdAt:  createdAt ?? this.createdAt,
    );
  }
}

// ============================================================
// MerchantDeal — 完整 Deal 数据模型
// 对应 deals 表（含新增字段）
// ============================================================
class MerchantDeal {
  const MerchantDeal({
    required this.id,
    required this.merchantId,
    required this.title,
    required this.description,
    required this.category,
    required this.originalPrice,
    required this.discountPrice,
    required this.stockLimit,
    required this.totalSold,
    required this.rating,
    required this.reviewCount,
    required this.isActive,
    required this.dealStatus,
    required this.validityType,
    required this.expiresAt,
    required this.usageDays,
    required this.isStackable,
    required this.images,
    required this.createdAt,
    required this.updatedAt,
    this.discountPercent,
    this.packageContents = '',
    this.usageNotes = '',
    this.maxPerPerson,
    this.validityDays,
    this.reviewNotes,
    this.publishedAt,
  });

  /// Deal ID
  final String id;

  /// 所属商家 ID
  final String merchantId;

  /// 标题
  final String title;

  /// 描述
  final String description;

  /// 类别（如 Restaurant、Spa 等）
  final String category;

  /// 原价（美元）
  final double originalPrice;

  /// 现价（美元）
  final double discountPrice;

  /// 折扣百分比（由数据库生成字段自动计算）
  final int? discountPercent;

  /// 库存数量（-1 表示无限制）
  final int stockLimit;

  /// 已售出数量
  final int totalSold;

  /// 平均评分
  final double rating;

  /// 评价数量
  final int reviewCount;

  /// 是否当前处于上架状态（is_active）
  final bool isActive;

  /// 审核状态
  final DealStatus dealStatus;

  /// 套餐包含内容
  final String packageContents;

  /// 使用须知
  final String usageNotes;

  /// 有效期类型
  final ValidityType validityType;

  /// 固定日期类型的过期时间
  final DateTime expiresAt;

  /// 购买后有效天数（仅 daysAfterPurchase 类型使用）
  final int? validityDays;

  /// 可用星期（空数组=全周可用）
  final List<String> usageDays;

  /// 每人限用数量（null=不限）
  final int? maxPerPerson;

  /// 是否可叠加其他优惠
  final bool isStackable;

  /// 审核拒绝原因（仅 rejected 状态有值）
  final String? reviewNotes;

  /// 首次上架时间
  final DateTime? publishedAt;

  /// 图片列表（含主图）
  final List<DealImage> images;

  /// 创建时间
  final DateTime createdAt;

  /// 更新时间
  final DateTime updatedAt;

  // --------------------------------------------------------
  // 计算属性
  // --------------------------------------------------------

  /// 是否为无限库存
  bool get isUnlimited => stockLimit == -1;

  /// 剩余库存
  int get remainingStock => isUnlimited ? -1 : (stockLimit - totalSold);

  /// 是否已售罄
  bool get isSoldOut => !isUnlimited && remainingStock <= 0;

  /// 主图 URL（第一张 is_primary=true 的图，或第一张图）
  String? get coverImageUrl {
    if (images.isEmpty) return null;
    final primary = images.where((img) => img.isPrimary).toList();
    if (primary.isNotEmpty) return primary.first.imageUrl;
    final sorted = [...images]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return sorted.first.imageUrl;
  }

  /// 折扣文案（如 "40% OFF"）
  String get discountLabel {
    final percent = discountPercent ??
        ((1 - discountPrice / originalPrice) * 100).round();
    return '$percent% OFF';
  }

  /// 是否可以手动上架（审核通过后 inactive → active）
  bool get canActivate => dealStatus == DealStatus.inactive;

  /// 是否可以下架
  bool get canDeactivate => dealStatus == DealStatus.active;

  /// 是否可以编辑（所有状态都允许编辑）
  bool get canEdit => true;

  // --------------------------------------------------------
  // 序列化/反序列化
  // --------------------------------------------------------

  /// 从 Edge Function 返回的 JSON 构造
  factory MerchantDeal.fromJson(Map<String, dynamic> json) {
    // 图片列表：可能来自 join 结果（deal_images 数组）
    final imagesJson = json['deal_images'] as List<dynamic>? ?? [];
    final imagesSorted = imagesJson
        .map((e) => DealImage.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return MerchantDeal(
      id:              json['id'] as String,
      merchantId:      json['merchant_id'] as String? ?? '',
      title:           json['title'] as String,
      description:     json['description'] as String,
      category:        json['category'] as String,
      originalPrice:   (json['original_price'] as num).toDouble(),
      discountPrice:   (json['discount_price'] as num).toDouble(),
      discountPercent: json['discount_percent'] as int?,
      stockLimit:      json['stock_limit'] as int? ?? 100,
      totalSold:       json['total_sold'] as int? ?? 0,
      rating:          (json['rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount:     json['review_count'] as int? ?? 0,
      isActive:        json['is_active'] as bool? ?? false,
      dealStatus:      DealStatus.fromString(json['deal_status'] as String?),
      packageContents: json['package_contents'] as String? ?? '',
      usageNotes:      json['usage_notes'] as String? ?? '',
      validityType:    ValidityType.fromString(json['validity_type'] as String?),
      expiresAt:       DateTime.parse(json['expires_at'] as String),
      validityDays:    json['validity_days'] as int?,
      usageDays:       List<String>.from(json['usage_days'] as List<dynamic>? ?? []),
      maxPerPerson:    json['max_per_person'] as int?,
      isStackable:     json['is_stackable'] as bool? ?? true,
      reviewNotes:     json['review_notes'] as String?,
      publishedAt:     json['published_at'] != null
          ? DateTime.parse(json['published_at'] as String)
          : null,
      images:          imagesSorted,
      createdAt:       DateTime.parse(json['created_at'] as String),
      updatedAt:       DateTime.parse(json['updated_at'] as String),
    );
  }

  /// 转为 Edge Function 请求 JSON（创建/更新用）
  Map<String, dynamic> toJson() => {
        'merchant_id':      merchantId,
        'title':            title,
        'description':      description,
        'category':         category,
        'original_price':   originalPrice,
        'discount_price':   discountPrice,
        'stock_limit':      stockLimit,
        'expires_at':       expiresAt.toIso8601String(),
        'package_contents': packageContents,
        'usage_notes':      usageNotes,
        'validity_type':    validityType.value,
        'validity_days':    validityDays,
        'usage_days':       usageDays,
        'max_per_person':   maxPerPerson,
        'is_stackable':     isStackable,
      };

  /// 复制并修改部分字段
  MerchantDeal copyWith({
    String? id,
    String? merchantId,
    String? title,
    String? description,
    String? category,
    double? originalPrice,
    double? discountPrice,
    int? discountPercent,
    int? stockLimit,
    int? totalSold,
    double? rating,
    int? reviewCount,
    bool? isActive,
    DealStatus? dealStatus,
    String? packageContents,
    String? usageNotes,
    ValidityType? validityType,
    DateTime? expiresAt,
    int? validityDays,
    List<String>? usageDays,
    int? maxPerPerson,
    bool? isStackable,
    String? reviewNotes,
    DateTime? publishedAt,
    List<DealImage>? images,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MerchantDeal(
      id:              id ?? this.id,
      merchantId:      merchantId ?? this.merchantId,
      title:           title ?? this.title,
      description:     description ?? this.description,
      category:        category ?? this.category,
      originalPrice:   originalPrice ?? this.originalPrice,
      discountPrice:   discountPrice ?? this.discountPrice,
      discountPercent: discountPercent ?? this.discountPercent,
      stockLimit:      stockLimit ?? this.stockLimit,
      totalSold:       totalSold ?? this.totalSold,
      rating:          rating ?? this.rating,
      reviewCount:     reviewCount ?? this.reviewCount,
      isActive:        isActive ?? this.isActive,
      dealStatus:      dealStatus ?? this.dealStatus,
      packageContents: packageContents ?? this.packageContents,
      usageNotes:      usageNotes ?? this.usageNotes,
      validityType:    validityType ?? this.validityType,
      expiresAt:       expiresAt ?? this.expiresAt,
      validityDays:    validityDays ?? this.validityDays,
      usageDays:       usageDays ?? this.usageDays,
      maxPerPerson:    maxPerPerson ?? this.maxPerPerson,
      isStackable:     isStackable ?? this.isStackable,
      reviewNotes:     reviewNotes ?? this.reviewNotes,
      publishedAt:     publishedAt ?? this.publishedAt,
      images:          images ?? this.images,
      createdAt:       createdAt ?? this.createdAt,
      updatedAt:       updatedAt ?? this.updatedAt,
    );
  }
}
