class OrderModel {
  final String id;
  final String userId;
  final String dealId;
  final String? couponId; // nullable — auto-filled by DB trigger
  final int quantity;
  final double totalAmount;
  final String status; // unused | used | refunded | refund_requested | expired
  final String paymentIntentId;
  final String? refundReason;
  final DateTime createdAt;
  final DateTime? refundRequestedAt;
  final DateTime? refundedAt;
  /// 管理员拒绝退款时写入，详情页多维度展示 Refund Rejected
  final DateTime? refundRejectedAt;
  final DealSummary? deal;
  /// 券过期时间（来自 coupons.expires_at，用于列表展示「按时间已过期」）
  final DateTime? couponExpiresAt;
  /// 订单号，用于区分同一 deal 的多次购买
  final String? orderNumber;
  /// 是否已完成 Stripe capture（true = 已扣款；false = 预授权未扣款）
  final bool isCaptured;

  const OrderModel({
    required this.id,
    required this.userId,
    required this.dealId,
    this.couponId,
    required this.quantity,
    required this.totalAmount,
    required this.status,
    required this.paymentIntentId,
    this.refundReason,
    required this.createdAt,
    this.refundRequestedAt,
    this.refundedAt,
    this.refundRejectedAt,
    this.deal,
    this.couponExpiresAt,
    this.orderNumber,
    this.isCaptured = true,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    DateTime? couponExpiresAt;
    final coupons = json['coupons'];
    if (coupons is Map<String, dynamic> && coupons['expires_at'] != null) {
      couponExpiresAt = DateTime.parse(coupons['expires_at'] as String);
    }
    return OrderModel(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        dealId: json['deal_id'] as String,
        couponId: json['coupon_id'] as String?,
        quantity: json['quantity'] as int,
        totalAmount: (json['total_amount'] as num).toDouble(),
        status: json['status'] as String,
        paymentIntentId: json['payment_intent_id'] as String,
        refundReason: json['refund_reason'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        refundRequestedAt: json['refund_requested_at'] != null
            ? DateTime.parse(json['refund_requested_at'] as String)
            : null,
        refundedAt: json['refunded_at'] != null
            ? DateTime.parse(json['refunded_at'] as String)
            : null,
        refundRejectedAt: json['refund_rejected_at'] != null
            ? DateTime.parse(json['refund_rejected_at'] as String)
            : null,
        orderNumber: json['order_number'] as String?,
        isCaptured: json['is_captured'] as bool? ?? true,
        deal: json['deals'] != null
            ? DealSummary.fromJson(json['deals'] as Map<String, dynamic>)
            : null,
        couponExpiresAt: couponExpiresAt,
      );
  }

  bool get isUnused => status == 'unused';
  bool get isUsed => status == 'used';
  bool get isRefunded => status == 'refunded';
  bool get isRefundRequested => status == 'refund_requested';
  bool get isRefundFailed => status == 'refund_failed';
  bool get isExpired => status == 'expired';
  /// 管理员曾拒绝过该订单的退款申请（详情页展示 Refund Rejected）
  bool get isRefundRejected => refundRejectedAt != null;
  /// 未使用订单的券已按时间过期（用于列表展示）
  bool get isExpiredByDate =>
      couponExpiresAt != null && DateTime.now().isAfter(couponExpiresAt!);

  /// 仅未使用的订单可以退款（已使用/过期/已退款/已申请退款 均不可）
  bool get canRefund => isUnused;
}

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
        id: json['id'] as String,
        title: json['title'] as String,
        imageUrl: (json['image_urls'] as List?)?.isNotEmpty == true
            ? json['image_urls'][0] as String
            : null,
        merchantName: json['merchants'] != null
            ? (json['merchants'] as Map)['name'] as String?
            : null,
      );
}
