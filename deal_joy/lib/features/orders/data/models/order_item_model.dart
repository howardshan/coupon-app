// Order V3 — 订单 item 维度数据模型
// 每个 order_item 对应一张券，status 双视角（客户/商家）独立枚举

// =============================================================
// 客户端 item 状态枚举
// =============================================================

enum CustomerItemStatus {
  unused,
  used,
  expired,
  refundPending,
  refundReview,
  refundReject,
  refundSuccess;

  static CustomerItemStatus fromString(String s) => switch (s) {
        'unused' => unused,
        'used' => used,
        'expired' => expired,
        'refund_pending' => refundPending,
        'refund_review' => refundReview,
        'refund_reject' => refundReject,
        'refund_success' => refundSuccess,
        _ => unused,
      };

  /// 展示给用户的状态文案（英文）
  String get displayLabel => switch (this) {
        unused => 'Unused',
        used => 'Used',
        expired => 'Expired',
        refundPending => 'Refund Processing',
        refundReview => 'Under Review',
        refundReject => 'Refund Rejected',
        refundSuccess => 'Refunded',
      };
}

// =============================================================
// 商家端 item 状态枚举（用于商家侧展示，客户端只读）
// =============================================================

enum MerchantItemStatus {
  unused,
  unpaid,
  pending,
  paid,
  refundRequest,
  refundReview,
  refundReject,
  refundSuccess;

  static MerchantItemStatus fromString(String s) => switch (s) {
        'unused' => unused,
        'unpaid' => unpaid,
        'pending' => pending,
        'paid' => paid,
        'refund_request' => refundRequest,
        'refund_review' => refundReview,
        'refund_reject' => refundReject,
        'refund_success' => refundSuccess,
        _ => unused,
      };

  /// 展示给商家的状态文案（英文）
  String get displayLabel => switch (this) {
        unused => 'Unused',
        unpaid => 'Unpaid',
        pending => 'Pending',
        paid => 'Paid',
        refundRequest => 'Refund Requested',
        refundReview => 'Under Review',
        refundReject => 'Refund Rejected',
        refundSuccess => 'Refunded',
      };
}

// =============================================================
// OrderItemModel — 订单 item 数据模型
// =============================================================

class OrderItemModel {
  final String id;
  final String orderId;
  final String dealId;

  /// 关联的券 ID（可为 null，DB trigger 自动生成）
  final String? couponId;

  /// 16位原始券码（无 -）
  final String? couponCode;

  /// QR code 内容（16位数字）
  final String? couponQrCode;

  final String? couponStatus;
  final DateTime? couponExpiresAt;

  /// 单价（不含 service fee）
  final double unitPrice;

  /// service fee 金额
  final double serviceFee;

  /// 购买时关联的商家 ID 快照
  final String? purchasedMerchantId;

  /// 购买时关联的商家名称快照
  final String? purchasedMerchantName;

  /// 此 item 可用的门店 ID 列表（购买时快照）
  final List<String> applicableStoreIds;

  /// 核销该 item 的商家 ID
  final String? redeemedMerchantId;

  /// 核销该 item 的商家名称
  final String? redeemedMerchantName;

  final DateTime? redeemedAt;
  final DateTime? refundedAt;
  final String? refundReason;
  final double? refundAmount;

  /// 退款方式：'store_credit' | 'original_payment'
  final String? refundMethod;

  /// 客户视角状态
  final CustomerItemStatus customerStatus;

  /// 商家视角状态
  final MerchantItemStatus merchantStatus;

  /// 购买时选择的规格（如大小、口味等）
  final Map<String, dynamic>? selectedOptions;

  final DateTime createdAt;

  // ---------- join 字段（来自 deals 表） ----------

  /// deal 标题
  final String dealTitle;

  /// deal 第一张图片 URL
  final String? dealImageUrl;

  /// 关联商家名称
  final String? merchantName;

  const OrderItemModel({
    required this.id,
    required this.orderId,
    required this.dealId,
    this.couponId,
    this.couponCode,
    this.couponQrCode,
    this.couponStatus,
    this.couponExpiresAt,
    required this.unitPrice,
    required this.serviceFee,
    this.purchasedMerchantId,
    this.purchasedMerchantName,
    this.applicableStoreIds = const [],
    this.redeemedMerchantId,
    this.redeemedMerchantName,
    this.redeemedAt,
    this.refundedAt,
    this.refundReason,
    this.refundAmount,
    this.refundMethod,
    required this.customerStatus,
    required this.merchantStatus,
    this.selectedOptions,
    required this.createdAt,
    required this.dealTitle,
    this.dealImageUrl,
    this.merchantName,
  });

