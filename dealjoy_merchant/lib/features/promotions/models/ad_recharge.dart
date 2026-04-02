// 广告余额充值记录数据模型
// 对应后端 ad_recharges 表，记录每次充值的金额与状态

/// 广告余额充值记录
class AdRecharge {
  final String id;
  final String merchantId;
  final double amount;   // 充值金额（美元）
  final String status;   // 充值状态: pending | succeeded | failed
  final DateTime createdAt;

  const AdRecharge({
    required this.id,
    required this.merchantId,
    required this.amount,
    required this.status,
    required this.createdAt,
  });

  /// 从 Edge Function 返回的 JSON 构造，所有字段 null-safe
  factory AdRecharge.fromJson(Map<String, dynamic> json) {
    return AdRecharge(
      id:         json['id'] as String? ?? '',
      merchantId: json['merchant_id'] as String? ?? '',
      amount:     (json['amount'] as num?)?.toDouble() ?? 0.0,
      status:     json['status'] as String? ?? 'pending',
      createdAt:  json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  /// 是否已成功
  bool get isSucceeded => status == 'succeeded';

  /// 是否处理中
  bool get isPending => status == 'pending';

  /// 是否失败
  bool get isFailed => status == 'failed';
}
