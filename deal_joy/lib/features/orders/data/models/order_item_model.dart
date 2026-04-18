// Order V3 — 订单 item 维度数据模型
// 每个 order_item 对应一张券，status 双视角（客户/商家）独立枚举

import 'coupon_gift_model.dart';

// =============================================================
// 客户端 item 状态枚举
// =============================================================

enum CustomerItemStatus {
  unused,
  used,
  expired,
  refundPending,
  refundProcessing,
  refundReview,
  refundReject,
  refundSuccess,
  gifted;

  static CustomerItemStatus fromString(String s) => switch (s) {
        'unused' => unused,
        'used' => used,
        'expired' => expired,
        'refund_pending' => refundPending,
        'refund_processing' => refundProcessing,
        'refund_review' => refundReview,
        'refund_reject' => refundReject,
        'refund_success' => refundSuccess,
        'gifted' => gifted,
        _ => unused,
      };

  /// 展示给用户的状态文案（英文）
  String get displayLabel => switch (this) {
        unused => 'Unused',
        used => 'Used',
        expired => 'Expired',
        refundPending => 'Refund Pending',
        refundProcessing => 'Refund Processing',
        refundReview => 'Under Review',
        refundReject => 'Refund Rejected',
        refundSuccess => 'Refunded',
        gifted => 'Gifted',
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
  /// 所属订单号（展示用；聚合多笔订单时由 Provider 写入）
  final String? orderNumber;
  final String dealId;

  /// 关联的券 ID（可为 null，DB trigger 自动生成）
  final String? couponId;

  /// 16位原始券码（无 -）
  final String? couponCode;

  /// QR code 内容（16位数字）
  final String? couponQrCode;

  final String? couponStatus;
  final DateTime? couponExpiresAt;

  /// 单价（不含 service fee、不含税）
  final double unitPrice;

  /// service fee 金额
  final double serviceFee;

  /// 税额（快照，按购买时 merchant.metro_area 对应税率计算）
  final double taxAmount;

  /// 税率快照（如 0.0825 表示 8.25%）
  final double? taxRate;

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

  /// Deal 使用规则（从 deals.usage_rules 字段）
  final List<String> usageRules;

  /// Deal 使用须知长文案（从 deals.usage_notes 字段）
  final String? usageNotes;

  /// Deal 可用日（从 deals.usage_days 字段，如 ['Mon','Tue','Wed']，空表示每天可用）
  final List<String> usageDays;

  /// Deal 退款政策
  final String? refundPolicy;

  /// Deal 过期时间
  final DateTime? dealExpiresAt;

  /// Deal 原价
  final double? dealOriginalPrice;

  /// 当前有效的赠送记录（pending 或 claimed）
  final CouponGiftModel? activeGift;

  const OrderItemModel({
    required this.id,
    required this.orderId,
    this.orderNumber,
    required this.dealId,
    this.couponId,
    this.couponCode,
    this.couponQrCode,
    this.couponStatus,
    this.couponExpiresAt,
    required this.unitPrice,
    required this.serviceFee,
    this.taxAmount = 0.0,
    this.taxRate,
    this.purchasedMerchantId,
    this.purchasedMerchantName,
    this.applicableStoreIds = const [],
    this.redeemedMerchantId,
    this.redeemedMerchantName,
    this.redeemedAt,
    this.refundedAt,
    this.refundReason,
    this.usageRules = const [],
    this.usageNotes,
    this.usageDays = const [],
    this.refundPolicy,
    this.dealExpiresAt,
    this.dealOriginalPrice,
    this.refundAmount,
    this.refundMethod,
    required this.customerStatus,
    required this.merchantStatus,
    this.selectedOptions,
    required this.createdAt,
    required this.dealTitle,
    this.dealImageUrl,
    this.merchantName,
    this.activeGift,
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

  /// 核销后 24h 内：走争议退款（submit-refund-dispute），与 Edge 校验窗口一致
  bool get isInDisputeRefundWindow {
    if (customerStatus != CustomerItemStatus.used) return false;
    final r = redeemedAt;
    if (r == null) return false;
    final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 24));
    return !r.toUtc().isBefore(cutoff);
  }

  /// 核销超过 24h 且在 7 天内：走 After-sales 表单
  bool get isInAfterSalesRefundWindow {
    if (customerStatus != CustomerItemStatus.used) return false;
    final r = redeemedAt;
    if (r == null) return false;
    final now = DateTime.now().toUtc();
    final afterDispute = now.subtract(const Duration(hours: 24));
    final afterSalesEnd = now.subtract(const Duration(days: 7));
    return r.toUtc().isBefore(afterDispute) && !r.toUtc().isBefore(afterSalesEnd);
  }

  /// 已超过 7 天售后窗口
  bool get isPastAfterSalesRefundWindow {
    if (customerStatus != CustomerItemStatus.used) return false;
    final r = redeemedAt;
    if (r == null) return false;
    return r.toUtc().isBefore(DateTime.now().toUtc().subtract(const Duration(days: 7)));
  }

  /// 已使用后可写评价
  bool get showWriteReview => customerStatus == CustomerItemStatus.used;

  /// 可赠送（未使用且未赠出）
  bool get showGift =>
      customerStatus == CustomerItemStatus.unused && activeGift == null;

  /// 可撤回赠送（已赠出 + pending 状态）
  bool get showRecallGift =>
      customerStatus == CustomerItemStatus.gifted &&
      activeGift?.status == GiftStatus.pending;

  /// 可修改受赠方（已赠出 + pending 状态）
  bool get showEditRecipient =>
      customerStatus == CustomerItemStatus.gifted &&
      activeGift?.status == GiftStatus.pending;

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

    // 解析嵌套 coupons 对象（来自 join）
    final couponsObj = json['coupons'] as Map<String, dynamic>?;

    // 辅助：同时尝试 snake_case 和 camelCase
    T? pick<T>(String snake, String camel) =>
        (json[snake] ?? json[camel]) as T?;
    DateTime? pickDate(String snake, String camel) {
      final v = json[snake] ?? json[camel];
      return v != null ? DateTime.tryParse(v as String) : null;
    }

    return OrderItemModel(
      id: json['id'] as String? ?? '',
      orderId: pick<String>('order_id', 'orderId') ?? '',
      orderNumber: pick<String>('order_number', 'orderNumber'),
      dealId: pick<String>('deal_id', 'dealId') ?? '',
      couponId: pick<String>('coupon_id', 'couponId') ?? couponsObj?['id'] as String?,
      couponCode: couponsObj?['coupon_code'] as String? ??
          pick<String>('coupon_code', 'couponCode'),
      couponQrCode: couponsObj?['qr_code'] as String? ??
          pick<String>('coupon_qr_code', 'couponQrCode'),
      couponStatus: couponsObj?['status'] as String? ??
          pick<String>('coupon_status', 'couponStatus'),
      couponExpiresAt: (couponsObj?['expires_at'] ??
              json['coupon_expires_at'] ?? json['couponExpiresAt']) != null
          ? DateTime.tryParse((couponsObj?['expires_at'] ??
              json['coupon_expires_at'] ?? json['couponExpiresAt']) as String)
          : null,
      unitPrice: (pick<num>('unit_price', 'unitPrice'))?.toDouble() ?? 0.0,
      serviceFee: (pick<num>('service_fee', 'serviceFee'))?.toDouble() ?? 0.0,
      taxAmount: (pick<num>('tax_amount', 'taxAmount'))?.toDouble() ?? 0.0,
      taxRate: (pick<num>('tax_rate', 'taxRate'))?.toDouble(),
      purchasedMerchantId: pick<String>('purchased_merchant_id', 'purchasedMerchantId'),
      purchasedMerchantName: pick<String>('purchased_merchant_name', 'purchasedMerchantName'),
      applicableStoreIds: applicableStoreIds,
      redeemedMerchantId: pick<String>('redeemed_merchant_id', 'redeemedMerchantId'),
      redeemedMerchantName: pick<String>('redeemed_merchant_name', 'redeemedMerchantName'),
      redeemedAt: pickDate('redeemed_at', 'redeemedAt'),
      refundedAt: pickDate('refunded_at', 'refundedAt'),
      refundReason: pick<String>('refund_reason', 'refundReason'),
      refundAmount: (pick<num>('refund_amount', 'refundAmount'))?.toDouble(),
      refundMethod: pick<String>('refund_method', 'refundMethod'),
      customerStatus: CustomerItemStatus.fromString(
          pick<String>('customer_status', 'customerStatus') ?? 'unused'),
      merchantStatus: MerchantItemStatus.fromString(
          pick<String>('merchant_status', 'merchantStatus') ?? 'unused'),
      selectedOptions: (json['selected_options'] ?? json['selectedOptions']) as Map<String, dynamic>?,
      createdAt: pickDate('created_at', 'createdAt') ?? DateTime.now(),
      // deal 标题：优先 join 嵌套 → camelCase 扁平 → snake_case 扁平
      dealTitle: (dealsObj?['title'] as String?) ??
          pick<String>('deal_title', 'dealTitle') ??
          '',
      dealImageUrl: dealImageUrl ??
          pick<String>('deal_image_url', 'dealImageUrl'),
      // 商家名
      merchantName: (merchantsObj?['name'] as String?) ??
          pick<String>('merchant_name', 'merchantName'),
      // Deal 额外信息
      usageRules: ((json['usageRules'] ?? json['usage_rules'] ?? dealsObj?['usage_rules']) as List?)
              ?.cast<String>() ?? const [],
      usageNotes: pick<String>('usage_notes', 'usageNotes') ??
          dealsObj?['usage_notes'] as String?,
      usageDays: ((json['usageDays'] ?? json['usage_days'] ?? dealsObj?['usage_days']) as List?)
              ?.cast<String>() ?? const [],
      refundPolicy: pick<String>('refund_policy', 'refundPolicy') ??
          dealsObj?['refund_policy'] as String?,
      dealExpiresAt: pickDate('deal_expires_at', 'dealExpiresAt') ??
          (dealsObj?['expires_at'] != null ? DateTime.tryParse(dealsObj!['expires_at'] as String) : null),
      dealOriginalPrice: (pick<num>('deal_original_price', 'dealOriginalPrice') ??
          (dealsObj?['original_price'] as num?))?.toDouble(),
      // 解析 active gift（从 coupon_gifts join）
      activeGift: _parseActiveGift(json['coupon_gifts']),
    );
  }

  /// 从 coupon_gifts join 数据中解析当前有效的 gift（pending 或 claimed）
  static CouponGiftModel? _parseActiveGift(dynamic giftData) {
    if (giftData == null) return null;
    if (giftData is List) {
      final activeList = giftData
          .cast<Map<String, dynamic>>()
          .where((g) => g['status'] == 'pending' || g['status'] == 'claimed')
          .toList();
      if (activeList.isNotEmpty) {
        return CouponGiftModel.fromJson(activeList.first);
      }
    } else if (giftData is Map<String, dynamic>) {
      return CouponGiftModel.fromJson(giftData);
    }
    return null;
  }
}
