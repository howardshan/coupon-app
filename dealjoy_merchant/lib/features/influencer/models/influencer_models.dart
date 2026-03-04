// ============================================================
// Influencer 合作 — 数据模型
// 模块: 12. Influencer 合作
// 优先级: P2/V2 — 模型定义完整，业务逻辑 V2 实现
// ============================================================

// ============================================================
// 枚举定义
// ============================================================

/// 报酬模式: 固定金额 / 按核销计算 / 按收益分成
enum CompensationType {
  fixed,          // 固定报酬（一次性支付固定金额）
  perRedemption,  // 按核销次数计算（每次核销 × 单价）
  revenueShare,   // 按收益分成（核销总金额 × 比例%）
  ;

  /// 从 JSON 字符串转换
  static CompensationType fromJson(String value) {
    switch (value) {
      case 'fixed':
        return CompensationType.fixed;
      case 'per_redemption':
        return CompensationType.perRedemption;
      case 'revenue_share':
        return CompensationType.revenueShare;
      default:
        return CompensationType.fixed;
    }
  }

  /// 转为 JSON 字符串（与数据库字段一致）
  String toJson() {
    switch (this) {
      case CompensationType.fixed:
        return 'fixed';
      case CompensationType.perRedemption:
        return 'per_redemption';
      case CompensationType.revenueShare:
        return 'revenue_share';
    }
  }

  /// UI 展示文案
  String get displayName {
    switch (this) {
      case CompensationType.fixed:
        return 'Fixed Fee';
      case CompensationType.perRedemption:
        return 'Per Redemption';
      case CompensationType.revenueShare:
        return 'Revenue Share';
    }
  }
}

/// Campaign 状态: 草稿 / 进行中 / 已完成
enum CampaignStatus {
  draft,     // 草稿，未发布
  active,    // 正在进行
  completed, // 已完成
  ;

  /// 从 JSON 字符串转换
  static CampaignStatus fromJson(String value) {
    switch (value) {
      case 'draft':
        return CampaignStatus.draft;
      case 'active':
        return CampaignStatus.active;
      case 'completed':
        return CampaignStatus.completed;
      default:
        return CampaignStatus.draft;
    }
  }

  /// 转为 JSON 字符串
  String toJson() => name;

  /// UI 展示文案
  String get displayName {
    switch (this) {
      case CampaignStatus.draft:
        return 'Draft';
      case CampaignStatus.active:
        return 'Active';
      case CampaignStatus.completed:
        return 'Completed';
    }
  }
}

/// 申请状态: 待审批 / 已通过 / 已拒绝
enum ApplicationStatus {
  pending,   // 待审批
  approved,  // 审批通过
  rejected,  // 已拒绝
  ;

  /// 从 JSON 字符串转换
  static ApplicationStatus fromJson(String value) {
    switch (value) {
      case 'pending':
        return ApplicationStatus.pending;
      case 'approved':
        return ApplicationStatus.approved;
      case 'rejected':
        return ApplicationStatus.rejected;
      default:
        return ApplicationStatus.pending;
    }
  }

  /// 转为 JSON 字符串
  String toJson() => name;

  /// UI 展示文案
  String get displayName {
    switch (this) {
      case ApplicationStatus.pending:
        return 'Pending';
      case ApplicationStatus.approved:
        return 'Approved';
      case ApplicationStatus.rejected:
        return 'Rejected';
    }
  }
}

/// 结算状态: 待结算 / 已打款
enum SettlementStatus {
  pending, // 待结算
  paid,    // 已打款
  ;

  /// 从 JSON 字符串转换
  static SettlementStatus fromJson(String value) {
    switch (value) {
      case 'pending':
        return SettlementStatus.pending;
      case 'paid':
        return SettlementStatus.paid;
      default:
        return SettlementStatus.pending;
    }
  }

  /// 转为 JSON 字符串
  String toJson() => name;

