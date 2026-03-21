// 订单管理数据模型
// 包含: MerchantOrder、OrderStatus、OrderTimeline、TimelineEvent、OrderFilter

import 'package:flutter/material.dart';

// =============================================================
// OrderStatus — 订单状态枚举
// =============================================================

/// 订单状态（与数据库 order_status enum 映射 + 展示用 expired / pendingRefund）
enum OrderStatus {
  /// 已支付，未核销
  paid,
  /// 已核销（used）
  redeemed,
  /// 退款处理中（refund_requested）
  refundRequested,
  /// 已退款
  refunded,
  /// 已取消 / 过期（DB 或展示）
  cancelled,
  /// 展示用：券已过期、未满 24h
  expired,
  /// 展示用：过期 ≥24h、待自动退款
  pendingRefund,

  /// Stripe 退款失败
  refundFailed,

  /// 管理员拒绝退款（详情页标签，主状态仍为 paid）
  refundRejected;

  /// 从数据库字符串值映射
  factory OrderStatus.fromString(String value) {
    switch (value.toLowerCase()) {
      case 'unused':
      case 'paid':
        return OrderStatus.paid;
      case 'used':
      case 'redeemed':
        return OrderStatus.redeemed;
      case 'refund_requested':
        return OrderStatus.refundRequested;
      case 'refunded':
        return OrderStatus.refunded;
      case 'refund_failed':
        return OrderStatus.refundFailed;
      case 'expired':
      case 'cancelled':
        return OrderStatus.cancelled;
      default:
        return OrderStatus.paid;
    }
  }

  /// UI 展示文本
  String get displayLabel {
    switch (this) {
      case OrderStatus.paid:
        return 'Paid';
      case OrderStatus.redeemed:
        return 'Redeemed';
      case OrderStatus.refundRequested:
        return 'Refund Requested';
      case OrderStatus.refunded:
        return 'Refunded';
      case OrderStatus.cancelled:
        return 'Cancelled';
      case OrderStatus.expired:
        return 'Expired';
      case OrderStatus.pendingRefund:
        return 'Pending Refund';
      case OrderStatus.refundFailed:
        return 'Refund Failed';
      case OrderStatus.refundRejected:
        return 'Refund Rejected';
    }
  }

  /// 根据原始状态 + 券过期时间计算展示用状态（未使用且已过期 → Expired / Pending Refund）
  static OrderStatus displayStatus(OrderStatus raw, DateTime? couponExpiresAt) {
    if (raw != OrderStatus.paid) return raw;
    if (couponExpiresAt == null) return OrderStatus.paid;
    final now = DateTime.now();
    if (now.isBefore(couponExpiresAt)) return OrderStatus.paid;
    final elapsed = now.difference(couponExpiresAt);
    if (elapsed >= const Duration(hours: 24)) return OrderStatus.pendingRefund;
    return OrderStatus.expired;
  }

  /// Tab 标签文本（All 单独处理）
  static String tabLabel(OrderStatus? status) {
    if (status == null) return 'All';
    return status.displayLabel;
  }

  /// 状态对应颜色（Badge 颜色）
  Color get badgeColor {
    switch (this) {
      case OrderStatus.paid:
        return const Color(0xFF3B82F6); // 蓝色
      case OrderStatus.redeemed:
        return const Color(0xFF10B981); // 绿色
      case OrderStatus.refundRequested:
        return const Color(0xFFEF4444); // 红色
      case OrderStatus.refunded:
        return const Color(0xFFF59E0B); // 橙色
      case OrderStatus.cancelled:
        return const Color(0xFF9CA3AF); // 灰色
      case OrderStatus.expired:
        return const Color(0xFFDC2626); // 红
      case OrderStatus.pendingRefund:
        return const Color(0xFFD97706); // 琥珀
      case OrderStatus.refundFailed:
        return const Color(0xFFDC2626); // 红
      case OrderStatus.refundRejected:
        return const Color(0xFFF59E0B); // 琥珀
    }
  }

