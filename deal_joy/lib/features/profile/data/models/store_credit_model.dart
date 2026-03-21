// Store Credit 相关数据模型
// 对应数据库表：store_credits（余额）、store_credit_transactions（流水）

// ── 余额模型 ─────────────────────────────────────────────────────────────────
class StoreCredit {
  final String id;
  final String userId;
  final double amount;
  final DateTime updatedAt;

  const StoreCredit({
    required this.id,
    required this.userId,
    required this.amount,
    required this.updatedAt,
  });

  /// 从数据库 JSON 解析，所有字段 null-safe
  factory StoreCredit.fromJson(Map<String, dynamic> json) {
    return StoreCredit(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// 当用户没有余额记录时，返回零余额的占位对象
  factory StoreCredit.zero(String userId) {
    return StoreCredit(
      id: '',
      userId: userId,
      amount: 0.0,
      updatedAt: DateTime.now(),
    );
  }
}

// ── 流水记录模型 ──────────────────────────────────────────────────────────────
class StoreCreditTransaction {
  final String id;
  final String userId;
  final String? orderItemId;
  final double amount; // 正数=充入/退款，负数=消费
  final String type; // 'refund_credit' | 'purchase_deduction'
  final String? description;
  final DateTime createdAt;

  const StoreCreditTransaction({
    required this.id,
    required this.userId,
    this.orderItemId,
    required this.amount,
    required this.type,
    this.description,
    required this.createdAt,
  });

  /// 充入（正数）返回 true，消费（负数）返回 false
  bool get isCredit => amount > 0;

  /// UI 展示用的类型标签
  String get displayType => isCredit ? 'Credit' : 'Deduction';

  /// 从数据库 JSON 解析，所有字段 null-safe
  factory StoreCreditTransaction.fromJson(Map<String, dynamic> json) {
    return StoreCreditTransaction(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      orderItemId: json['order_item_id'] as String?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      type: json['type'] as String? ?? '',
      description: json['description'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
