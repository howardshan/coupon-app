// Order V3 — 订单数据模型
// V3 订单以 order_items 为核心，每张券独立维护状态
// 保留旧字段（dealId, couponId, quantity, status 等）以向后兼容旧订单查询

import 'order_item_model.dart';

class OrderModel {
  final String id;
  final String userId;

  /// 订单号（如 DJ-20260301-0001），用于区分同一 deal 的多次购买
  final String? orderNumber;

  /// 券总价（所有 items 的 unit_price 之和）
  final double itemsAmount;

  /// service fee 总额
  final double serviceFeeTotal;

  /// 整单税费合计（快照，从各 item tax_amount 累加得到）
  final double taxAmount;

  /// 总计（itemsAmount + serviceFeeTotal + taxAmount）
  final double totalAmount;

  final String paymentIntentId;

  /// Stripe charge ID（退款时需要）
  final String? stripeChargeId;

  /// 本单使用的 Store Credit 金额
  final double storeCreditUsed;

  final DateTime? paidAt;
  final DateTime createdAt;

  /// V3 order items 列表（每张券一个 item）
  final List<OrderItemModel> items;

  // ---------- 向后兼容旧字段（V2 订单可能没有 order_items） ----------

  /// 旧版：订单关联 deal ID（V3 由 items 持有）
  final String? dealId;

  /// 旧版：订单关联 coupon ID
  final String? couponId;

  /// 旧版：购买数量
  final int? quantity;

  /// 旧版：单价
  final double? unitPrice;

  /// 旧版：order 级别状态（V3 不使用，状态在 item 层）
  final String? status;

  /// 旧版：退款原因（V3 由 item 持有）
  final String? refundReason;

  /// 旧版：退款申请时间
  final DateTime? refundRequestedAt;

  /// 旧版：退款完成时间
  final DateTime? refundedAt;

  /// 旧版：管理员拒绝退款时间
  final DateTime? refundRejectedAt;

  /// 旧版：deal 摘要（join 自 deals 表）
  final DealSummary? deal;

  /// 旧版：券过期时间（来自 coupons.expires_at）
  final DateTime? couponExpiresAt;

  /// 旧版：是否已完成 Stripe capture
  final bool isCaptured;

  const OrderModel({
    required this.id,
    required this.userId,
    this.orderNumber,
    this.itemsAmount = 0.0,
    this.serviceFeeTotal = 0.0,
    this.taxAmount = 0.0,
    required this.totalAmount,
    required this.paymentIntentId,
    this.stripeChargeId,
    this.storeCreditUsed = 0.0,
    this.paidAt,
    required this.createdAt,
    this.items = const [],
    // 旧字段
    this.dealId,
    this.couponId,
    this.quantity,
    this.unitPrice,
    this.status,
    this.refundReason,
    this.refundRequestedAt,
    this.refundedAt,
    this.refundRejectedAt,
    this.deal,
    this.couponExpiresAt,
    this.isCaptured = true,
  });

  // =============================================================
  // fromJson — 兼容两种数据源：
  //   1. 直接查表（items 通过 join order_items 获取）
  //   2. Edge Function 返回（items 在 json['items'] 数组中）
  // =============================================================

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    // 解析 V3 items 列表（两种 key 都尝试）
    final rawItems =
        (json['items'] as List?) ?? (json['order_items'] as List?);
    final orderCreatedRaw = json['created_at'];
    final items = rawItems
            ?.map((e) {
              final m = Map<String, dynamic>.from(e as Map<String, dynamic>);
              if (m['created_at'] == null &&
                  m['createdAt'] == null &&
                  orderCreatedRaw != null) {
                m['created_at'] = orderCreatedRaw;
              }
              return OrderItemModel.fromJson(m);
            })
            .toList() ??
        const <OrderItemModel>[];

    // 旧版：解析 coupons 嵌套对象获取过期时间
    DateTime? couponExpiresAt;
    final coupons = json['coupons'];
    if (coupons is Map<String, dynamic> && coupons['expires_at'] != null) {
      couponExpiresAt =
          DateTime.tryParse(coupons['expires_at'] as String);
    }

