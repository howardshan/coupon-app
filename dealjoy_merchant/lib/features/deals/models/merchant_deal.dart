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
  rejected,

  /// 已过期（按 expires_at 计算，仅用于展示，不持久化）
  expired;

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
      case DealStatus.expired:
        return 'Expired';
    }
  }
}

// ============================================================
// ValidityType — 有效期类型枚举
// ============================================================
enum ValidityType {
  /// 固定日期到期（商家设置具体到期日）
  fixedDate,

  /// 购买后 1-7 天内有效（Stripe 预授权模式，核销时才实收）
  shortAfterPurchase,

  /// 购买后 8-365 天内有效（立即扣款，退款时走正常流程）
  longAfterPurchase;

  /// 转换为 API 字符串
  String get value => switch (this) {
    ValidityType.fixedDate          => 'fixed_date',
    ValidityType.shortAfterPurchase => 'short_after_purchase',
    ValidityType.longAfterPurchase  => 'long_after_purchase',
  };

  /// 从 API 字符串解析
  static ValidityType fromString(String? value) => switch (value) {
    'fixed_date'           => ValidityType.fixedDate,
    'short_after_purchase' => ValidityType.shortAfterPurchase,
    'long_after_purchase'  => ValidityType.longAfterPurchase,
    // 向后兼容旧数据（迁移前的 days_after_purchase）
    'days_after_purchase'  => ValidityType.longAfterPurchase,
    _                      => ValidityType.fixedDate,
  };

  /// 用户友好的显示标签
  String get displayLabel => switch (this) {
    ValidityType.fixedDate          => 'Fixed Date',
    ValidityType.shortAfterPurchase => 'Short-term (1–7 days)',
    ValidityType.longAfterPurchase  => 'Long-term (8–365 days)',
  };
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
      id:         json['id'] as String? ?? '',
      dealId:     json['deal_id'] as String? ?? '',
      imageUrl:   json['image_url'] as String? ?? '',
      sortOrder:  json['sort_order'] as int? ?? 0,
      isPrimary:  json['is_primary'] as bool? ?? false,
      createdAt:  json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
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
// DealOptionItem — 选项项（如 "Grilled Salmon"）
// ============================================================
class DealOptionItem {
  const DealOptionItem({
    this.id,
    required this.name,
    required this.price,
    this.sortOrder = 0,
  });

  final String? id;
  final String name;
  final double price;
  final int sortOrder;

