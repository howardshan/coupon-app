class OrderModel {
  final String id;
  final String userId;
  final String dealId;
  final String? couponId; // nullable — auto-filled by DB trigger
  final int quantity;
  final double totalAmount;
  final String status; // unused | used | refunded | expired
  final String paymentIntentId;
  final DateTime createdAt;
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
    required this.createdAt,
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
        createdAt: DateTime.parse(json['created_at'] as String),
        deal: json['deals'] != null
            ? DealSummary.fromJson(json['deals'] as Map<String, dynamic>)
            : null,
      );

  bool get isUnused => status == 'unused';
  bool get isUsed => status == 'used';
  bool get isRefunded => status == 'refunded';
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