  /// 状态对应背景颜色（浅色）
  Color get badgeBackground {
    switch (this) {
      case OrderStatus.paid:
        return const Color(0xFFEFF6FF);
      case OrderStatus.redeemed:
        return const Color(0xFFECFDF5);
      case OrderStatus.refundRequested:
        return const Color(0xFFFEF2F2);
      case OrderStatus.refunded:
        return const Color(0xFFFFFBEB);
      case OrderStatus.cancelled:
        return const Color(0xFFF3F4F6);
      case OrderStatus.expired:
        return const Color(0xFFFEF2F2);
      case OrderStatus.pendingRefund:
        return const Color(0xFFFFFBEB);
      case OrderStatus.refundFailed:
        return const Color(0xFFFEF2F2);
      case OrderStatus.refundRejected:
        return const Color(0xFFFFFBEB);
    }
  }
}

// =============================================================
// TimelineEvent — 时间线单个事件
// =============================================================

/// 订单时间线中的单个事件节点
class TimelineEvent {
  /// 事件类型：purchased / redeemed / refund_requested / refunded
  final String event;

  /// 事件发生时间（可能为 null，表示事件尚未发生）
  final DateTime? timestamp;

  /// 是否已完成（已发生）
  final bool completed;

  const TimelineEvent({
    required this.event,
    this.timestamp,
    required this.completed,
  });

  /// 从 JSON 构造（Edge Function 返回格式）
  factory TimelineEvent.fromJson(Map<String, dynamic> json) {
    return TimelineEvent(
      event: json['event'] as String,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
      completed: json['completed'] as bool? ?? false,
    );
  }

  /// UI 展示标题
  String get displayTitle {
    switch (event) {
      case 'purchased':
        return 'Order Placed';
      case 'redeemed':
        return 'Voucher Redeemed';
      case 'refund_requested':
        return 'Refund Requested';
      case 'refunded':
        return 'Refunded';
      default:
        return event;
    }
  }

  /// UI 副标题（说明文字）
  String get displaySubtitle {
    switch (event) {
      case 'purchased':
        return 'Customer completed payment';
      case 'redeemed':
        return 'Voucher scanned and confirmed';
      case 'refund_requested':
        return 'Customer requested a refund';
      case 'refunded':
        return 'Automatically refunded by DealJoy';
      default:
        return '';
    }
  }

  /// 图标
  IconData get icon {
    switch (event) {
      case 'purchased':
        return Icons.shopping_bag_outlined;
      case 'redeemed':
        return Icons.check_circle_outline_rounded;
      case 'refund_requested':
        return Icons.hourglass_empty_rounded;
      case 'refunded':
        return Icons.currency_exchange_rounded;
      default:
        return Icons.circle_outlined;
    }
  }

  /// 图标颜色
  Color get iconColor {
    switch (event) {
      case 'purchased':
        return const Color(0xFF3B82F6);
      case 'redeemed':
        return const Color(0xFF10B981);
      case 'refund_requested':
        return const Color(0xFFF59E0B);
      case 'refunded':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF9CA3AF);
    }
  }
}

// =============================================================
// OrderTimeline — 完整时间线
// =============================================================

/// 订单完整时间线（包含所有事件节点列表）
class OrderTimeline {
  final List<TimelineEvent> events;

  const OrderTimeline({required this.events});