  // =============================================================
  // 按钮可见性 getter（UI 层根据此决定展示哪些操作按钮）
  // =============================================================

  /// 可展示 QR 核销码
  bool get showQrCode => customerStatus == CustomerItemStatus.unused;

  /// 可取消（未使用状态下可申请退款/取消）
  bool get showCancel => customerStatus == CustomerItemStatus.unused;

  /// 已使用后可申请售后退款
  bool get showRefundRequest => customerStatus == CustomerItemStatus.used;

  /// 已使用后可写评价
  bool get showWriteReview => customerStatus == CustomerItemStatus.used;

  // =============================================================
  // 券码格式化：1A2B3C4D5E6F7G8H → 1A2B-3C4D-5E6F-7G8H
  // =============================================================

  String? get formattedCouponCode {
    final code = couponCode;
    if (code == null || code.length != 16) return code;
    return '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8, 12)}-${code.substring(12, 16)}';
  }

  // =============================================================
  // fromJson — 支持直接查表（order_items join deals/merchants）
  // =============================================================

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    // 解析嵌套 deals 对象（可能来自 join）
    final dealsObj = json['deals'] as Map<String, dynamic>?;
    final merchantsObj = dealsObj?['merchants'] as Map<String, dynamic>?;

    // deal 图片取第一张
    String? dealImageUrl;
    final imageUrls = dealsObj?['image_urls'] as List?;
    if (imageUrls != null && imageUrls.isNotEmpty) {
      dealImageUrl = imageUrls.first as String?;
    }
    // 也接受顶层 deal_image_url 扁平字段
    dealImageUrl ??= json['deal_image_url'] as String?;

    // 解析 applicable_store_ids（JSON 数组 → List<String>）
    final storeIdsRaw = json['applicable_store_ids'] as List?;
    final applicableStoreIds = storeIdsRaw
            ?.map((e) => e?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList() ??
        const <String>[];

    return OrderItemModel(
      id: json['id'] as String? ?? '',
      orderId: json['order_id'] as String? ?? '',
      dealId: json['deal_id'] as String? ?? '',
      couponId: json['coupon_id'] as String?,
      couponCode: json['coupon_code'] as String?,
      couponQrCode: json['coupon_qr_code'] as String?,
      couponStatus: json['coupon_status'] as String?,
      couponExpiresAt: json['coupon_expires_at'] != null
          ? DateTime.tryParse(json['coupon_expires_at'] as String)
          : null,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      serviceFee: (json['service_fee'] as num?)?.toDouble() ?? 0.0,
      purchasedMerchantId: json['purchased_merchant_id'] as String?,
      purchasedMerchantName: json['purchased_merchant_name'] as String?,
      applicableStoreIds: applicableStoreIds,
      redeemedMerchantId: json['redeemed_merchant_id'] as String?,
      redeemedMerchantName: json['redeemed_merchant_name'] as String?,
      redeemedAt: json['redeemed_at'] != null
          ? DateTime.tryParse(json['redeemed_at'] as String)
          : null,
      refundedAt: json['refunded_at'] != null
          ? DateTime.tryParse(json['refunded_at'] as String)
          : null,
      refundReason: json['refund_reason'] as String?,
      refundAmount: (json['refund_amount'] as num?)?.toDouble(),
      refundMethod: json['refund_method'] as String?,
      customerStatus: CustomerItemStatus.fromString(
          json['customer_status'] as String? ?? 'unused'),
      merchantStatus: MerchantItemStatus.fromString(
          json['merchant_status'] as String? ?? 'unused'),
      selectedOptions: json['selected_options'] as Map<String, dynamic>?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      // deal 标题：优先取 join 嵌套字段，其次取顶层扁平字段
      dealTitle: (dealsObj?['title'] as String?) ??
          (json['deal_title'] as String?) ??
          '',
      dealImageUrl: dealImageUrl,
      // 商家名：优先取 join 嵌套，其次取顶层扁平字段
      merchantName: (merchantsObj?['name'] as String?) ??
          (json['merchant_name'] as String?),
    );
  }
}
