// 财务与结算模块数据模型
// 包含: EarningsSummary, EarningsTransaction, SettlementSchedule,
//       ReportRow, ReportData, PagedTransactions, TransactionTotals

/// 平台手续费率（15%）
const double kPlatformFeeRate = 0.15;

/// 商家实收比例（85%）
const double kMerchantNetRate = 0.85;

// =============================================================
// EarningsSummary — 收入概览（月度汇总）
// =============================================================
class EarningsSummary {
  final String month;          // 格式: 2026-03
  final double totalRevenue;        // 本月总收入（含手续费）
  final double pendingSettlement;   // 待结算金额（商家实收85%）
  final double settledAmount;       // 已结算金额
  final double refundedAmount;      // 退款金额

  const EarningsSummary({
    required this.month,
    required this.totalRevenue,
    required this.pendingSettlement,
    required this.settledAmount,
    required this.refundedAmount,
  });

  /// 从 Edge Function JSON 解析
  factory EarningsSummary.fromJson(Map<String, dynamic> json) {
    return EarningsSummary(
      month:             json['month'] as String? ?? '',
      totalRevenue:      (json['total_revenue'] as num?)?.toDouble() ?? 0.0,
      pendingSettlement: (json['pending_settlement'] as num?)?.toDouble() ?? 0.0,
      settledAmount:     (json['settled_amount'] as num?)?.toDouble() ?? 0.0,
      refundedAmount:    (json['refunded_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// 空值（加载前的默认状态）
  factory EarningsSummary.empty(String month) {
    return EarningsSummary(
      month:             month,
      totalRevenue:      0.0,
      pendingSettlement: 0.0,
      settledAmount:     0.0,
      refundedAmount:    0.0,
    );
  }

  EarningsSummary copyWith({
    String? month,
    double? totalRevenue,
    double? pendingSettlement,
    double? settledAmount,
    double? refundedAmount,
  }) {
    return EarningsSummary(
      month:             month             ?? this.month,
      totalRevenue:      totalRevenue      ?? this.totalRevenue,
      pendingSettlement: pendingSettlement ?? this.pendingSettlement,
      settledAmount:     settledAmount     ?? this.settledAmount,
      refundedAmount:    refundedAmount    ?? this.refundedAmount,
    );
  }
}

// =============================================================
// EarningsTransaction — 单笔交易记录
// =============================================================
class EarningsTransaction {
  final String orderId;       // 订单 UUID
  final double amount;        // 原始金额（含平台手续费）
  final double platformFee;   // 平台手续费（15%）
  final double netAmount;     // 商家实收（85%）
  final String status;        // 订单状态原始值
  final DateTime createdAt;   // 下单时间

  const EarningsTransaction({
    required this.orderId,
    required this.amount,
    required this.platformFee,
    required this.netAmount,
    required this.status,
    required this.createdAt,
  });

  /// 从 Edge Function JSON 解析
  factory EarningsTransaction.fromJson(Map<String, dynamic> json) {
    return EarningsTransaction(
      orderId:     json['order_id'] as String? ?? '',
      amount:      (json['amount'] as num?)?.toDouble() ?? 0.0,
      platformFee: (json['platform_fee'] as num?)?.toDouble() ?? 0.0,
      netAmount:   (json['net_amount'] as num?)?.toDouble() ?? 0.0,
      status:      json['status'] as String? ?? 'unknown',
      createdAt:   DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// 显示用状态标签
  String get displayStatus {
    switch (status) {
      case 'unused':
        return 'Pending';
      case 'used':
        return 'Redeemed';
      case 'refunded':
        return 'Refunded';
      case 'refund_requested':
        return 'Refund Requested';
      case 'expired':
        return 'Expired';
      default:
        return status;
    }
  }

  /// 订单号截断显示（前8位）
  String get shortOrderId {
    if (orderId.length > 8) {
      return '#${orderId.replaceAll('-', '').substring(0, 8).toUpperCase()}';
    }
    return '#${orderId.toUpperCase()}';
  }
}

// =============================================================
// TransactionTotals — 交易明细合计行
// =============================================================
class TransactionTotals {
  final double amount;
  final double platformFee;
  final double netAmount;

  const TransactionTotals({
    required this.amount,
    required this.platformFee,
    required this.netAmount,
  });

  factory TransactionTotals.fromJson(Map<String, dynamic> json) {
    return TransactionTotals(
      amount:      (json['amount'] as num?)?.toDouble() ?? 0.0,
      platformFee: (json['platform_fee'] as num?)?.toDouble() ?? 0.0,
      netAmount:   (json['net_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  factory TransactionTotals.zero() {
    return const TransactionTotals(
      amount: 0.0,
      platformFee: 0.0,
      netAmount: 0.0,
    );
  }
}

// =============================================================
// PagedTransactions — 分页交易列表（含合计）
// =============================================================
class PagedTransactions {
  final List<EarningsTransaction> data;
  final int page;
  final int perPage;
  final int total;
  final bool hasMore;
  final TransactionTotals totals;

  const PagedTransactions({
    required this.data,
    required this.page,
    required this.perPage,
    required this.total,
    required this.hasMore,
    required this.totals,
  });

  factory PagedTransactions.fromJson(Map<String, dynamic> json) {
    final rawList = json['data'] as List<dynamic>? ?? [];
    final paginationMap = json['pagination'] as Map<String, dynamic>? ?? {};
    final totalsMap = json['totals'] as Map<String, dynamic>? ?? {};

    return PagedTransactions(
      data: rawList
          .map((item) => EarningsTransaction.fromJson(item as Map<String, dynamic>))
          .toList(),
      page:    (paginationMap['page'] as num?)?.toInt() ?? 1,
      perPage: (paginationMap['per_page'] as num?)?.toInt() ?? 20,
      total:   (paginationMap['total'] as num?)?.toInt() ?? 0,
      hasMore: paginationMap['has_more'] as bool? ?? false,
      totals:  TransactionTotals.fromJson(totalsMap),
    );
  }

  factory PagedTransactions.empty() {
    return PagedTransactions(
      data:    [],
      page:    1,
      perPage: 20,
      total:   0,
      hasMore: false,
      totals:  TransactionTotals.zero(),
    );
  }
}

// =============================================================
// SettlementSchedule — 结算规则与下次打款信息
// =============================================================
class SettlementSchedule {
  final String settlementRule;      // 结算规则说明文案
  final int settlementDays;         // T+N 天数
  final DateTime? nextPayoutDate;   // 下次打款日期（可能为 null）
  final double pendingAmount;       // 待结算金额（商家实收）
  final int pendingOrderCount;      // 待结算订单数

  const SettlementSchedule({
    required this.settlementRule,
    required this.settlementDays,
    this.nextPayoutDate,
    required this.pendingAmount,
    required this.pendingOrderCount,
  });

  factory SettlementSchedule.fromJson(Map<String, dynamic> json) {
    return SettlementSchedule(
      settlementRule:     json['settlement_rule'] as String? ??
          'Redeemed orders are settled T+7 days after redemption',
      settlementDays:     (json['settlement_days'] as num?)?.toInt() ?? 7,
      nextPayoutDate:     json['next_payout_date'] != null
          ? DateTime.tryParse(json['next_payout_date'] as String)
          : null,
      pendingAmount:      (json['pending_amount'] as num?)?.toDouble() ?? 0.0,
      pendingOrderCount:  (json['pending_order_count'] as num?)?.toInt() ?? 0,
    );
  }

  factory SettlementSchedule.defaultSchedule() {
    return const SettlementSchedule(
      settlementRule:    'Redeemed orders are settled T+7 days after redemption via Stripe Connect',
      settlementDays:    7,
      nextPayoutDate:    null,
      pendingAmount:     0.0,
      pendingOrderCount: 0,
    );
  }

  bool get hasPendingSettlement => pendingOrderCount > 0;
}

// =============================================================
// ReportPeriodType — 对账报表周期类型枚举
// =============================================================
enum ReportPeriodType {
  monthly,
  weekly;

  String get label {
    switch (this) {
      case ReportPeriodType.monthly:
        return 'Monthly';
      case ReportPeriodType.weekly:
        return 'Weekly';
    }
  }

  String get apiValue {
    switch (this) {
      case ReportPeriodType.monthly:
        return 'monthly';
      case ReportPeriodType.weekly:
        return 'weekly';
    }
  }
}

// =============================================================
// ReportRow — 对账报表单日数据行
// =============================================================
class ReportRow {
  final DateTime date;
  final int orderCount;
  final double grossAmount;
  final double platformFee;
  final double netAmount;

  const ReportRow({
    required this.date,
    required this.orderCount,
    required this.grossAmount,
    required this.platformFee,
    required this.netAmount,
  });

  factory ReportRow.fromJson(Map<String, dynamic> json) {
    return ReportRow(
      date:         DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      orderCount:   (json['order_count'] as num?)?.toInt() ?? 0,
      grossAmount:  (json['gross_amount'] as num?)?.toDouble() ?? 0.0,
      platformFee:  (json['platform_fee'] as num?)?.toDouble() ?? 0.0,
      netAmount:    (json['net_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// =============================================================
// ReportTotals — 对账报表合计行
// =============================================================
class ReportTotals {
  final int orderCount;
  final double grossAmount;
  final double platformFee;
  final double netAmount;

  const ReportTotals({
    required this.orderCount,
    required this.grossAmount,
    required this.platformFee,
    required this.netAmount,
  });

  factory ReportTotals.fromJson(Map<String, dynamic> json) {
    return ReportTotals(
      orderCount:  (json['order_count'] as num?)?.toInt() ?? 0,
      grossAmount: (json['gross_amount'] as num?)?.toDouble() ?? 0.0,
      platformFee: (json['platform_fee'] as num?)?.toDouble() ?? 0.0,
      netAmount:   (json['net_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  factory ReportTotals.zero() {
    return const ReportTotals(
      orderCount:  0,
      grossAmount: 0.0,
      platformFee: 0.0,
      netAmount:   0.0,
    );
  }
}

// =============================================================
// ReportData — 完整对账报表数据
// =============================================================
class ReportData {
  final ReportPeriodType periodType;
  final DateTime dateFrom;
  final DateTime dateTo;
  final List<ReportRow> rows;
  final ReportTotals totals;

  const ReportData({
    required this.periodType,
    required this.dateFrom,
    required this.dateTo,
    required this.rows,
    required this.totals,
  });

  factory ReportData.fromJson(Map<String, dynamic> json) {
    final periodTypeStr = json['period_type'] as String? ?? 'monthly';
    final periodType = periodTypeStr == 'weekly'
        ? ReportPeriodType.weekly
        : ReportPeriodType.monthly;

    final rawRows = json['rows'] as List<dynamic>? ?? [];
    final totalsMap = json['totals'] as Map<String, dynamic>? ?? {};

    return ReportData(
      periodType: periodType,
      dateFrom:   DateTime.tryParse(json['date_from'] as String? ?? '') ?? DateTime.now(),
      dateTo:     DateTime.tryParse(json['date_to'] as String? ?? '') ?? DateTime.now(),
      rows:       rawRows
          .map((item) => ReportRow.fromJson(item as Map<String, dynamic>))
          .toList(),
      totals: ReportTotals.fromJson(totalsMap),
    );
  }

  factory ReportData.empty(ReportPeriodType type) {
    return ReportData(
      periodType: type,
      dateFrom:   DateTime.now(),
      dateTo:     DateTime.now(),
      rows:       [],
      totals:     ReportTotals.zero(),
    );
  }
}

// =============================================================
// StripeAccountInfo — Stripe Connect 账户信息
// =============================================================
class StripeAccountInfo {
  final bool isConnected;
  final String? accountId;
  final String? accountEmail;
  final String accountStatus; // 'not_connected' | 'connected' | 'restricted'

  const StripeAccountInfo({
    required this.isConnected,
    this.accountId,
    this.accountEmail,
    required this.accountStatus,
  });

  factory StripeAccountInfo.fromJson(Map<String, dynamic> json) {
    return StripeAccountInfo(
      isConnected:   json['is_connected'] as bool? ?? false,
      accountId:     json['account_id'] as String?,
      accountEmail:  json['account_email'] as String?,
      accountStatus: json['account_status'] as String? ?? 'not_connected',
    );
  }

  factory StripeAccountInfo.notConnected() {
    return const StripeAccountInfo(
      isConnected:   false,
      accountId:     null,
      accountEmail:  null,
      accountStatus: 'not_connected',
    );
  }

  /// 账户显示标签（末4位）
  String? get accountDisplayId {
    if (accountId == null || accountId!.isEmpty) return null;
    final clean = accountId!.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (clean.length > 4) {
      return '...${clean.substring(clean.length - 4).toUpperCase()}';
    }
    return accountId;
  }
}

// =============================================================
// TransactionsFilter — 交易明细筛选条件
// =============================================================
class TransactionsFilter {
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int page;

  const TransactionsFilter({
    this.dateFrom,
    this.dateTo,
    this.page = 1,
  });

  TransactionsFilter copyWith({
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearDateFrom = false,
    bool clearDateTo = false,
    int? page,
  }) {
    return TransactionsFilter(
      dateFrom: clearDateFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo:   clearDateTo   ? null : (dateTo   ?? this.dateTo),
      page:     page ?? this.page,
    );
  }

  bool get hasFilter => dateFrom != null || dateTo != null;
}
