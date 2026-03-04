// 营销工具模块数据模型
// 包含: FlashDeal / NewCustomerOffer / Promotion / PromoType
// 优先级: P2/V2 — 模型结构完整，业务逻辑在 V2 实现

/// 促销活动类型枚举
/// V2 预留扩展点：buy_x_get_y, free_item 等
enum PromoType {
  spendXGetY('spend_x_get_y');

  const PromoType(this.value);

  /// 数据库存储值
  final String value;

  /// 从数据库值解析枚举
  static PromoType fromValue(String value) {
    return PromoType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => PromoType.spendXGetY,
    );
  }

  /// 用户可读的展示名称
  String get displayName {
    switch (this) {
      case PromoType.spendXGetY:
        return 'Spend X Get Y';
    }
  }
}

/// 限时折扣（Flash Deal）模型
/// 商家为指定 Deal 设置限时额外折扣，到期自动结束
class FlashDeal {
  const FlashDeal({
    required this.id,
    required this.dealId,
    required this.merchantId,
    required this.discountPercentage,
    required this.startTime,
    required this.endTime,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// 关联的 Deal ID
  final String dealId;

  /// 所属商家 ID
  final String merchantId;

  /// 额外折扣百分比，范围 1-99
  /// 例如：10 表示在 Deal 原价基础上再减 10%
  final double discountPercentage;

  /// 活动开始时间
  final DateTime startTime;

  /// 活动结束时间
  final DateTime endTime;

  /// 是否生效（过期后由 pg_cron 自动置 false）
  final bool isActive;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 活动是否当前有效（本地计算，辅助 UI 展示）
  bool get isCurrentlyActive =>
      isActive &&
      DateTime.now().isAfter(startTime) &&
      DateTime.now().isBefore(endTime);

  /// 从 JSON 构建（对应 Supabase 返回格式）
  factory FlashDeal.fromJson(Map<String, dynamic> json) {
    return FlashDeal(
      id: json['id'] as String,
      dealId: json['deal_id'] as String,
      merchantId: json['merchant_id'] as String,
      discountPercentage: (json['discount_percentage'] as num).toDouble(),
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// 转换为 JSON（用于插入/更新 Supabase）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deal_id': dealId,
      'merchant_id': merchantId,
      'discount_percentage': discountPercentage,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// 不可变更新（V2 使用）
  FlashDeal copyWith({
    String? id,
    String? dealId,
    String? merchantId,
    double? discountPercentage,
    DateTime? startTime,
    DateTime? endTime,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FlashDeal(
      id: id ?? this.id,
      dealId: dealId ?? this.dealId,
      merchantId: merchantId ?? this.merchantId,
      discountPercentage: discountPercentage ?? this.discountPercentage,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'FlashDeal(id: $id, dealId: $dealId, discount: $discountPercentage%, active: $isActive)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlashDeal &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 新客特惠（New Customer Offer）模型
/// 仅对首次购买的新用户可见的特别优惠价格
class NewCustomerOffer {
  const NewCustomerOffer({
    required this.id,
    required this.dealId,
    required this.merchantId,
    required this.specialPrice,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// 关联的 Deal ID
  final String dealId;

  /// 所属商家 ID
  final String merchantId;

  /// 新客特惠价格（USD），必须低于 Deal 原价
  final double specialPrice;

  /// 是否启用
  final bool isActive;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 从 JSON 构建（对应 Supabase 返回格式）
  factory NewCustomerOffer.fromJson(Map<String, dynamic> json) {
    return NewCustomerOffer(
      id: json['id'] as String,
      dealId: json['deal_id'] as String,
      merchantId: json['merchant_id'] as String,
      specialPrice: (json['special_price'] as num).toDouble(),
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// 转换为 JSON（用于插入/更新 Supabase）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deal_id': dealId,
      'merchant_id': merchantId,
      'special_price': specialPrice,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// 不可变更新（V2 使用）
  NewCustomerOffer copyWith({
    String? id,
    String? dealId,
    String? merchantId,
    double? specialPrice,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NewCustomerOffer(
      id: id ?? this.id,
      dealId: dealId ?? this.dealId,
      merchantId: merchantId ?? this.merchantId,
      specialPrice: specialPrice ?? this.specialPrice,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'NewCustomerOffer(id: $id, dealId: $dealId, price: \$$specialPrice, active: $isActive)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NewCustomerOffer &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 满减活动（Promotion）模型
/// 满 X 减 Y 活动，支持绑定特定 Deal 或全店通用
class Promotion {
  const Promotion({
    required this.id,
    required this.merchantId,
    this.dealId,
    required this.promoType,
    required this.minSpend,
    required this.discountAmount,
    required this.isActive,
    this.startTime,
    this.endTime,
    this.title,
    this.description,
    this.usageLimit,
    this.perUserLimit,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// 所属商家 ID
  final String merchantId;

  /// 关联特定 Deal（为 null 表示全店通用）
  final String? dealId;

  /// 活动类型（当前仅支持 spendXGetY）
  final PromoType promoType;

  /// 最低消费金额（USD）
  final double minSpend;

  /// 满足条件后减免金额（USD），必须 < minSpend
  final double discountAmount;

  /// 是否启用
  final bool isActive;

  /// 活动开始时间（null 表示立即生效）
  final DateTime? startTime;

  /// 活动结束时间（null 表示无截止期）
  final DateTime? endTime;

  /// 活动标题，如 "Spend $30 Get $5 Off"
  final String? title;

  /// 活动说明
  final String? description;

  /// V2 预留：总使用次数上限（null 表示不限）
  final int? usageLimit;

  /// V2 预留：每用户使用次数上限（null 表示不限）
  final int? perUserLimit;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 活动是否当前有效（本地计算，辅助 UI 展示）
  bool get isCurrentlyActive {
    if (!isActive) return false;
    final now = DateTime.now();
    if (startTime != null && now.isBefore(startTime!)) return false;
    if (endTime != null && now.isAfter(endTime!)) return false;
    return true;
  }

  /// 自动生成的展示标题（若 title 字段为空时使用）
  String get displayTitle {
    if (title != null && title!.isNotEmpty) return title!;
    return 'Spend \$${minSpend.toStringAsFixed(0)} Get \$${discountAmount.toStringAsFixed(0)} Off';
  }

  /// 全店通用（dealId 为 null）
  bool get isStoreWide => dealId == null;

  /// 从 JSON 构建（对应 Supabase 返回格式）
  factory Promotion.fromJson(Map<String, dynamic> json) {
    return Promotion(
      id: json['id'] as String,
      merchantId: json['merchant_id'] as String,
      dealId: json['deal_id'] as String?,
      promoType: PromoType.fromValue(json['promo_type'] as String? ?? 'spend_x_get_y'),
      minSpend: (json['min_spend'] as num).toDouble(),
      discountAmount: (json['discount_amount'] as num).toDouble(),
      isActive: json['is_active'] as bool,
      startTime: json['start_time'] != null
          ? DateTime.parse(json['start_time'] as String)
          : null,
      endTime: json['end_time'] != null
          ? DateTime.parse(json['end_time'] as String)
          : null,
      title: json['title'] as String?,
      description: json['description'] as String?,
      usageLimit: json['usage_limit'] as int?,
      perUserLimit: json['per_user_limit'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// 转换为 JSON（用于插入/更新 Supabase）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'merchant_id': merchantId,
      'deal_id': dealId,
      'promo_type': promoType.value,
      'min_spend': minSpend,
      'discount_amount': discountAmount,
      'is_active': isActive,
      'start_time': startTime?.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'title': title,
      'description': description,
      'usage_limit': usageLimit,
      'per_user_limit': perUserLimit,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// 不可变更新（V2 使用）
  Promotion copyWith({
    String? id,
    String? merchantId,
    String? dealId,
    PromoType? promoType,
    double? minSpend,
    double? discountAmount,
    bool? isActive,
    DateTime? startTime,
    DateTime? endTime,
    String? title,
    String? description,
    int? usageLimit,
    int? perUserLimit,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Promotion(
      id: id ?? this.id,
      merchantId: merchantId ?? this.merchantId,
      dealId: dealId ?? this.dealId,
      promoType: promoType ?? this.promoType,
      minSpend: minSpend ?? this.minSpend,
      discountAmount: discountAmount ?? this.discountAmount,
      isActive: isActive ?? this.isActive,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      title: title ?? this.title,
      description: description ?? this.description,
      usageLimit: usageLimit ?? this.usageLimit,
      perUserLimit: perUserLimit ?? this.perUserLimit,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'Promotion(id: $id, minSpend: \$$minSpend, discount: \$$discountAmount, active: $isActive)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Promotion &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
