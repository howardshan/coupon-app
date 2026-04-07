// 广告计划数据模型
// 对应后端 ad_campaigns 表，包含投放配置、每日/累计统计及质量分数

/// copyWith 用哨兵值，用于区分"未传入"和"传入 null"
const _sentinel = Object();

/// 广告计划状态枚举
enum CampaignStatus {
  active,       // 投放中
  paused,       // 商家暂停
  exhausted,    // 余额耗尽自动暂停
  ended,        // 已结束（超过 endAt）
  adminPaused,  // 管理员强制暂停
}

/// 广告目标类型：推广某个 Deal 或整个门店
enum TargetType {
  deal,   // 推广单个 Deal
  store,  // 推广整个门店
}

/// 广告计划
class AdCampaign {
  final String id;
  final String merchantId;
  final String adAccountId;
  final TargetType targetType;
  final String targetId;         // deal_id 或 merchant_id
  final String placement;        // 投放位置标识符，如 home_deal_top
  final int? categoryId;         // 分类限定（可选）
  final double bidPrice;         // 出价（美元）
  final double dailyBudget;      // 每日预算上限
  final List<int>? scheduleHours; // 投放时段（0-23 小时列表），null 表示全天
  final DateTime startAt;
  final DateTime? endAt;
  final CampaignStatus status;
  final String? adminNote;       // 管理员备注（adminPaused 时说明原因）

  // 今日实时统计
  final double todaySpend;
  final int todayImpressions;
  final int todayClicks;

  // 累计统计
  final double totalSpend;
  final int totalImpressions;
  final int totalClicks;

  // 广告质量分数
  final double qualityScore; // 基础质量分（0-10）
  final double adScore;      // 综合竞价得分（质量 × 出价）

  // splash 广告位专属字段
  final String? creativeUrl;        // 广告素材图片 URL（Supabase Storage）
  final String? splashLinkType;     // 跳转类型: 'deal' | 'merchant' | 'external' | 'none'
  final String? splashLinkValue;    // 跳转目标值（dealId / merchantId / URL）
  final int splashRadiusMeters;     // 投放半径（米），默认 16093 = 10mi

  final DateTime createdAt;
  final DateTime updatedAt;

  const AdCampaign({
    required this.id,
    required this.merchantId,
    required this.adAccountId,
    required this.targetType,
    required this.targetId,
    required this.placement,
    this.categoryId,
    required this.bidPrice,
    required this.dailyBudget,
    this.scheduleHours,
    required this.startAt,
    this.endAt,
    required this.status,
    this.adminNote,
    required this.todaySpend,
    required this.todayImpressions,
    required this.todayClicks,
    required this.totalSpend,
    required this.totalImpressions,
    required this.totalClicks,
    required this.qualityScore,
    required this.adScore,
    this.creativeUrl,
    this.splashLinkType,
    this.splashLinkValue,
    this.splashRadiusMeters = 16093,
    required this.createdAt,
    required this.updatedAt,
  });

  // ----------------------------------------------------------
  // CampaignStatus 字符串转换
  // ----------------------------------------------------------

  /// 从后端字符串解析状态，未知值默认 paused
  static CampaignStatus statusFromString(String? s) {
    switch (s) {
      case 'active':
        return CampaignStatus.active;
      case 'paused':
        return CampaignStatus.paused;
      case 'exhausted':
        return CampaignStatus.exhausted;
      case 'ended':
        return CampaignStatus.ended;
      case 'admin_paused':
        return CampaignStatus.adminPaused;
      default:
        return CampaignStatus.paused;
    }
  }

  /// 状态转换为后端字符串
  static String statusToString(CampaignStatus status) {
    switch (status) {
      case CampaignStatus.active:
        return 'active';
      case CampaignStatus.paused:
        return 'paused';
      case CampaignStatus.exhausted:
        return 'exhausted';
      case CampaignStatus.ended:
        return 'ended';
      case CampaignStatus.adminPaused:
        return 'admin_paused';
    }
  }

  // ----------------------------------------------------------
  // TargetType 字符串转换
  // ----------------------------------------------------------

  static TargetType targetTypeFromString(String? s) {
    switch (s) {
      case 'store':
        return TargetType.store;
      case 'deal':
      default:
        return TargetType.deal;
    }
  }

