// 团购券数据模型 — 对应 Supabase coupons 表，携带关联的 deal/merchant 信息

class CouponModel {
  final String id;
  final String orderId;
  final String userId;
  final String dealId;
  final String merchantId;
  final String qrCode;
  final String status; // unused | used | expired | refunded
  final DateTime expiresAt;
  final DateTime? usedAt;
  final DateTime createdAt;
  final String? giftedFrom;
  final String? verifiedBy;

  // Join 字段 — 来自 deals 表
  final String? dealTitle;
  final String? dealDescription;
  final String? dealImageUrl;
  final String? refundPolicy;

  // Join 字段 — 来自 deals.merchants 表
  final String? merchantName;
  final String? merchantLogoUrl;
  final String? merchantAddress;
  final String? merchantPhone;

  const CouponModel({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.dealId,
    required this.merchantId,
    required this.qrCode,
    required this.status,
    required this.expiresAt,
    this.usedAt,
    required this.createdAt,
    this.giftedFrom,
    this.verifiedBy,
    this.dealTitle,
    this.dealDescription,
    this.dealImageUrl,
    this.refundPolicy,
    this.merchantName,
    this.merchantLogoUrl,
    this.merchantAddress,
    this.merchantPhone,
  });

  factory CouponModel.fromJson(Map<String, dynamic> json) {
    // 解析嵌套的 deals 对象
    final deals = json['deals'] as Map<String, dynamic>?;

    // 解析嵌套的 deals.merchants 对象
    final merchants = deals?['merchants'] as Map<String, dynamic>?;

    // deal 图片取第一张
    String? dealImageUrl;
    if (deals != null) {
      final imageUrls = deals['image_urls'] as List?;
      if (imageUrls != null && imageUrls.isNotEmpty) {
        dealImageUrl = imageUrls.first as String?;
      }
    }

    return CouponModel(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      userId: json['user_id'] as String,
      dealId: json['deal_id'] as String,
      merchantId: json['merchant_id'] as String,
      qrCode: json['qr_code'] as String,
      status: json['status'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      usedAt: json['used_at'] != null
          ? DateTime.parse(json['used_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      giftedFrom: json['gifted_from'] as String?,
      verifiedBy: json['verified_by'] as String?,
      dealTitle: deals?['title'] as String?,
      dealDescription: deals?['description'] as String?,
      dealImageUrl: dealImageUrl,
      refundPolicy: deals?['refund_policy'] as String?,
      merchantName: merchants?['name'] as String?,
      merchantLogoUrl: merchants?['logo_url'] as String?,
      merchantAddress: merchants?['address'] as String?,
      merchantPhone: merchants?['phone'] as String?,
    );
  }

  // 状态便捷 getter（过期同时考虑 status 与过期时间，便于展示「已过期」提示）
  bool get isUnused => status == 'unused';
  bool get isUsed => status == 'used';
  bool get isExpired => status == 'expired' || DateTime.now().isAfter(expiresAt);
  bool get isRefunded => status == 'refunded';
}
