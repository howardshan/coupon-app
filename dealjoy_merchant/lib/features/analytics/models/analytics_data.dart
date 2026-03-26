// =============================================================
// 数据分析模块数据模型
// 包含:
//   - OverviewStats   — 经营概览指标
//   - DealFunnelData  — 单个 Deal 转化漏斗数据
//   - CustomerAnalysis — 客群新老分析数据
// =============================================================

// =============================================================
// OverviewStats — 经营概览指标
// 对应 Edge Function 响应: GET /merchant-analytics/overview
// =============================================================
class OverviewStats {
  /// 浏览量（deal_views 表）
  final int viewsCount;

  /// 下单量（非退款订单）
  final int ordersCount;

  /// 核销量（coupon status='used'）
  final int redemptionsCount;

  /// 总收入（向后兼容）
  final double revenue;

  /// 已核销收入
  final double redeemRevenue;

  /// 未核销收入（pending）
  final double pendingRevenue;

  /// 已结算收入（paid）
  final double paidRevenue;

  /// 当前查询的时间范围（天）
  final int daysRange;

  const OverviewStats({
    required this.viewsCount,
    required this.ordersCount,
    required this.redemptionsCount,
    required this.revenue,
    this.redeemRevenue = 0.0,
    this.pendingRevenue = 0.0,
    this.paidRevenue = 0.0,
    required this.daysRange,
  });

  /// 从 Edge Function 响应 JSON 创建
  factory OverviewStats.fromJson(Map<String, dynamic> json) {
    return OverviewStats(
      viewsCount:       (json['views_count']       as num?)?.toInt()    ?? 0,
      ordersCount:      (json['orders_count']      as num?)?.toInt()    ?? 0,
      redemptionsCount: (json['redemptions_count'] as num?)?.toInt()    ?? 0,
      revenue:          (json['revenue']           as num?)?.toDouble() ?? 0.0,
      redeemRevenue:    (json['redeem_revenue']    as num?)?.toDouble() ?? 0.0,
      pendingRevenue:   (json['pending_revenue']   as num?)?.toDouble() ?? 0.0,
      paidRevenue:      (json['paid_revenue']      as num?)?.toDouble() ?? 0.0,
      daysRange:        (json['days_range']        as num?)?.toInt()    ?? 7,
    );
  }

  /// 空数据（无指标时的默认值）
  factory OverviewStats.empty({int daysRange = 7}) {
    return OverviewStats(
      viewsCount:       0,
      ordersCount:      0,
      redemptionsCount: 0,
      revenue:          0.0,
      redeemRevenue:    0.0,
      pendingRevenue:   0.0,
      paidRevenue:      0.0,
      daysRange:        daysRange,
    );
  }

  @override
  String toString() =>
      'OverviewStats(views=$viewsCount, orders=$ordersCount, '
      'redemptions=$redemptionsCount, revenue=$revenue, days=$daysRange)';
}

// =============================================================
// DealFunnelData — 单个 Deal 的转化漏斗数据
// 对应 Edge Function 响应: GET /merchant-analytics/deal-funnel
// =============================================================
class DealFunnelData {
  /// Deal UUID
  final String dealId;

  /// Deal 标题
  final String dealTitle;

  /// 浏览量
  final int views;

  /// 下单量（非退款）
  final int orders;

  /// 核销量
  final int redemptions;

  /// 浏览→下单转化率（百分比，如 12.5 表示 12.5%）
  final double viewToOrderRate;

  /// 下单→核销转化率
  final double orderToRedemptionRate;

  const DealFunnelData({
    required this.dealId,
    required this.dealTitle,
    required this.views,
    required this.orders,
    required this.redemptions,
    required this.viewToOrderRate,
    required this.orderToRedemptionRate,
  });

  /// 从 JSON 创建
  factory DealFunnelData.fromJson(Map<String, dynamic> json) {
    return DealFunnelData(
      dealId:                  json['deal_id']                  as String? ?? '',
      dealTitle:               json['deal_title']               as String? ?? 'Unknown Deal',
      views:                   (json['views']                   as num?)?.toInt()    ?? 0,
      orders:                  (json['orders']                  as num?)?.toInt()    ?? 0,
      redemptions:             (json['redemptions']             as num?)?.toInt()    ?? 0,
      viewToOrderRate:         (json['view_to_order_rate']      as num?)?.toDouble() ?? 0.0,
      orderToRedemptionRate:   (json['order_to_redemption_rate']as num?)?.toDouble() ?? 0.0,
    );
  }

  /// 将 views 作为基准（100%），计算 orders 和 redemptions 的相对宽度比例
  /// 用于漏斗条渲染，值域 0.0 ~ 1.0
  double get ordersFraction =>
      views > 0 ? (orders / views).clamp(0.0, 1.0) : 0.0;

  double get redemptionsFraction =>
      views > 0 ? (redemptions / views).clamp(0.0, 1.0) : 0.0;

  @override
  String toString() =>
      'DealFunnelData(title=$dealTitle, views=$views, orders=$orders, redemptions=$redemptions)';
}

// =============================================================
// CustomerAnalysis — 客群新老分析
// 对应 Edge Function 响应: GET /merchant-analytics/customers
// =============================================================
class CustomerAnalysis {
  /// 新客数量（只在该商家下过 1 笔订单的用户）
  final int newCustomersCount;

  /// 老客数量（在该商家下过 ≥2 笔订单的用户）
  final int returningCustomersCount;

  /// 复购率（老客占有效购买用户的百分比，如 35.2 表示 35.2%）
  final double repeatRate;

  const CustomerAnalysis({
    required this.newCustomersCount,
    required this.returningCustomersCount,
    required this.repeatRate,
  });

  /// 从 JSON 创建
  factory CustomerAnalysis.fromJson(Map<String, dynamic> json) {
    return CustomerAnalysis(
      newCustomersCount:       (json['new_customers_count']       as num?)?.toInt()    ?? 0,
      returningCustomersCount: (json['returning_customers_count'] as num?)?.toInt()    ?? 0,
      repeatRate:              (json['repeat_rate']               as num?)?.toDouble() ?? 0.0,
    );
  }

  /// 空数据（无客户时的默认值）
  factory CustomerAnalysis.empty() {
    return const CustomerAnalysis(
      newCustomersCount:       0,
      returningCustomersCount: 0,
      repeatRate:              0.0,
    );
  }

  /// 总有效购买用户数
  int get totalCustomers => newCustomersCount + returningCustomersCount;

  /// 新客占比（0.0 ~ 1.0），用于饼图渲染
  double get newCustomersFraction =>
      totalCustomers > 0 ? newCustomersCount / totalCustomers : 0.0;

  /// 老客占比（0.0 ~ 1.0）
  double get returningCustomersFraction =>
      totalCustomers > 0 ? returningCustomersCount / totalCustomers : 0.0;

  @override
  String toString() =>
      'CustomerAnalysis(new=$newCustomersCount, returning=$returningCustomersCount, repeatRate=$repeatRate%)';
}