  static String targetTypeToString(TargetType t) {
    switch (t) {
      case TargetType.deal:
        return 'deal';
      case TargetType.store:
        return 'store';
    }
  }

  // ----------------------------------------------------------
  // placement 显示名称
  // ----------------------------------------------------------

  /// 返回投放位置的用户友好名称
  String get placementDisplayName {
    switch (placement) {
      case 'home_deal_top':
        return 'Home Page Featured';
      case 'home_deal_feed':
        return 'Home Page Feed';
      case 'category_top':
        return 'Category Page Top';
      case 'search_top':
        return 'Search Results Top';
      case 'merchant_nearby':
        return 'Nearby Merchants';
      case 'splash':
        return 'App Splash Screen';
      default:
        // 未知位置：将下划线替换为空格并首字母大写
        return placement
            .split('_')
            .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
            .join(' ');
    }
  }

  // ----------------------------------------------------------
  // CTR 计算属性
  // ----------------------------------------------------------

  /// 今日点击率（百分比）
  double get todayCtr =>
      todayImpressions > 0 ? todayClicks / todayImpressions * 100 : 0.0;

  /// 累计点击率（百分比）
  double get totalCtr =>
      totalImpressions > 0 ? totalClicks / totalImpressions * 100 : 0.0;

  // ----------------------------------------------------------
  // fromJson / copyWith / toCreateJson / toUpdateJson
  // ----------------------------------------------------------