  factory DealOptionItem.fromJson(Map<String, dynamic> json) {
    return DealOptionItem(
      id:        json['id'] as String?,
      name:      json['name'] as String? ?? '',
      price:     (json['price'] as num?)?.toDouble() ?? 0,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'price': price,
    'sort_order': sortOrder,
  };

  DealOptionItem copyWith({String? id, String? name, double? price, int? sortOrder}) {
    return DealOptionItem(
      id:        id ?? this.id,
      name:      name ?? this.name,
      price:     price ?? this.price,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

// ============================================================
// DealOptionGroup — 选项组（如 "Main Course: pick 3 from 8"）
// ============================================================
class DealOptionGroup {
  const DealOptionGroup({
    this.id,
    required this.name,
    required this.selectMin,
    required this.selectMax,
    this.sortOrder = 0,
    this.items = const [],
  });

  final String? id;
  final String name;
  final int selectMin;
  final int selectMax;
  final int sortOrder;
  final List<DealOptionItem> items;

  factory DealOptionGroup.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['deal_option_items'] as List<dynamic>? ?? [];
    return DealOptionGroup(
      id:        json['id'] as String?,
      name:      json['name'] as String? ?? '',
      selectMin: json['select_min'] as int? ?? 1,
      selectMax: json['select_max'] as int? ?? 1,
      sortOrder: json['sort_order'] as int? ?? 0,
      items: itemsJson
          .map((e) => DealOptionItem.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'select_min': selectMin,
    'select_max': selectMax,
    'sort_order': sortOrder,
    'items': items.map((e) => e.toJson()).toList(),
  };

  DealOptionGroup copyWith({
    String? id,
    String? name,
    int? selectMin,
    int? selectMax,
    int? sortOrder,
    List<DealOptionItem>? items,
  }) {
    return DealOptionGroup(
      id:        id ?? this.id,
      name:      name ?? this.name,
      selectMin: selectMin ?? this.selectMin,
      selectMax: selectMax ?? this.selectMax,
      sortOrder: sortOrder ?? this.sortOrder,
      items:     items ?? this.items,
    );
  }

  /// 显示标签：selectMin == items.length 时只显示组名，否则 "Select X from Y"
  String get displayLabel => selectMin == items.length
      ? '$name'
      : 'Select $selectMin from ${items.length}';
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
    this.dealCategoryId,
    this.applicableMerchantIds,
    this.storeConfirmations,
    this.shortName,
    this.dealType = 'regular',
    this.usageNoteImages = const [],
    this.dishes = const [],
    this.optionGroups = const [],
    this.detailImages = const [],
    this.usageRules = const [],
    this.maxPerAccount = -1,
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

  /// 使用须知附带的图片/视频 URL 列表
  final List<String> usageNoteImages;

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

  /// Deal 分类 ID（关联 deal_categories 表）
  final String? dealCategoryId;

  /// 适用门店 ID 列表（null = 仅本店，非空 = 多店通用）
  final List<String>? applicableMerchantIds;

  /// 门店预确认数据（brand_multi_store deal 创建时传给 Edge Function）
  /// 格式：[{ 'store_id': 'uuid', 'pre_confirmed': true/false }]
  final List<Map<String, dynamic>>? storeConfirmations;

  /// 短名称（最多10字符，用于变体选择器展示）
  final String? shortName;

  /// Deal 类型：'regular'（套餐券）/ 'voucher'（抵用券）
  final String dealType;

  /// 菜品列表（格式："name::qty::subtotal"），用于用户端展示每行价格
  final List<String> dishes;

  /// 选项组列表（"几选几"功能）
  final List<DealOptionGroup> optionGroups;

  /// 详情页多图列表（区别于封面图 image_urls）
  final List<String> detailImages;

  /// 使用规则列表（多条文本，如 "No takeout"）
  final List<String> usageRules;

  /// 每账户限购数量（-1=无限制，正数=具体上限）
  final int maxPerAccount;

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

  /// 是否已按日期过期（expires_at 已过，用于展示「Expired」状态）
  bool get isExpiredByDate => DateTime.now().isAfter(expiresAt);

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

  /// 从 Edge Function 返回的 JSON 构造
  factory MerchantDeal.fromJson(Map<String, dynamic> json) {
    // 图片列表：可能来自 join 结果（deal_images 数组）
    final imagesJson = json['deal_images'] as List<dynamic>? ?? [];
    final imagesSorted = imagesJson
        .map((e) => DealImage.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return MerchantDeal(
      id:              json['id'] as String? ?? '',
      merchantId:      json['merchant_id'] as String? ?? '',
      title:           json['title'] as String? ?? '',
      description:     json['description'] as String? ?? '',
      category:        json['category'] as String? ?? '',
      originalPrice:   (json['original_price'] as num?)?.toDouble() ?? 0,
      discountPrice:   (json['discount_price'] as num?)?.toDouble() ?? 0,
      discountPercent: json['discount_percent'] as int?,
      stockLimit:      json['stock_limit'] as int? ?? 100,
      totalSold:       json['total_sold'] as int? ?? 0,
      rating:          (json['rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount:     json['review_count'] as int? ?? 0,
      isActive:        json['is_active'] as bool? ?? false,
      dealStatus:      DealStatus.fromString(json['deal_status'] as String?),
      packageContents: json['package_contents'] as String? ?? '',
      usageNotes:      json['usage_notes'] as String? ?? '',
      usageNoteImages: (json['usage_note_images'] as List<dynamic>?)
          ?.map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList() ?? [],
      validityType:    ValidityType.fromString(json['validity_type'] as String?),
      expiresAt:       json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : DateTime.now().add(const Duration(days: 30)),
      validityDays:    json['validity_days'] as int?,
      usageDays:       (json['usage_days'] as List<dynamic>?)
          ?.map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList() ?? [],
      maxPerPerson:    json['max_per_person'] as int?,
      isStackable:     json['is_stackable'] as bool? ?? true,
      reviewNotes:     json['rejection_reason'] as String? ?? json['review_notes'] as String?,
      publishedAt:     json['published_at'] != null
          ? DateTime.parse(json['published_at'] as String)
          : null,
      dealCategoryId:  json['deal_category_id'] as String?,
      applicableMerchantIds: (json['applicable_merchant_ids'] as List<dynamic>?)
          ?.map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
      storeConfirmations: null, // 后端不返回此字段，仅用于创建时传参
      shortName:       json['short_name'] as String?,
      dealType:        json['deal_type'] as String? ?? 'regular',
      dishes:          List<String>.from(json['dishes'] as List? ?? []),
      optionGroups:    _parseOptionGroups(json),
      detailImages:    List<String>.from(json['detail_images'] as List? ?? []),
      // 使用规则列表，DB 返回 text[] 或 null
      usageRules:      (json['usage_rules'] as List<dynamic>?)
          ?.map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList() ?? [],
      // 每账户限购，-1 表示无限制
      maxPerAccount:   json['max_per_account'] as int? ?? -1,
      images:          imagesSorted,
      createdAt:       json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt:       json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
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
        'usage_note_images': usageNoteImages,
        'validity_type':    validityType.value,
        'validity_days':    validityDays,
        'usage_days':       usageDays,
        'max_per_person':   maxPerPerson,
        'is_stackable':     isStackable,
        'deal_category_id': dealCategoryId,
        if (applicableMerchantIds != null)
          'applicable_merchant_ids': applicableMerchantIds,
        if (storeConfirmations != null)
          'store_confirmations': storeConfirmations,
        if (shortName != null)
          'short_name': shortName,
        'deal_type': dealType,
        'dishes': dishes,
        if (optionGroups.isNotEmpty)
          'option_groups': optionGroups.map((g) => g.toJson()).toList(),
        'detail_images': detailImages,
        'usage_rules':   usageRules,
        'max_per_account': maxPerAccount,
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
    List<String>? usageNoteImages,
    ValidityType? validityType,
    DateTime? expiresAt,
    int? validityDays,
    List<String>? usageDays,
    int? maxPerPerson,
    bool? isStackable,
    String? reviewNotes,
    DateTime? publishedAt,
    String? dealCategoryId,
    List<String>? applicableMerchantIds,
    List<Map<String, dynamic>>? storeConfirmations,
    String? shortName,
    String? dealType,
    List<String>? dishes,
    List<DealOptionGroup>? optionGroups,
    List<String>? detailImages,
    List<String>? usageRules,
    int? maxPerAccount,
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
      usageNoteImages: usageNoteImages ?? this.usageNoteImages,
      validityType:    validityType ?? this.validityType,
      expiresAt:       expiresAt ?? this.expiresAt,
      validityDays:    validityDays ?? this.validityDays,
      usageDays:       usageDays ?? this.usageDays,
      maxPerPerson:    maxPerPerson ?? this.maxPerPerson,
      isStackable:     isStackable ?? this.isStackable,
      reviewNotes:     reviewNotes ?? this.reviewNotes,
      publishedAt:     publishedAt ?? this.publishedAt,
      dealCategoryId:  dealCategoryId ?? this.dealCategoryId,
      applicableMerchantIds: applicableMerchantIds ?? this.applicableMerchantIds,
      storeConfirmations: storeConfirmations ?? this.storeConfirmations,
      shortName:       shortName ?? this.shortName,
      dealType:        dealType ?? this.dealType,
      dishes:          dishes ?? this.dishes,
      optionGroups:    optionGroups ?? this.optionGroups,
      detailImages:    detailImages ?? this.detailImages,
      usageRules:      usageRules ?? this.usageRules,
      maxPerAccount:   maxPerAccount ?? this.maxPerAccount,
      images:          images ?? this.images,
      createdAt:       createdAt ?? this.createdAt,
      updatedAt:       updatedAt ?? this.updatedAt,
    );
  }
}
