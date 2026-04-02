// 广告账户数据模型
// 对应后端 ad_accounts 表，记录商家的广告余额和消费统计

/// 广告账户
class AdAccount {
  final String id;
  final String merchantId;
  final double balance;           // 当前可用余额
  final double totalRecharged;    // 累计充值金额
  final double totalSpent;        // 累计消费金额
  final int activeCampaignCount;  // 当前活跃广告计划数量
  final DateTime createdAt;

  const AdAccount({
    required this.id,
    required this.merchantId,
    required this.balance,
    required this.totalRecharged,
    required this.totalSpent,
    required this.activeCampaignCount,
    required this.createdAt,
  });

  /// 从 Edge Function 返回的 JSON 构造，所有字段 null-safe
  factory AdAccount.fromJson(Map<String, dynamic> json) {
    return AdAccount(
      id:                  json['id'] as String? ?? '',
      merchantId:          json['merchant_id'] as String? ?? '',
      balance:             (json['balance'] as num?)?.toDouble() ?? 0.0,
      totalRecharged:      (json['total_recharged'] as num?)?.toDouble() ?? 0.0,
      totalSpent:          (json['total_spent'] as num?)?.toDouble() ?? 0.0,
      activeCampaignCount: (json['active_campaign_count'] as num?)?.toInt() ?? 0,
      createdAt:           json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  /// 空账户（用于加载前的占位）
  factory AdAccount.empty() {
    return AdAccount(
      id:                  '',
      merchantId:          '',
      balance:             0.0,
      totalRecharged:      0.0,
      totalSpent:          0.0,
      activeCampaignCount: 0,
      createdAt:           DateTime.now(),
    );
  }
}
