// 商家工作台数据模型
// 包含: DashboardData, DashboardStats, WeeklyTrendEntry, TodoCounts

// ============================================================
// DashboardStats — 今日核心数据卡片
// ============================================================
class DashboardStats {
  /// 今日订单数
  final int todayOrders;

  /// 今日核销（已使用）券数
  final int todayRedemptions;

  /// 今日收入（美元）
  final double todayRevenue;

  /// 当前待核销券数（未过期、未使用）
  final int pendingCoupons;

  /// 商家 ID
  final String merchantId;

  /// 门店展示名称
  final String merchantName;

  /// 门店是否在线（is_online）
  final bool isOnline;

  /// 商家审核状态（pending / approved / rejected）
  final String merchantStatus;

  const DashboardStats({
    required this.todayOrders,
    required this.todayRedemptions,
    required this.todayRevenue,
    required this.pendingCoupons,
    required this.merchantId,
    required this.merchantName,
    required this.isOnline,
    required this.merchantStatus,
  });

  /// 从 Edge Function JSON 响应构造
  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? {};
    return DashboardStats(
      merchantId: json['merchantId'] as String? ?? '',
      merchantName: json['merchantName'] as String? ?? 'My Store',
      isOnline: json['isOnline'] as bool? ?? true,
      merchantStatus: json['merchantStatus'] as String? ?? 'pending',
      todayOrders: (stats['todayOrders'] as num?)?.toInt() ?? 0,
      todayRedemptions: (stats['todayRedemptions'] as num?)?.toInt() ?? 0,
      todayRevenue: (stats['todayRevenue'] as num?)?.toDouble() ?? 0.0,
      pendingCoupons: (stats['pendingCoupons'] as num?)?.toInt() ?? 0,
    );
  }

  /// 复制并替换部分字段（用于乐观更新）
  DashboardStats copyWith({bool? isOnline}) {
    return DashboardStats(
      todayOrders: todayOrders,
      todayRedemptions: todayRedemptions,
      todayRevenue: todayRevenue,
      pendingCoupons: pendingCoupons,
      merchantId: merchantId,
      merchantName: merchantName,
      isOnline: isOnline ?? this.isOnline,
      merchantStatus: merchantStatus,
    );
  }
}

// ============================================================
// WeeklyTrendEntry — 近 7 天每天数据
// ============================================================
class WeeklyTrendEntry {
  /// 日期（本地时区）
  final DateTime date;

  /// 当天订单数
  final int orders;

  /// 当天收入（美元）
  final double revenue;

  const WeeklyTrendEntry({
    required this.date,
    required this.orders,
    required this.revenue,
  });