    return OrderModel(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      orderNumber: json['order_number'] as String?,
      itemsAmount:
          (json['items_amount'] as num?)?.toDouble() ?? 0.0,
      serviceFeeTotal:
          (json['service_fee_total'] as num?)?.toDouble() ?? 0.0,
      taxAmount:
          (json['tax_amount'] as num?)?.toDouble() ?? 0.0,
      totalAmount:
          (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      paymentIntentId:
          json['payment_intent_id'] as String? ?? '',
      stripeChargeId: json['stripe_charge_id'] as String?,
      storeCreditUsed: (json['store_credit_used'] as num?)?.toDouble() ?? 0.0,
      paidAt: json['paid_at'] != null
          ? DateTime.tryParse(json['paid_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ??
              DateTime.now()
          : DateTime.now(),
      items: items,
      // 旧字段
      dealId: json['deal_id'] as String?,
      couponId: json['coupon_id'] as String?,
      quantity: (json['quantity'] as num?)?.toInt(),
      unitPrice: (json['unit_price'] as num?)?.toDouble(),
      status: json['status'] as String?,
      refundReason: json['refund_reason'] as String?,
      refundRequestedAt: json['refund_requested_at'] != null
          ? DateTime.tryParse(json['refund_requested_at'] as String)
          : null,
      refundedAt: json['refunded_at'] != null
          ? DateTime.tryParse(json['refunded_at'] as String)
          : null,
      refundRejectedAt: json['refund_rejected_at'] != null
          ? DateTime.tryParse(json['refund_rejected_at'] as String)
          : null,
      isCaptured: json['is_captured'] as bool? ?? true,
      deal: json['deals'] != null
          ? DealSummary.fromJson(
              json['deals'] as Map<String, dynamic>)
          : null,
      couponExpiresAt: couponExpiresAt,
    );
  }

  // =============================================================
  // V3 计算属性
  // =============================================================

  /// 总 item 数（= 购买的券数量）
  int get itemCount => items.length;

  /// 按 deal_id 分组（订单详情页展示多 deal 场景）
  Map<String, List<OrderItemModel>> get itemsByDeal {
    final map = <String, List<OrderItemModel>>{};
    for (final item in items) {
      map.putIfAbsent(item.dealId, () => []).add(item);
    }
    return map;
  }

  /// 所有 items 均已退款成功
  bool get isFullyRefunded =>
      items.isNotEmpty &&
      items.every(
          (i) => i.customerStatus == CustomerItemStatus.refundSuccess);

  // =============================================================
  // 旧版 getter（向后兼容，UI 层可继续使用）
  // =============================================================

  bool get isUnused => status == 'unused';
  bool get isUsed => status == 'used';
  bool get isRefunded => status == 'refunded';
  bool get isRefundRequested => status == 'refund_requested';
  bool get isRefundFailed => status == 'refund_failed';
  bool get isExpired => status == 'expired';

  /// 管理员曾拒绝过该订单的退款申请
  bool get isRefundRejected => refundRejectedAt != null;

  /// 未使用订单的券已按时间过期（按商家时区 CST UTC-6，给 30h 缓冲）
  bool get isExpiredByDate =>
      couponExpiresAt != null &&
      DateTime.now().toUtc().isAfter(
          couponExpiresAt!.toUtc().add(const Duration(hours: 30)));

  /// 旧版：仅未使用的订单可退款
  bool get canRefund => isUnused;
}

// =============================================================
// DealSummary — 旧版 deal 摘要（OrderModel.deal 字段用）
// =============================================================

class DealSummary {
  final String id;
  final String title;
  final String? imageUrl;
  final String? merchantName;

  const DealSummary({
    required this.id,
    required this.title,
    this.imageUrl,
    this.merchantName,
  });

  factory DealSummary.fromJson(Map<String, dynamic> json) => DealSummary(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        imageUrl: (json['image_urls'] as List?)?.isNotEmpty == true
            ? json['image_urls'][0] as String?
            : null,
        merchantName: json['merchants'] != null
            ? (json['merchants'] as Map)['name'] as String?
            : null,
      );
}