  /// UI 展示文案
  String get displayName {
    switch (this) {
      case SettlementStatus.pending:
        return 'Pending';
      case SettlementStatus.paid:
        return 'Paid';
    }
  }
}

// ============================================================
// InfluencerCampaign — 推广任务模型
// 对应数据库表: influencer_campaigns
// ============================================================
class InfluencerCampaign {
  const InfluencerCampaign({
    required this.id,
    required this.merchantId,
    this.dealId,
    required this.title,
    this.requirements,
    required this.compensationType,
    required this.compensationAmount,
    required this.budget,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String merchantId;
  final String? dealId;           // 关联 Deal（可选）
  final String title;
  final String? requirements;     // 推广要求描述
  final CompensationType compensationType;
  final double compensationAmount; // 报酬金额或百分比
  final double budget;             // 总预算上限（USD）
  final CampaignStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 从 Supabase JSON 构建模型
  factory InfluencerCampaign.fromJson(Map<String, dynamic> json) {
    return InfluencerCampaign(
      id: json['id'] as String,
      merchantId: json['merchant_id'] as String,
      dealId: json['deal_id'] as String?,
      title: json['title'] as String,
      requirements: json['requirements'] as String?,
      compensationType: CompensationType.fromJson(
        json['compensation_type'] as String,
      ),
      compensationAmount: (json['compensation_amount'] as num).toDouble(),
      budget: (json['budget'] as num).toDouble(),
      status: CampaignStatus.fromJson(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// 转为 Supabase 写入 JSON（不包含自动字段）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'merchant_id': merchantId,
      if (dealId != null) 'deal_id': dealId,
      'title': title,
      if (requirements != null) 'requirements': requirements,
      'compensation_type': compensationType.toJson(),
      'compensation_amount': compensationAmount,
      'budget': budget,
      'status': status.toJson(),
    };
  }

  /// 创建副本（部分字段更新）
  InfluencerCampaign copyWith({
    String? id,
    String? merchantId,
    String? dealId,
    String? title,
    String? requirements,
    CompensationType? compensationType,
    double? compensationAmount,
    double? budget,
    CampaignStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InfluencerCampaign(
      id: id ?? this.id,
      merchantId: merchantId ?? this.merchantId,
      dealId: dealId ?? this.dealId,
      title: title ?? this.title,
      requirements: requirements ?? this.requirements,
      compensationType: compensationType ?? this.compensationType,
      compensationAmount: compensationAmount ?? this.compensationAmount,
      budget: budget ?? this.budget,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InfluencerCampaign &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'InfluencerCampaign(id: $id, title: $title, status: ${status.name})';
}

// ============================================================
// InfluencerApplication — 达人申请模型
// 对应数据库表: influencer_applications
// ============================================================
class InfluencerApplication {
  const InfluencerApplication({
    required this.id,
    required this.campaignId,
    required this.influencerUserId,
    required this.status,
    this.promoLink,
    this.rejectionReason,
    required this.appliedAt,
    this.reviewedAt,
  });

  final String id;
  final String campaignId;
  final String influencerUserId; // 达人的 auth user id
  final ApplicationStatus status;
  final String? promoLink;       // 审批通过后生成的专属推广链接
  final String? rejectionReason; // 拒绝原因（可选）
  final DateTime appliedAt;
  final DateTime? reviewedAt;   // 审批时间

  /// 从 Supabase JSON 构建模型
  factory InfluencerApplication.fromJson(Map<String, dynamic> json) {
    return InfluencerApplication(
      id: json['id'] as String,
      campaignId: json['campaign_id'] as String,
      influencerUserId: json['influencer_user_id'] as String,
      status: ApplicationStatus.fromJson(json['status'] as String),
      promoLink: json['promo_link'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      appliedAt: DateTime.parse(json['applied_at'] as String),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
    );
  }

  /// 转为 Supabase 写入 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'campaign_id': campaignId,
      'influencer_user_id': influencerUserId,
      'status': status.toJson(),
      if (promoLink != null) 'promo_link': promoLink,
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
    };
  }

  /// 创建副本（部分字段更新）
  InfluencerApplication copyWith({
    String? id,
    String? campaignId,
    String? influencerUserId,
    ApplicationStatus? status,
    String? promoLink,
    String? rejectionReason,
    DateTime? appliedAt,
    DateTime? reviewedAt,
  }) {
    return InfluencerApplication(
      id: id ?? this.id,
      campaignId: campaignId ?? this.campaignId,
      influencerUserId: influencerUserId ?? this.influencerUserId,
      status: status ?? this.status,
      promoLink: promoLink ?? this.promoLink,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      appliedAt: appliedAt ?? this.appliedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InfluencerApplication &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'InfluencerApplication(id: $id, campaignId: $campaignId, status: ${status.name})';
}

// ============================================================
// InfluencerPerformance — 效果追踪与佣金结算模型
// 对应数据库表: influencer_performance
// ============================================================
class InfluencerPerformance {
  const InfluencerPerformance({
    required this.id,
    required this.campaignId,
    required this.influencerUserId,
    required this.clicks,
    required this.purchases,
    required this.redemptions,
    required this.commissionAmount,
    required this.settlementStatus,
    this.paidAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String campaignId;
  final String influencerUserId;
  final int clicks;             // 推广链接点击次数
  final int purchases;          // 带来的购买次数
  final int redemptions;        // 带来的核销次数
  final double commissionAmount; // 应付佣金（USD），系统自动计算
  final SettlementStatus settlementStatus;
  final DateTime? paidAt;       // 打款时间
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 计算转化率（购买 / 点击），点击为 0 时返回 0.0
  double get conversionRate =>
      clicks > 0 ? purchases / clicks : 0.0;

  /// 计算核销率（核销 / 购买），购买为 0 时返回 0.0
  double get redemptionRate =>
      purchases > 0 ? redemptions / purchases : 0.0;

  /// 从 Supabase JSON 构建模型
  factory InfluencerPerformance.fromJson(Map<String, dynamic> json) {
    return InfluencerPerformance(
      id: json['id'] as String,
      campaignId: json['campaign_id'] as String,
      influencerUserId: json['influencer_user_id'] as String,
      clicks: (json['clicks'] as num).toInt(),
      purchases: (json['purchases'] as num).toInt(),
      redemptions: (json['redemptions'] as num).toInt(),
      commissionAmount: (json['commission_amount'] as num).toDouble(),
      settlementStatus: SettlementStatus.fromJson(
        json['settlement_status'] as String,
      ),
      paidAt: json['paid_at'] != null
          ? DateTime.parse(json['paid_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// 转为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'campaign_id': campaignId,
      'influencer_user_id': influencerUserId,
      'clicks': clicks,
      'purchases': purchases,
      'redemptions': redemptions,
      'commission_amount': commissionAmount,
      'settlement_status': settlementStatus.toJson(),
      if (paidAt != null) 'paid_at': paidAt!.toIso8601String(),
    };
  }

  /// 创建副本（部分字段更新）
  InfluencerPerformance copyWith({
    String? id,
    String? campaignId,
    String? influencerUserId,
    int? clicks,
    int? purchases,
    int? redemptions,
    double? commissionAmount,
    SettlementStatus? settlementStatus,
    DateTime? paidAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InfluencerPerformance(
      id: id ?? this.id,
      campaignId: campaignId ?? this.campaignId,
      influencerUserId: influencerUserId ?? this.influencerUserId,
      clicks: clicks ?? this.clicks,
      purchases: purchases ?? this.purchases,
      redemptions: redemptions ?? this.redemptions,
      commissionAmount: commissionAmount ?? this.commissionAmount,
      settlementStatus: settlementStatus ?? this.settlementStatus,
      paidAt: paidAt ?? this.paidAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InfluencerPerformance &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'InfluencerPerformance(id: $id, campaignId: $campaignId, clicks: $clicks, commissionAmount: $commissionAmount)';
}