  /// 从 Edge Function 返回的 JSON 构造，所有字段 null-safe
  factory AdCampaign.fromJson(Map<String, dynamic> json) {
    // 解析 scheduleHours：可能是 List<dynamic> 或 null
    List<int>? scheduleHours;
    final rawHours = json['schedule_hours'];
    if (rawHours is List) {
      scheduleHours = rawHours
          .map((e) => (e as num?)?.toInt() ?? 0)
          .toList();
    }

    return AdCampaign(
      id:               json['id'] as String? ?? '',
      merchantId:       json['merchant_id'] as String? ?? '',
      adAccountId:      json['ad_account_id'] as String? ?? '',
      targetType:       targetTypeFromString(json['target_type'] as String?),
      targetId:         json['target_id'] as String? ?? '',
      placement:        json['placement'] as String? ?? '',
      categoryId:       (json['category_id'] as num?)?.toInt(),
      bidPrice:         (json['bid_price'] as num?)?.toDouble() ?? 0.0,
      dailyBudget:      (json['daily_budget'] as num?)?.toDouble() ?? 0.0,
      scheduleHours:    scheduleHours,
      startAt:          json['start_at'] != null
          ? DateTime.parse(json['start_at'] as String)
          : DateTime.now(),
      endAt:            json['end_at'] != null
          ? DateTime.parse(json['end_at'] as String)
          : null,
      status:           statusFromString(json['status'] as String?),
      adminNote:        json['admin_note'] as String?,
      todaySpend:       (json['today_spend'] as num?)?.toDouble() ?? 0.0,
      todayImpressions: (json['today_impressions'] as num?)?.toInt() ?? 0,
      todayClicks:      (json['today_clicks'] as num?)?.toInt() ?? 0,
      totalSpend:       (json['total_spend'] as num?)?.toDouble() ?? 0.0,
      totalImpressions: (json['total_impressions'] as num?)?.toInt() ?? 0,
      totalClicks:      (json['total_clicks'] as num?)?.toInt() ?? 0,
      qualityScore:     (json['quality_score'] as num?)?.toDouble() ?? 0.0,
      adScore:          (json['ad_score'] as num?)?.toDouble() ?? 0.0,
      // splash 专属字段（null-safe）
      creativeUrl:         json['creative_url'] as String?,
      splashLinkType:      json['splash_link_type'] as String?,
      splashLinkValue:     json['splash_link_value'] as String?,
      splashRadiusMeters:  (json['splash_radius_meters'] as num?)?.toInt() ?? 16093,
      createdAt:        json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt:        json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  /// copyWith — 返回修改部分字段后的新实例
  AdCampaign copyWith({
    String? id,
    String? merchantId,
    String? adAccountId,
    TargetType? targetType,
    String? targetId,
    String? placement,
    int? categoryId,
    double? bidPrice,
    double? dailyBudget,
    List<int>? scheduleHours,
    DateTime? startAt,
    DateTime? endAt,
    CampaignStatus? status,
    String? adminNote,
    double? todaySpend,
    int? todayImpressions,
    int? todayClicks,
    double? totalSpend,
    int? totalImpressions,
    int? totalClicks,
    double? qualityScore,
    double? adScore,
    // splash 专属字段（copyWith 时需要支持清空为 null，用 Object? 技巧）
    Object? creativeUrl = _sentinel,
    Object? splashLinkType = _sentinel,
    Object? splashLinkValue = _sentinel,
    int? splashRadiusMeters,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AdCampaign(
      id:               id ?? this.id,
      merchantId:       merchantId ?? this.merchantId,
      adAccountId:      adAccountId ?? this.adAccountId,
      targetType:       targetType ?? this.targetType,
      targetId:         targetId ?? this.targetId,
      placement:        placement ?? this.placement,
      categoryId:       categoryId ?? this.categoryId,
      bidPrice:         bidPrice ?? this.bidPrice,
      dailyBudget:      dailyBudget ?? this.dailyBudget,
      scheduleHours:    scheduleHours ?? this.scheduleHours,
      startAt:          startAt ?? this.startAt,
      endAt:            endAt ?? this.endAt,
      status:           status ?? this.status,
      adminNote:        adminNote ?? this.adminNote,
      todaySpend:       todaySpend ?? this.todaySpend,
      todayImpressions: todayImpressions ?? this.todayImpressions,
      todayClicks:      todayClicks ?? this.todayClicks,
      totalSpend:       totalSpend ?? this.totalSpend,
      totalImpressions: totalImpressions ?? this.totalImpressions,
      totalClicks:      totalClicks ?? this.totalClicks,
      qualityScore:     qualityScore ?? this.qualityScore,
      adScore:          adScore ?? this.adScore,
      creativeUrl:      creativeUrl == _sentinel
          ? this.creativeUrl
          : creativeUrl as String?,
      splashLinkType:   splashLinkType == _sentinel
          ? this.splashLinkType
          : splashLinkType as String?,
      splashLinkValue:  splashLinkValue == _sentinel
          ? this.splashLinkValue
          : splashLinkValue as String?,
      splashRadiusMeters: splashRadiusMeters ?? this.splashRadiusMeters,
      createdAt:        createdAt ?? this.createdAt,
      updatedAt:        updatedAt ?? this.updatedAt,
    );
  }

  /// toCreateJson — 创建新计划时发送给 Edge Function 的字段
  Map<String, dynamic> toCreateJson() {
    final base = <String, dynamic>{
      'target_type':    targetTypeToString(targetType),
      'target_id':      targetId,
      'placement':      placement,
      if (categoryId != null) 'category_id': categoryId,
      'bid_price':      bidPrice,
      'daily_budget':   dailyBudget,
      if (scheduleHours != null) 'schedule_hours': scheduleHours,
      'start_at':       startAt.toIso8601String(),
      if (endAt != null) 'end_at': endAt!.toIso8601String(),
    };
    // splash 广告位额外传入素材与投放配置
    if (placement == 'splash') {
      if (creativeUrl != null) base['creative_url'] = creativeUrl;
      base['splash_link_type'] = splashLinkType ?? 'none';
      base['splash_link_value'] = splashLinkValue;
      base['splash_radius_meters'] = splashRadiusMeters;
    }
    return base;
  }

  /// toUpdateJson — 更新计划时可修改的字段
  Map<String, dynamic> toUpdateJson() {
    final base = <String, dynamic>{
      if (dailyBudget > 0) 'daily_budget': dailyBudget,
      if (scheduleHours != null) 'schedule_hours': scheduleHours,
    };
    // splash 广告位可更新素材与投放配置
    if (placement == 'splash') {
      if (creativeUrl != null) base['creative_url'] = creativeUrl;
      if (splashLinkType != null) base['splash_link_type'] = splashLinkType;
      base['splash_link_value'] = splashLinkValue;
      base['splash_radius_meters'] = splashRadiusMeters;
    }
    return base;
  }
}
