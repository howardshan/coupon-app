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

/// 流水列表展示：统一历史杂项文案 + 新写入的短描述（UI 全英文）
extension StoreCreditTransactionDisplay on StoreCreditTransaction {
  String get displayLabel {
    final typeNorm = type.trim().toLowerCase();
    final raw = description?.trim();

    if (typeNorm == 'admin_adjustment') {
      if (raw == null || raw.isEmpty) return 'Account adjustment';
      return raw.length > 72 ? '${raw.substring(0, 69)}…' : raw;
    }

    if (raw == null || raw.isEmpty) {
      return displayType;
    }

    final lower = raw.toLowerCase();

    // 新后端短文案 / 与后端常量一致
    if (lower == 'after-sale refund' || lower == 'after_sale_post_redeem') {
      return 'After-sale refund';
    }
    if (lower == 'refund to store credit') return 'Refund to Store Credit';
    if (lower == 'partial refund to store credit') {
      return 'Partial refund to Store Credit';
    }
    if (lower == 'auto refund (expired voucher)') {
      return 'Auto refund (expired voucher)';
    }
    if (lower == 'auto refund (expired voucher, store credit)') {
      return 'Auto refund (expired voucher, store credit)';
    }
    if (lower == 'auto refund (expired voucher, card to credit)') {
      return 'Auto refund (expired voucher, card to credit)';
    }
    if (lower == 'order checkout (store credit)' ||
        lower == 'order paid with store credit') {
      return 'Order checkout (store credit)';
    }

    // 历史长句 / 旧默认值
    if (lower.startsWith('auto refund for expired coupon')) {
      return 'Auto refund (expired voucher)';
    }
    if (lower.startsWith('auto refund (store credit portion) for expired')) {
      return 'Auto refund (expired voucher, store credit)';
    }
    if (lower.startsWith('auto refund (card fallback to store credit)')) {
      return 'Auto refund (expired voucher, card to credit)';
    }
    if (lower == 'refund for order item') return 'Refund to Store Credit';
    if (lower.startsWith('partial refund (store credit portion)')) {
      return 'Partial refund to Store Credit';
    }
    if (lower.startsWith('purchase deduction for order')) {
      return 'Order checkout (store credit)';
    }
    if (lower == 'refund dispute approved' ||
        lower.startsWith('refund dispute')) {
      return 'Refund to Store Credit';
    }

    // 裸 snake_case（无空格）→ 标题式可读词
    if (!raw.contains(' ') && !raw.contains('\n') && raw.contains('_')) {
      final words = raw.split('_').where((w) => w.isNotEmpty).toList();
      if (words.isNotEmpty) {
        return words
            .map(
              (w) =>
                  '${w[0].toUpperCase()}${w.length > 1 ? w.substring(1).toLowerCase() : ''}',
            )
            .join(' ');
      }
    }

    if (raw.length > 72) {
      return '${raw.substring(0, 69)}…';
    }
    return raw;
  }
}