  factory OrderTimeline.fromJsonList(List<dynamic> list) {
    return OrderTimeline(
      events: list
          .map((e) => TimelineEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// =============================================================
// MerchantOrderItem — order_items 子项数据模型（V3）
// =============================================================

/// 订单详情中的子项（每行=一张券）
class MerchantOrderItem {
  /// order_items 表的主键
  final String orderItemId;

  /// 所属订单 ID
  final String orderId;

  /// Deal 标题
  final String dealTitle;

  /// Deal ID
  final String dealId;

  /// 单价
  final double unitPrice;

  /// 手续费
  final double serviceFee;

  /// 用户侧状态（unused / used / refunded 等）
  final String customerStatus;

  /// 商家侧状态（active / redeemed / refunded 等）
  final String merchantStatus;

  /// 优惠券码
  final String? couponCode;

  /// 优惠券状态
  final String? couponStatus;

  /// 券过期时间
  final DateTime? couponExpiresAt;

  /// 核销时间
  final DateTime? couponRedeemedAt;

  const MerchantOrderItem({
    required this.orderItemId,
    required this.orderId,
    required this.dealTitle,
    required this.dealId,
    required this.unitPrice,
    required this.serviceFee,
    required this.customerStatus,
    required this.merchantStatus,
    this.couponCode,
    this.couponStatus,
    this.couponExpiresAt,
    this.couponRedeemedAt,
  });

  /// 从 Edge Function 返回的 JSON 构造（null-safe）
  factory MerchantOrderItem.fromJson(Map<String, dynamic> json) {
    return MerchantOrderItem(
      orderItemId: json['order_item_id'] as String? ?? json['id'] as String? ?? '',
      orderId: json['order_id'] as String? ?? '',
      dealTitle: json['deal_title'] as String? ?? '',
      dealId: json['deal_id'] as String? ?? '',
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      serviceFee: (json['service_fee'] as num?)?.toDouble() ?? 0.0,
      customerStatus: json['customer_status'] as String? ?? 'unused',
      merchantStatus: json['merchant_status'] as String? ?? 'active',
      couponCode: json['coupon_code'] as String?,
      couponStatus: json['coupon_status'] as String?,
      couponExpiresAt: json['coupon_expires_at'] != null
          ? DateTime.parse(json['coupon_expires_at'] as String)
          : null,
      couponRedeemedAt: json['coupon_redeemed_at'] != null
          ? DateTime.parse(json['coupon_redeemed_at'] as String)
          : null,
    );
  }

  /// 从 customer_status 解析 OrderStatus（用于展示）
  OrderStatus get orderStatus =>
      OrderStatus.fromString(customerStatus);
}

// =============================================================
// MerchantOrder — 订单列表项数据模型
// =============================================================

/// 订单列表中单条订单数据
/// V3 适配：列表接口按 order_items 维度返回（每行=一张券）
class MerchantOrder {
  /// order_items 主键（V3 新增，列表维度唯一标识）
  final String? orderItemId;

  /// orders 表 ID
  final String id;

  /// 可读订单号，例如 DJ-ABCD1234
  final String orderNumber;

  /// 用户展示名（脱敏：只有 first name）
  final String userName;

  /// Deal 标题
  final String dealTitle;

  /// Deal ID
  final String dealId;

  /// 购买数量
  final int quantity;

  /// 单价
  final double unitPrice;

  /// 手续费（V3 新增）
  final double serviceFee;

  /// 总金额
  final double totalAmount;

  /// 用户侧状态（V3：对应 customer_status；向后兼容也读旧 status 字段）
  final OrderStatus status;

  /// 商家侧原始状态字符串（V3 新增）
  final String? merchantStatus;

  /// 优惠券码（已核销或已退款时才有值）
  final String? couponCode;

  /// 优惠券状态
  final String? couponStatus;

  /// 核销时间
  final DateTime? couponRedeemedAt;

  /// 券过期时间（列表接口返回，用于展示 Expired / Pending Refund）
  final DateTime? couponExpiresAt;

  /// 退款原因
  final String? refundReason;

  /// 创建时间
  final DateTime createdAt;

  /// 退款申请时间
  final DateTime? refundRequestedAt;

  /// 退款完成时间
  final DateTime? refundedAt;

  /// 管理员拒绝退款时间（详情页展示 Refund Rejected 标签）
  final DateTime? refundRejectedAt;

  const MerchantOrder({
    this.orderItemId,
    required this.id,
    required this.orderNumber,
    required this.userName,
    required this.dealTitle,
    required this.dealId,
    required this.quantity,
    required this.unitPrice,
    this.serviceFee = 0.0,
    required this.totalAmount,
    required this.status,
    this.merchantStatus,
    this.couponCode,
    this.couponStatus,
    this.couponRedeemedAt,
    this.couponExpiresAt,
    this.refundReason,
    required this.createdAt,
    this.refundRequestedAt,
    this.refundedAt,
    this.refundRejectedAt,
  });

  /// 展示用状态（未使用且已过期时显示 Expired / Pending Refund）
  OrderStatus get displayStatus =>
      OrderStatus.displayStatus(status, couponExpiresAt);

  /// 订单详情页：多个状态标签列表（如 [Paid, Expired]、[Paid, Refund Rejected]）
  List<OrderStatus> get detailStatusTags {
    if (status == OrderStatus.refundFailed) return [OrderStatus.refundFailed];
    if (status != OrderStatus.paid) return [status];
    final tags = <OrderStatus>[OrderStatus.paid];
    if (refundRejectedAt != null) tags.add(OrderStatus.refundRejected);
    if (couponExpiresAt == null) return tags;
    final now = DateTime.now();
    if (now.isBefore(couponExpiresAt!)) return tags;
    final elapsed = now.difference(couponExpiresAt!);
    if (elapsed >= const Duration(hours: 24)) {
      tags.add(OrderStatus.pendingRefund);
    } else {
      tags.add(OrderStatus.expired);
    }
    return tags;
  }

  /// 从 Edge Function / 数据库函数返回的 JSON 构造
  /// V3 适配：优先读 order_item_id / customer_status，向后兼容旧 status/user_display_name 字段
  factory MerchantOrder.fromJson(Map<String, dynamic> json) {
    // V3：order_id 是订单 ID，order_item_id 是券行 ID；旧版 id 直接是订单 ID
    final orderId = json['order_id'] as String? ?? json['id'] as String? ?? '';
    final orderItemId = json['order_item_id'] as String?;

    // V3 customer_status 优先，向后兼容旧 status 字段
    final rawStatus = json['customer_status'] as String?
        ?? json['status'] as String?
        ?? 'unused';

    // V3 user_name 优先，向后兼容旧 user_display_name
    final userName = json['user_name'] as String?
        ?? json['user_display_name'] as String?
        ?? 'Customer';

    return MerchantOrder(
      orderItemId: orderItemId,
      id: orderId,
      orderNumber: json['order_number'] as String? ?? 'DJ-????????',
      userName: userName,
      dealTitle: json['deal_title'] as String? ?? '',
      dealId: json['deal_id'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      serviceFee: (json['service_fee'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      status: OrderStatus.fromString(rawStatus),
      merchantStatus: json['merchant_status'] as String?,
      couponCode: json['coupon_code'] as String?,
      couponStatus: json['coupon_status'] as String?,
      couponRedeemedAt: json['coupon_redeemed_at'] != null
          ? DateTime.parse(json['coupon_redeemed_at'] as String)
          : null,
      couponExpiresAt: json['coupon_expires_at'] != null
          ? DateTime.parse(json['coupon_expires_at'] as String)
          : null,
      refundReason: json['refund_reason'] as String?,
      createdAt: DateTime.parse(
          json['created_at'] as String? ?? DateTime.now().toIso8601String()),
      refundRequestedAt: json['refund_requested_at'] != null
          ? DateTime.parse(json['refund_requested_at'] as String)
          : null,
      refundedAt: json['refunded_at'] != null
          ? DateTime.parse(json['refunded_at'] as String)
          : null,
      refundRejectedAt: json['refund_rejected_at'] != null
          ? DateTime.parse(json['refund_rejected_at'] as String)
          : null,
    );
  }
}

// =============================================================
// MerchantOrderDetail — 订单详情数据模型（含时间线）
// =============================================================

/// 订单详情（包含所有展示信息、子项列表和时间线）
/// V3 适配：新增 items / itemsAmount / serviceFeeTotal / customerEmail 字段
/// handleDetail 响应结构: { order: {..., items: [...], timeline: [...]}, customer: {...} }
class MerchantOrderDetail extends MerchantOrder {
  /// Deal 原始定价
  final double dealOriginalPrice;

  /// Deal 折扣价
  final double dealDiscountPrice;

  /// 支付意图 ID（脱敏显示）
  final String? paymentIntentIdMasked;

  /// 支付状态（来自 payments 表）
  final String? paymentStatus;

  /// 退款金额（如有）
  final double? refundAmount;

  /// 完整时间线
  final OrderTimeline timeline;

  /// 订单子项列表（V3：每行=一张券）
  final List<MerchantOrderItem> items;

  /// 商品金额小计（items_amount，V3 新增）
  final double itemsAmount;

  /// 平台手续费合计（service_fee_total，V3 新增）
  final double serviceFeeTotal;

  /// 客户邮箱（V3 customer 对象新增）
  final String? customerEmail;

  const MerchantOrderDetail({
    super.orderItemId,
    required super.id,
    required super.orderNumber,
    required super.userName,
    required super.dealTitle,
    required super.dealId,
    required super.quantity,
    required super.unitPrice,
    super.serviceFee = 0.0,
    required super.totalAmount,
    required super.status,
    super.merchantStatus,
    super.couponCode,
    super.couponStatus,
    super.couponRedeemedAt,
    super.couponExpiresAt,
    super.refundReason,
    required super.createdAt,
    super.refundRequestedAt,
    super.refundedAt,
    super.refundRejectedAt,
    required this.dealOriginalPrice,
    required this.dealDiscountPrice,
    this.paymentIntentIdMasked,
    this.paymentStatus,
    this.refundAmount,
    required this.timeline,
    this.items = const [],
    this.itemsAmount = 0.0,
    this.serviceFeeTotal = 0.0,
    this.customerEmail,
  });

  /// 从 Edge Function 返回的详情 JSON 构造
  /// 兼容 V3 新结构 { order: {...}, customer: {...} } 和旧结构（order 为顶层）
  factory MerchantOrderDetail.fromJson(Map<String, dynamic> json) {
    // V3 结构：顶层有 order 和 customer 两个 key
    final orderJson = json['order'] as Map<String, dynamic>? ?? json;
    final customerJson = json['customer'] as Map<String, dynamic>?;

    final timelineJson = orderJson['timeline'] as List<dynamic>? ?? [];

    // V3 items 列表
    final itemsJson = orderJson['items'] as List<dynamic>? ?? [];
    final items = itemsJson
        .map((e) => MerchantOrderItem.fromJson(e as Map<String, dynamic>))
        .toList();

    // 用户名：V3 customer.name 优先，再回退旧字段
    final userName = customerJson?['name'] as String?
        ?? orderJson['user_display_name'] as String?
        ?? 'Customer';

    // 状态：优先读 customer_status，兼容旧 status
    final rawStatus = orderJson['customer_status'] as String?
        ?? orderJson['status'] as String?
        ?? 'unused';

    // 单价/数量：V3 可能没有这两个字段，用 items 推算
    final unitPrice = (orderJson['unit_price'] as num?)?.toDouble()
        ?? (items.isNotEmpty ? items.first.unitPrice : 0.0);
    final quantity = (orderJson['quantity'] as num?)?.toInt()
        ?? items.length;

    return MerchantOrderDetail(
      id: orderJson['id'] as String? ?? '',
      orderNumber: orderJson['order_number'] as String? ?? 'DJ-????????',
      userName: userName,
      customerEmail: customerJson?['email'] as String?,
      dealTitle: orderJson['deal_title'] as String?
          ?? (items.isNotEmpty ? items.first.dealTitle : ''),
      dealId: orderJson['deal_id'] as String?
          ?? (items.isNotEmpty ? items.first.dealId : ''),
      quantity: quantity,
      unitPrice: unitPrice,
      serviceFee: (orderJson['service_fee'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (orderJson['total_amount'] as num?)?.toDouble() ?? 0.0,
      status: OrderStatus.fromString(rawStatus),
      merchantStatus: orderJson['merchant_status'] as String?,
      couponCode: orderJson['coupon_code'] as String?
          ?? (items.isNotEmpty ? items.first.couponCode : null),
      couponStatus: orderJson['coupon_status'] as String?
          ?? (items.isNotEmpty ? items.first.couponStatus : null),
      couponRedeemedAt: orderJson['coupon_redeemed_at'] != null
          ? DateTime.parse(orderJson['coupon_redeemed_at'] as String)
          : (items.isNotEmpty ? items.first.couponRedeemedAt : null),
      refundReason: orderJson['refund_reason'] as String?,
      createdAt: DateTime.parse(
          orderJson['created_at'] as String? ?? DateTime.now().toIso8601String()),
      refundRequestedAt: orderJson['refund_requested_at'] != null
          ? DateTime.parse(orderJson['refund_requested_at'] as String)
          : null,
      refundedAt: orderJson['refunded_at'] != null
          ? DateTime.parse(orderJson['refunded_at'] as String)
          : null,
      refundRejectedAt: orderJson['refund_rejected_at'] != null
          ? DateTime.parse(orderJson['refund_rejected_at'] as String)
          : null,
      dealOriginalPrice:
          (orderJson['deal_original_price'] as num?)?.toDouble() ?? 0.0,
      dealDiscountPrice:
          (orderJson['deal_discount_price'] as num?)?.toDouble() ?? 0.0,
      paymentIntentIdMasked:
          orderJson['payment_intent_id_masked'] as String?,
      paymentStatus: orderJson['payment_status'] as String?,
      refundAmount: (orderJson['refund_amount'] as num?)?.toDouble(),
      couponExpiresAt: orderJson['coupon_expires_at'] != null
          ? DateTime.parse(orderJson['coupon_expires_at'] as String)
          : (items.isNotEmpty ? items.first.couponExpiresAt : null),
      timeline: OrderTimeline.fromJsonList(timelineJson),
      items: items,
      itemsAmount: (orderJson['items_amount'] as num?)?.toDouble() ?? 0.0,
      serviceFeeTotal: (orderJson['service_fee_total'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// =============================================================
// OrderFilter — 筛选条件数据类
// =============================================================

/// 订单列表筛选条件（不可变，通过 copyWith 更新）
class OrderFilter {
  /// 状态筛选（null = All）
  final OrderStatus? status;

  /// 开始日期（可选）
  final DateTime? dateFrom;

  /// 结束日期（可选）
  final DateTime? dateTo;

  /// 指定 Deal ID（可选）
  final String? dealId;

  /// Deal 标题（用于 UI 展示，不传给 API）
  final String? dealTitle;

  const OrderFilter({
    this.status,
    this.dateFrom,
    this.dateTo,
    this.dealId,
    this.dealTitle,
  });

  /// 是否有除状态 tab 之外的附加筛选条件
  bool get hasExtraFilter =>
      dateFrom != null || dateTo != null || dealId != null;

  /// copyWith 支持清除字段
  OrderFilter copyWith({
    OrderStatus? status,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? dealId,
    String? dealTitle,
    bool clearStatus = false,
    bool clearDateFrom = false,
    bool clearDateTo = false,
    bool clearDeal = false,
  }) {
    return OrderFilter(
      status: clearStatus ? null : (status ?? this.status),
      dateFrom: clearDateFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateTo ? null : (dateTo ?? this.dateTo),
      dealId: clearDeal ? null : (dealId ?? this.dealId),
      dealTitle: clearDeal ? null : (dealTitle ?? this.dealTitle),
    );
  }

  /// 清除所有筛选（保留 status tab）
  OrderFilter clearExtra() {
    return OrderFilter(status: status);
  }

  /// 生成状态字符串（传给 API 的 status 参数）
  String? get statusParam {
    if (status == null) return null;
    switch (status!) {
      case OrderStatus.paid:
        return 'unused'; // 数据库中 paid 对应 unused
      case OrderStatus.redeemed:
        return 'used';
      case OrderStatus.refundRequested:
        return 'refund_requested';
      case OrderStatus.refunded:
        return 'refunded';
      case OrderStatus.refundFailed:
        return 'refund_failed';
      case OrderStatus.cancelled:
        return 'expired';
      case OrderStatus.expired:
      case OrderStatus.pendingRefund:
      case OrderStatus.refundRejected:
        // 展示用状态，筛选用 DB 的 unused
        return 'unused';
    }
  }

  /// 格式化日期范围显示文本
  String get dateRangeLabel {
    if (dateFrom == null && dateTo == null) return 'Date Range';
    final fromStr = dateFrom != null
        ? '${dateFrom!.month}/${dateFrom!.day}/${dateFrom!.year}'
        : '...';
    final toStr = dateTo != null
        ? '${dateTo!.month}/${dateTo!.day}/${dateTo!.year}'
        : '...';
    return '$fromStr – $toStr';
  }
}