  /// 从 Edge Function JSON 解析
  factory WeeklyTrendEntry.fromJson(Map<String, dynamic> json) {
    return WeeklyTrendEntry(
      date: DateTime.parse(json['date'] as String),
      orders: (json['orders'] as num?)?.toInt() ?? 0,
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// 是否是今天
  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

// ============================================================
// TodoCounts — 待办提醒数量
// ============================================================
class TodoCounts {
  /// 待回复评价数
  final int pendingReviews;

  /// 待审核退款数（refund_requested 状态的订单）
  final int pendingRefunds;

  /// Influencer 合作申请数（V1 暂为 0）
  final int influencerRequests;

  const TodoCounts({
    required this.pendingReviews,
    required this.pendingRefunds,
    required this.influencerRequests,
  });

  /// 从 JSON 解析
  factory TodoCounts.fromJson(Map<String, dynamic> json) {
    return TodoCounts(
      pendingReviews: (json['pendingReviews'] as num?)?.toInt() ?? 0,
      pendingRefunds: (json['pendingRefunds'] as num?)?.toInt() ?? 0,
      influencerRequests: (json['influencerRequests'] as num?)?.toInt() ?? 0,
    );
  }

  /// 是否有任何待办（用于控制 Todos 区块是否显示）
  bool get hasAnyTodos =>
      pendingReviews > 0 || pendingRefunds > 0 || influencerRequests > 0;

  /// 待办总数
  int get totalCount => pendingReviews + pendingRefunds + influencerRequests;
}

// ============================================================
// DashboardData — 工作台完整数据（聚合）
// ============================================================
class DashboardData {
  /// 今日核心数据 + 门店信息
  final DashboardStats stats;

  /// 近 7 天趋势（按日期降序，index 0 = 今天）
  final List<WeeklyTrendEntry> weeklyTrend;

  /// 待办提醒
  final TodoCounts todos;

  const DashboardData({
    required this.stats,
    required this.weeklyTrend,
    required this.todos,
  });

  /// 从 Edge Function JSON 完整响应构造
  factory DashboardData.fromJson(Map<String, dynamic> json) {
    // 解析趋势列表
    final trendList = (json['weeklyTrend'] as List<dynamic>? ?? [])
        .map((e) => WeeklyTrendEntry.fromJson(e as Map<String, dynamic>))
        .toList();

    // 解析待办
    final todosJson = json['todos'] as Map<String, dynamic>? ?? {};

    return DashboardData(
      stats: DashboardStats.fromJson(json),
      weeklyTrend: trendList,
      todos: TodoCounts.fromJson(todosJson),
    );
  }

  /// 复制并替换 stats（用于乐观更新 isOnline）
  DashboardData copyWithOnlineStatus(bool isOnline) {
    return DashboardData(
      stats: stats.copyWith(isOnline: isOnline),
      weeklyTrend: weeklyTrend,
      todos: todos,
    );
  }
}

// ============================================================
// V2.1 品牌总览数据模型
// ============================================================

/// 品牌基本信息
class BrandOverviewInfo {
  final String id;
  final String name;
  final String? logoUrl;
  final String? description;

  const BrandOverviewInfo({
    required this.id,
    required this.name,
    this.logoUrl,
    this.description,
  });

  factory BrandOverviewInfo.fromJson(Map<String, dynamic> json) {
    return BrandOverviewInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      logoUrl: json['logoUrl'] as String?,
      description: json['description'] as String?,
    );
  }
}

/// 品牌级汇总统计
class BrandDailyStats {
  final int totalStores;
  final int onlineStores;
  final int todayOrders;
  final int todayRedemptions;
  final double todayRevenue;
  final int pendingCoupons;

  const BrandDailyStats({
    required this.totalStores,
    required this.onlineStores,
    required this.todayOrders,
    required this.todayRedemptions,
    required this.todayRevenue,
    required this.pendingCoupons,
  });

  factory BrandDailyStats.fromJson(Map<String, dynamic> json) {
    return BrandDailyStats(
      totalStores: (json['totalStores'] as num?)?.toInt() ?? 0,
      onlineStores: (json['onlineStores'] as num?)?.toInt() ?? 0,
      todayOrders: (json['todayOrders'] as num?)?.toInt() ?? 0,
      todayRedemptions: (json['todayRedemptions'] as num?)?.toInt() ?? 0,
      todayRevenue: (json['todayRevenue'] as num?)?.toDouble() ?? 0.0,
      pendingCoupons: (json['pendingCoupons'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 品牌总览完整数据（汇总 + 趋势）
class BrandOverviewData {
  final BrandOverviewInfo brand;
  final BrandDailyStats stats;
  final List<WeeklyTrendEntry> weeklyTrend;

  const BrandOverviewData({
    required this.brand,
    required this.stats,
    required this.weeklyTrend,
  });

  factory BrandOverviewData.fromJson(Map<String, dynamic> json) {
    final brandJson = json['brand'] as Map<String, dynamic>? ?? {};
    final statsJson = json['stats'] as Map<String, dynamic>? ?? {};
    final trendList = (json['weeklyTrend'] as List<dynamic>? ?? [])
        .map((e) => WeeklyTrendEntry.fromJson(e as Map<String, dynamic>))
        .toList();

    return BrandOverviewData(
      brand: BrandOverviewInfo.fromJson(brandJson),
      stats: BrandDailyStats.fromJson(statsJson),
      weeklyTrend: trendList,
    );
  }
}

/// 门店排行数据
class StoreRanking {
  final String storeId;
  final String storeName;
  final String storeAddress;
  final bool isOnline;
  final int totalOrders;
  final double totalRevenue;
  final int totalRedeemed;
  final double avgRating;
  final int reviewCount;
  final double refundRate;

  const StoreRanking({
    required this.storeId,
    required this.storeName,
    required this.storeAddress,
    required this.isOnline,
    required this.totalOrders,
    required this.totalRevenue,
    required this.totalRedeemed,
    required this.avgRating,
    required this.reviewCount,
    required this.refundRate,
  });

  factory StoreRanking.fromJson(Map<String, dynamic> json) {
    return StoreRanking(
      storeId: json['storeId'] as String? ?? '',
      storeName: json['storeName'] as String? ?? '',
      storeAddress: json['storeAddress'] as String? ?? '',
      isOnline: json['isOnline'] as bool? ?? false,
      totalOrders: (json['totalOrders'] as num?)?.toInt() ?? 0,
      totalRevenue: (json['totalRevenue'] as num?)?.toDouble() ?? 0.0,
      totalRedeemed: (json['totalRedeemed'] as num?)?.toInt() ?? 0,
      avgRating: (json['avgRating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      refundRate: (json['refundRate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// 门店健康警报
class StoreHealthAlert {
  final String storeId;
  final String storeName;
  final String alertType; // 'high_refund' | 'low_rating' | 'no_orders' | 'offline'
  final String alertMessage;
  final double alertValue;

  const StoreHealthAlert({
    required this.storeId,
    required this.storeName,
    required this.alertType,
    required this.alertMessage,
    required this.alertValue,
  });

  factory StoreHealthAlert.fromJson(Map<String, dynamic> json) {
    return StoreHealthAlert(
      storeId: json['storeId'] as String? ?? '',
      storeName: json['storeName'] as String? ?? '',
      alertType: json['alertType'] as String? ?? '',
      alertMessage: json['alertMessage'] as String? ?? '',
      alertValue: (json['alertValue'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
