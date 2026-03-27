// 团购券数据模型 — 对应 Supabase coupons 表，携带关联的 deal/merchant 信息

class CouponModel {
  final String id;
  final String orderId;
  final String userId;
  final String dealId;
  final String merchantId;
  final String qrCode;
  final String status; // unused | used | expired | refunded | voided
  final String? voidReason;
  final DateTime? voidedAt;
  final DateTime expiresAt;
  final DateTime? usedAt;
  final DateTime createdAt;
  final String? giftedFrom;
  final String? verifiedBy;

  // V3 新增字段 — 关联 order_items
  /// 关联的 order_item ID（V3 系统新增）
  final String? orderItemId;

  /// 16位原始券码（V3 order_items.coupon_code 字段）
  final String? couponCode;

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

  // 多店通用：适用门店 ID 列表（旧字段，来自 deals.applicable_merchant_ids）
  final List<String>? applicableMerchantIds;

  // 购买时门店快照（来自 orders.applicable_store_ids）
  final List<String>? applicableStoreIds;

  // 退款信息（来自 order_items join）
  final double? unitPrice;
  final DateTime? refundedAt;
  final double? refundAmount;
  final String? refundMethod; // 'original_payment' | 'store_credit'

  const CouponModel({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.dealId,
    required this.merchantId,
    required this.qrCode,
    required this.status,
    this.voidReason,
    this.voidedAt,
    required this.expiresAt,
    this.usedAt,
    required this.createdAt,
    this.giftedFrom,
    this.verifiedBy,
    this.orderItemId,
    this.couponCode,
    this.dealTitle,
    this.dealDescription,
    this.dealImageUrl,
    this.refundPolicy,
    this.merchantName,
    this.merchantLogoUrl,
    this.merchantAddress,
    this.merchantPhone,
    this.applicableMerchantIds,
    this.applicableStoreIds,
    this.unitPrice,
    this.refundedAt,
    this.refundAmount,
    this.refundMethod,
  });

  factory CouponModel.fromJson(Map<String, dynamic> json) {
    // V3：从 order_items join 获取 applicable_store_ids（新字段）
    // 注意：order_items 是反向 FK join，返回 List 而非 Map，取第一个元素
    final orderItemsList = json['order_items'] as List?;
    final orderItems = (orderItemsList != null && orderItemsList.isNotEmpty)
        ? orderItemsList.first as Map<String, dynamic>?
        : null;
    // 向后兼容旧版：从 orders join 获取（也可能是 List）
    final ordersRaw = json['orders'];
    final orders = ordersRaw is Map<String, dynamic>
        ? ordersRaw
        : (ordersRaw is List && ordersRaw.isNotEmpty ? ordersRaw.first as Map<String, dynamic>? : null);

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
      status: json['status'] as String? ?? 'unused',
      voidReason: json['void_reason'] as String?,
      voidedAt: json['voided_at'] != null
          ? DateTime.parse(json['voided_at'] as String)
          : null,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      usedAt: json['used_at'] != null
          ? DateTime.parse(json['used_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      giftedFrom: json['gifted_from'] as String?,
      verifiedBy: json['verified_by'] as String?,
      orderItemId: json['order_item_id'] as String?,
      couponCode: json['coupon_code'] as String?,
      dealTitle: deals?['title'] as String?,
      dealDescription: deals?['description'] as String?,
      dealImageUrl: dealImageUrl,
      refundPolicy: deals?['refund_policy'] as String?,
      merchantName: merchants?['name'] as String?,
      merchantLogoUrl: merchants?['logo_url'] as String?,
      merchantAddress: merchants?['address'] as String?,
      merchantPhone: merchants?['phone'] as String?,
      applicableMerchantIds: (deals?['applicable_merchant_ids'] as List?)
          ?.map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
      // V3：优先从 order_items join 获取，向后兼容旧版从 orders join 获取
      applicableStoreIds: ((orderItems?['applicable_store_ids'] ??
                  orders?['applicable_store_ids']) as List?)
          ?.map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
      // 退款信息（从 order_items join 获取）
      unitPrice: (orderItems?['unit_price'] as num?)?.toDouble(),
      refundedAt: orderItems?['refunded_at'] != null
          ? DateTime.parse(orderItems!['refunded_at'] as String)
          : null,
      refundAmount: (orderItems?['refund_amount'] as num?)?.toDouble(),
      refundMethod: orderItems?['refund_method'] as String?,
    );
  }

  // 状态便捷 getter（过期同时考虑 status 与过期时间，便于展示「已过期」提示）
  bool get isUnused => status == 'unused';
  bool get isUsed => status == 'used';
  bool get isExpired => status == 'expired' || DateTime.now().isAfter(expiresAt);
  bool get isRefunded => status == 'refunded';
  bool get isVoided => status == 'voided';
}
