// 品牌佣金收益数据模型
// 包含: BrandEarningsSummary, BrandTransaction, BrandBalance,
//       BrandWithdrawalRecord, BrandStripeAccount

// =============================================================
// BrandEarningsSummary — 品牌月度收益汇总
// =============================================================

/// 品牌月度收益概览（按月统计品牌佣金）
class BrandEarningsSummary {
  /// 月份（YYYY-MM 格式）
  final String month;

  /// 品牌佣金总收入（来自所有门店）
  final double totalBrandRevenue;

  /// 待结算金额（已核销未结算）
  final double pendingSettlement;

  /// 已结算金额
  final double settledAmount;

  /// 退款金额
  final double refundedAmount;

  const BrandEarningsSummary({
    required this.month,
    required this.totalBrandRevenue,
    required this.pendingSettlement,
    required this.settledAmount,
    required this.refundedAmount,
  });

  /// 空数据（初始状态）
  factory BrandEarningsSummary.empty(String month) {
    return BrandEarningsSummary(
      month: month,
      totalBrandRevenue: 0.0,
      pendingSettlement: 0.0,
      settledAmount: 0.0,
      refundedAmount: 0.0,
    );
  }

  /// 从 JSON 构造（null-safe）
  factory BrandEarningsSummary.fromJson(Map<String, dynamic> json) {
    return BrandEarningsSummary(
      month: json['month'] as String? ?? '',
      totalBrandRevenue: (json['total_brand_revenue'] as num?)?.toDouble() ?? 0.0,
      pendingSettlement: (json['pending_settlement'] as num?)?.toDouble() ?? 0.0,
      settledAmount: (json['settled_amount'] as num?)?.toDouble() ?? 0.0,
      refundedAmount: (json['refunded_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// =============================================================
// BrandTransaction — 品牌佣金单笔交易记录
// =============================================================

/// 品牌佣金交易明细（一张券 = 一条记录）
class BrandTransaction {
  /// 所属订单 ID
  final String orderId;

  /// 订单子项 ID
  final String orderItemId;

  /// Deal 标题
  final String dealTitle;

  /// 发生交易的门店名称
  final String storeName;

  /// 券面金额
  final double amount;

  /// 品牌佣金费率（如 0.15 = 15%）
  final double brandFeeRate;

  /// 品牌佣金金额
  final double brandFee;

  /// 交易状态（pending / settled / refunded）
  final String status;

  /// 交易发生时间
  final DateTime createdAt;

  const BrandTransaction({
    required this.orderId,
    required this.orderItemId,
    required this.dealTitle,
    required this.storeName,
    required this.amount,
    required this.brandFeeRate,
    required this.brandFee,
    required this.status,
    required this.createdAt,
  });

  /// 从 JSON 构造（null-safe）
  factory BrandTransaction.fromJson(Map<String, dynamic> json) {
    return BrandTransaction(
      orderId: json['order_id'] as String? ?? '',
      orderItemId: json['order_item_id'] as String? ?? '',
      dealTitle: json['deal_title'] as String? ?? '',
      storeName: json['store_name'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      brandFeeRate: (json['brand_fee_rate'] as num?)?.toDouble() ?? 0.0,
      brandFee: (json['brand_fee'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'pending',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  /// 状态展示文本
  String get statusLabel {
    switch (status) {
      case 'settled':
        return 'Settled';
      case 'refunded':
        return 'Refunded';
      default:
        return 'Pending';
    }
  }
}

// =============================================================
// BrandBalance — 品牌可提现余额
// =============================================================

/// 品牌账户余额信息
class BrandBalance {
  /// 可提现余额
  final double availableBalance;

  /// 待结算金额（已核销未到结算期）
  final double pendingSettlement;

  /// 历史总提现金额
  final double totalWithdrawn;

  const BrandBalance({
    required this.availableBalance,
    required this.pendingSettlement,
    required this.totalWithdrawn,
  });

  /// 零余额（默认值）
  factory BrandBalance.zero() {
    return const BrandBalance(
      availableBalance: 0.0,
      pendingSettlement: 0.0,
      totalWithdrawn: 0.0,
    );
  }

  /// 从 JSON 构造（null-safe）
  factory BrandBalance.fromJson(Map<String, dynamic> json) {
    return BrandBalance(
      availableBalance: (json['available_balance'] as num?)?.toDouble() ?? 0.0,
      pendingSettlement: (json['pending_settlement'] as num?)?.toDouble() ?? 0.0,
      totalWithdrawn: (json['total_withdrawn'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// =============================================================
// BrandWithdrawalRecord — 品牌提现记录
// =============================================================

/// 品牌提现单条记录
class BrandWithdrawalRecord {
  /// 提现记录 ID
  final String id;

  /// 提现金额
  final double amount;

  /// 状态（pending / completed / failed）
  final String status;

  /// 申请时间
  final DateTime requestedAt;

  /// 完成时间（仅 completed 时有值）
  final DateTime? completedAt;

  /// 失败原因（仅 failed 时有值）
  final String? failureReason;

  const BrandWithdrawalRecord({
    required this.id,
    required this.amount,
    required this.status,
    required this.requestedAt,
    this.completedAt,
    this.failureReason,
  });

  /// 从 JSON 构造（null-safe）
  factory BrandWithdrawalRecord.fromJson(Map<String, dynamic> json) {
    return BrandWithdrawalRecord(
      id: json['id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'pending',
      requestedAt: json['requested_at'] != null
          ? DateTime.parse(json['requested_at'] as String)
          : DateTime.now(),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      failureReason: json['failure_reason'] as String?,
    );
  }

  /// 状态展示文本
  String get statusLabel {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      default:
        return 'Pending';
    }
  }

  /// 状态颜色值（整型，用于 Color(...)）
  int get statusColorValue {
    switch (status) {
      case 'completed':
        return 0xFF4CAF50;
      case 'failed':
        return 0xFFF44336;
      default:
        return 0xFFFF9800;
    }
  }
}

// =============================================================
// BrandWithdrawalSettings — 品牌自动提现设置
// =============================================================

/// 品牌自动提现配置
class BrandWithdrawalSettings {
  /// 是否启用自动提现
  final bool autoWithdrawalEnabled;

  /// 提现频率（daily / weekly / biweekly / monthly）
  final String autoWithdrawalFrequency;

  /// 提现触发日（周几 1-7 或月几号 1-28）
  final int autoWithdrawalDay;

  /// 最低提现金额
  final double minWithdrawalAmount;

  const BrandWithdrawalSettings({
    required this.autoWithdrawalEnabled,
    required this.autoWithdrawalFrequency,
    required this.autoWithdrawalDay,
    required this.minWithdrawalAmount,
  });

  /// 默认值（未设置时）
  factory BrandWithdrawalSettings.defaults() {
    return const BrandWithdrawalSettings(
      autoWithdrawalEnabled: false,
      autoWithdrawalFrequency: 'weekly',
      autoWithdrawalDay: 1,
      minWithdrawalAmount: 50.00,
    );
  }

  /// 从 JSON 构造（null-safe）
  factory BrandWithdrawalSettings.fromJson(Map<String, dynamic> json) {
    return BrandWithdrawalSettings(
      autoWithdrawalEnabled: json['auto_withdrawal_enabled'] as bool? ?? false,
      autoWithdrawalFrequency:
          json['auto_withdrawal_frequency'] as String? ?? 'weekly',
      autoWithdrawalDay:
          (json['auto_withdrawal_day'] as num?)?.toInt() ?? 1,
      minWithdrawalAmount:
          (json['min_withdrawal_amount'] as num?)?.toDouble() ?? 50.00,
    );
  }

  /// 频率展示文本
  String get frequencyLabel {
    switch (autoWithdrawalFrequency) {
      case 'daily':
        return 'Daily';
      case 'weekly':
        return 'Weekly';
      case 'biweekly':
        return 'Bi-weekly';
      case 'monthly':
        return 'Monthly';
      default:
        return autoWithdrawalFrequency;
    }
  }
}

// =============================================================
// BrandStripeAccount — 品牌 Stripe Connect 账户信息
// =============================================================

/// 品牌 Stripe Connect 账户状态
class BrandStripeAccount {
  /// 是否已连接
  final bool isConnected;

  /// Stripe 账户 ID
  final String? accountId;

  /// Stripe 账户邮箱
  final String? accountEmail;

  /// 账户状态（not_connected / connected / restricted）
  final String accountStatus;

  const BrandStripeAccount({
    required this.isConnected,
    this.accountId,
    this.accountEmail,
    this.accountStatus = 'not_connected',
  });

  /// 未连接状态（默认值）
  factory BrandStripeAccount.notConnected() {
    return const BrandStripeAccount(
      isConnected: false,
      accountStatus: 'not_connected',
    );
  }

  /// 从 JSON 构造（null-safe）
  factory BrandStripeAccount.fromJson(Map<String, dynamic> json) {
    final accountStatus = json['account_status'] as String? ?? 'not_connected';
    return BrandStripeAccount(
      isConnected: json['is_connected'] as bool? ?? (accountStatus == 'connected'),
      accountId: json['account_id'] as String?,
      accountEmail: json['account_email'] as String?,
      accountStatus: accountStatus,
    );
  }
}
