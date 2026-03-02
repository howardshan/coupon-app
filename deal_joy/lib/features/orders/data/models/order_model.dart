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
  final DealSummary? deal;

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
    this.deal,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
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
        deal: json['deals'] != null
            ? DealSummary.fromJson(json['deals'] as Map<String, dynamic>)
            : null,
      );

  bool get isUnused => status == 'unused';
  bool get isUsed => status == 'used';
  bool get isRefunded => status == 'refunded';
  bool get isRefundRequested => status == 'refund_requested';
  bool get isExpired => status == 'expired';

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
