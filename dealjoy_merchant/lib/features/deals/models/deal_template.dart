// V2.2 Deal 模板数据模型
// 用于品牌级一键多店发布

class DealTemplate {
  final String id;
  final String brandId;
  final String createdBy;
  final String title;
  final String description;
  final String category;
  final double originalPrice;
  final double discountPrice;
  final String discountLabel;
  final int stockLimit;
  final String packageContents;
  final String usageNotes;
  final List<String> usageDays;
  final int? maxPerPerson;
  final bool isStackable;
  final String validityType;
  final int? validityDays;
  final String refundPolicy;
  final List<String> imageUrls;
  final String dealType;
  final String? badgeText;
  final String? dealCategoryId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  // 关联门店信息
  final List<TemplateStoreLink> linkedStores;

  const DealTemplate({
    required this.id,
    required this.brandId,
    required this.createdBy,
    required this.title,
    this.description = '',
    this.category = '',
    this.originalPrice = 0,
    this.discountPrice = 0,
    this.discountLabel = '',
    this.stockLimit = 100,
    this.packageContents = '',
    this.usageNotes = '',
    this.usageDays = const [],
    this.maxPerPerson,
    this.isStackable = true,
    this.validityType = 'fixed_date',
    this.validityDays,
    this.refundPolicy = 'Refund anytime before use, refund when expired',
    this.imageUrls = const [],
    this.dealType = 'regular',
    this.badgeText,
    this.dealCategoryId,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.linkedStores = const [],
  });

  /// 已发布门店数量
  int get publishedStoreCount => linkedStores.length;

  /// 已自定义门店数量
  int get customizedStoreCount =>
      linkedStores.where((s) => s.isCustomized).length;

  factory DealTemplate.fromJson(Map<String, dynamic> json) {
    // 解析关联门店
    final storesJson = json['deal_template_stores'] as List<dynamic>? ?? [];
    final stores = storesJson
        .map((e) => TemplateStoreLink.fromJson(e as Map<String, dynamic>))
        .toList();

    return DealTemplate(
      id: json['id'] as String? ?? '',
      brandId: json['brand_id'] as String? ?? '',
      createdBy: json['created_by'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? '',
      originalPrice: (json['original_price'] as num?)?.toDouble() ?? 0,
      discountPrice: (json['discount_price'] as num?)?.toDouble() ?? 0,
      discountLabel: json['discount_label'] as String? ?? '',
      stockLimit: (json['stock_limit'] as num?)?.toInt() ?? 100,
      packageContents: json['package_contents'] as String? ?? '',
      usageNotes: json['usage_notes'] as String? ?? '',
      usageDays: (json['usage_days'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      maxPerPerson: (json['max_per_person'] as num?)?.toInt(),
      isStackable: json['is_stackable'] as bool? ?? true,
      validityType: json['validity_type'] as String? ?? 'fixed_date',
      validityDays: (json['validity_days'] as num?)?.toInt(),
      refundPolicy: json['refund_policy'] as String? ??
          'Refund anytime before use, refund when expired',
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      dealType: json['deal_type'] as String? ?? 'regular',
      badgeText: json['badge_text'] as String?,
      dealCategoryId: json['deal_category_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      linkedStores: stores,
    );
  }

  /// 转为 JSON（创建/更新时发送给 Edge Function）
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'category': category,
      'original_price': originalPrice,
      'discount_price': discountPrice,
      'discount_label': discountLabel,
      'stock_limit': stockLimit,
      'package_contents': packageContents,
      'usage_notes': usageNotes,
      'usage_days': usageDays,
      if (maxPerPerson != null) 'max_per_person': maxPerPerson,
      'is_stackable': isStackable,
      'validity_type': validityType,
      if (validityDays != null) 'validity_days': validityDays,
      'refund_policy': refundPolicy,
      'image_urls': imageUrls,
      'deal_type': dealType,
      if (badgeText != null) 'badge_text': badgeText,
      if (dealCategoryId != null) 'deal_category_id': dealCategoryId,
    };
  }
}

/// 模板-门店关联
class TemplateStoreLink {
  final String id;
  final String merchantId;
  final String? dealId;
  final bool isCustomized;

  const TemplateStoreLink({
    required this.id,
    required this.merchantId,
    this.dealId,
    this.isCustomized = false,
  });

  factory TemplateStoreLink.fromJson(Map<String, dynamic> json) {
    return TemplateStoreLink(
      id: json['id'] as String? ?? '',
      merchantId: json['merchant_id'] as String? ?? '',
      dealId: json['deal_id'] as String?,
      isCustomized: json['is_customized'] as bool? ?? false,
    );
  }
}
