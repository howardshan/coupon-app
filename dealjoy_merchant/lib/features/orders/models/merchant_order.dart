// 订单管理数据模型
// 包含: MerchantOrder、OrderStatus、OrderTimeline、TimelineEvent、OrderFilter

import 'package:flutter/material.dart';

// =============================================================
// OrderStatus — 订单状态枚举
// =============================================================

/// 订单状态（与数据库 order_status enum 映射 + 展示用 expired / pendingRefund）
enum OrderStatus {
  /// 未使用
  unused,
  /// 已支付/已结算
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
        return OrderStatus.unused;
      case 'used':
      case 'redeemed':
      case 'unpaid':
        return OrderStatus.redeemed; // 已核销（待结算）
      case 'pending':
        return OrderStatus.pendingRefund; // 结算处理中（复用 pendingRefund 枚举）
      case 'paid':
        return OrderStatus.paid; // 已结算
      case 'refund_requested':
      case 'refund_request':
      case 'refund_pending':
      case 'refund_review':
        return OrderStatus.refundRequested;
      case 'refunded':
      case 'refund_success':
        return OrderStatus.refunded;
      case 'refund_failed':
      case 'refund_reject':
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
      case OrderStatus.unused:
        return 'Unused';
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
    if (raw != OrderStatus.unused && raw != OrderStatus.paid) return raw;
    if (raw == OrderStatus.paid) return OrderStatus.paid;
    // unused 券检查是否过期
    if (couponExpiresAt == null) return OrderStatus.unused;
    final now = DateTime.now();
    if (now.isBefore(couponExpiresAt)) return OrderStatus.unused;
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
      case OrderStatus.unused:
        return const Color(0xFF6366F1); // 靛蓝色
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
      case OrderStatus.unused:
        return const Color(0xFFEEF2FF); // 靛蓝浅色
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

  /// Deal 原价
  final double dealOriginalPrice;

  /// Deal 折扣价
  final double dealDiscountPrice;

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

  /// Deal 原价（来自 deals.original_price）
  final double dealOriginalPrice;

  /// Deal 折扣价（来自 deals.discount_price）
  final double dealDiscountPrice;

  const MerchantOrderItem({
    required this.orderItemId,
    required this.orderId,
    required this.dealTitle,
    required this.dealId,
    this.dealOriginalPrice = 0.0,
    this.dealDiscountPrice = 0.0,
    required this.unitPrice,
    required this.serviceFee,
    required this.customerStatus,
    required this.merchantStatus,
    this.dealOriginalPrice = 0.0,
    this.dealDiscountPrice = 0.0,
    this.couponCode,
    this.couponStatus,
    this.couponExpiresAt,
    this.couponRedeemedAt,
    this.refundReason,
    this.refundAmount,
  });

  /// 从 Edge Function 返回的 JSON 构造（null-safe）
  factory MerchantOrderItem.fromJson(Map<String, dynamic> json) {
    return MerchantOrderItem(
      orderItemId: json['order_item_id'] as String? ?? json['id'] as String? ?? '',
      orderId: json['order_id'] as String? ?? '',
      dealTitle: json['deal_title'] as String? ?? '',
      dealId: json['deal_id'] as String? ?? '',
      dealOriginalPrice: (json['deal_original_price'] as num?)?.toDouble() ?? 0.0,
      dealDiscountPrice: (json['deal_discount_price'] as num?)?.toDouble() ?? 0.0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      serviceFee: (json['service_fee'] as num?)?.toDouble() ?? 0.0,
      customerStatus: json['customer_status'] as String? ?? 'unused',
      merchantStatus: json['merchant_status'] as String? ?? 'active',
      dealOriginalPrice: (json['deal_original_price'] as num?)?.toDouble() ?? 0.0,
      dealDiscountPrice: (json['deal_discount_price'] as num?)?.toDouble() ?? 0.0,
      couponCode: json['coupon_code'] as String?,
      couponStatus: json['coupon_status'] as String?,
      couponExpiresAt: json['coupon_expires_at'] != null
          ? DateTime.parse(json['coupon_expires_at'] as String)
          : null,
      couponRedeemedAt: json['coupon_redeemed_at'] != null
          ? DateTime.parse(json['coupon_redeemed_at'] as String)
          : null,
      refundReason: json['refund_reason'] as String?,
      refundAmount: (json['refund_amount'] as num?)?.toDouble(),
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
/// V4: 以 order 为维度，聚合当前商家的 items 信息
class MerchantOrder {
  /// orders 表 ID
  final String id;

  /// 可读订单号，例如 DJ-ABCD1234
  final String orderNumber;

  /// 用户展示名（脱敏：只有 first name）
  final String userName;

  /// 属于当前商家的 deal 标题列表（去重）
  final List<String> dealTitles;

  /// 属于当前商家的 items 数量（券张数）
  final int itemCount;

  /// 商家专属金额合计（仅本商家的 items 单价之和）
  final double merchantTotal;

  /// 主状态（items 中最需关注的状态）
  final OrderStatus status;

  /// 券过期时间（unused items 中最早的，用于展示 Expired / Pending Refund）
  final DateTime? couponExpiresAt;

  /// 创建时间
  final DateTime createdAt;

  const MerchantOrder({
    required this.id,
    required this.orderNumber,
    required this.userName,
    required this.dealTitles,
    required this.itemCount,
    required this.merchantTotal,
    required this.status,
    this.couponExpiresAt,
    required this.createdAt,
  });

  /// 展示用状态（未使用且已过期时显示 Expired / Pending Refund）
  OrderStatus get displayStatus =>
      OrderStatus.displayStatus(status, couponExpiresAt);

  /// Deal 摘要文本（列表卡片展示用）
  String get dealSummary {
    if (dealTitles.isEmpty) return '';
    if (dealTitles.length == 1) return dealTitles.first;
    return '${dealTitles.first} +${dealTitles.length - 1} more';
  }

  /// 从 V4 Edge Function 返回的 JSON 构造（order 维度）
  factory MerchantOrder.fromJson(Map<String, dynamic> json) {
    final orderId = json['order_id'] as String? ?? json['id'] as String? ?? '';

    final rawStatus = json['customer_status'] as String?
        ?? json['status'] as String?
        ?? 'unused';

    final userName = json['user_name'] as String?
        ?? json['user_display_name'] as String?
        ?? 'Customer';

    // deal_titles 可能是 List<dynamic> 或不存在
    final rawTitles = json['deal_titles'] as List<dynamic>?;
    final dealTitles = rawTitles?.map((e) => e.toString()).toList()
        ?? [json['deal_title'] as String? ?? ''];

    return MerchantOrder(
      id: orderId,
      orderNumber: json['order_number'] as String? ?? 'DJ-????????',
      userName: userName,
      dealTitles: dealTitles,
      itemCount: (json['item_count'] as num?)?.toInt()
          ?? (json['quantity'] as num?)?.toInt()
          ?? 1,
      merchantTotal: (json['merchant_total'] as num?)?.toDouble()
          ?? (json['total_amount'] as num?)?.toDouble()
          ?? 0.0,
      status: OrderStatus.fromString(rawStatus),
      couponExpiresAt: json['coupon_expires_at'] != null
          ? DateTime.parse(json['coupon_expires_at'] as String)
          : null,
      createdAt: DateTime.parse(
          json['created_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }
}

// =============================================================
// MerchantOrderDetail — 订单详情数据模型（独立类，不继承 MerchantOrder）
// =============================================================

/// 订单详情（包含所有展示信息、子项列表和时间线）
/// V4: 独立类，商家专属金额，items 列表展示每张券状态
/// handleDetail 响应结构: { order: {...}, items: [...], customer: {...} }
class MerchantOrderDetail {
  /// orders 表 ID
  final String id;

  /// 可读订单号
  final String orderNumber;

  /// 用户展示名（脱敏）
  final String userName;

  /// 客户邮箱
  final String? customerEmail;

  /// 商家专属总金额（items_amount + service_fee_total）
  final double merchantTotal;

  /// 商品金额小计（仅本商家的 items）
  final double itemsAmount;

  /// 平台手续费合计
  final double serviceFeeTotal;

  /// 订单子项列表（每行=一张券，仅属于本商家）
  final List<MerchantOrderItem> items;

  /// 完整时间线
  final OrderTimeline timeline;

  /// 创建时间
  final DateTime createdAt;

  /// 支付时间
  final DateTime? paidAt;

  /// Store Credit 抵扣金额（>0 表示用了 Store Credit）
  final double storeCreditUsed;

  const MerchantOrderDetail({
    required this.id,
    required this.orderNumber,
    required this.userName,
    this.customerEmail,
    required this.merchantTotal,
    this.itemsAmount = 0.0,
    this.serviceFeeTotal = 0.0,
    this.customerEmail,
    this.storeCreditUsed = 0.0,
  });

  /// 计算主状态（从 items 中推导）
  OrderStatus get primaryStatus {
    if (items.isEmpty) return OrderStatus.unused;
    // 取最需关注的状态
    const priority = {
      'refund_review': 7,
      'refund_pending': 6,
      'refund_reject': 5,
      'unused': 4,
      'used': 3,
      'paid': 2,
      'refund_success': 1,
    };
    int maxP = -1;
    OrderStatus primary = OrderStatus.unused;
    for (final item in items) {
      final p = priority[item.customerStatus] ?? 0;
      if (p > maxP) {
        maxP = p;
        primary = item.orderStatus;
      }
    }
    return primary;
  }

  /// 从 V4 Edge Function 返回的详情 JSON 构造
  /// 结构: { order: {...}, items: [...], customer: {...} }
  factory MerchantOrderDetail.fromJson(Map<String, dynamic> json) {
    // V4 结构：顶层有 order, items, customer 三个 key
    final orderJson = json['order'] as Map<String, dynamic>? ?? json;
    final customerJson = json['customer'] as Map<String, dynamic>?;

    final timelineJson = orderJson['timeline'] as List<dynamic>? ?? [];

    // V3 items 列表：Edge Function 将 items 放在顶层（json['items']），不在 order 内部
    final itemsJson = (json['items'] as List<dynamic>?)
        ?? (orderJson['items'] as List<dynamic>?)
        ?? [];
    final items = itemsJson
        .map((e) => MerchantOrderItem.fromJson(e as Map<String, dynamic>))
        .toList();

    // 用户名
    final userName = customerJson?['name'] as String?
        ?? orderJson['user_display_name'] as String?
        ?? 'Customer';

    // 商家专属金额
    final itemsAmount = (orderJson['items_amount'] as num?)?.toDouble() ?? 0.0;
    final serviceFeeTotal = (orderJson['service_fee_total'] as num?)?.toDouble() ?? 0.0;
    final merchantTotal = (orderJson['total_amount'] as num?)?.toDouble()
        ?? (itemsAmount + serviceFeeTotal);

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
      // merchant_total：该商家自己的应收总额（新字段）；旧订单回退 total_amount
      totalAmount: (orderJson['merchant_total'] as num?)?.toDouble()
          ?? (orderJson['total_amount'] as num?)?.toDouble()
          ?? 0.0,
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
      paidAt: orderJson['paid_at'] != null
          ? DateTime.parse(orderJson['paid_at'] as String)
          : null,
      refundRejectedAt: orderJson['refund_rejected_at'] != null
          ? DateTime.parse(orderJson['refund_rejected_at'] as String)
          : null,
      dealOriginalPrice: (orderJson['deal_original_price'] as num?)?.toDouble()
          ?? (items.isNotEmpty ? items.first.dealOriginalPrice : 0.0),
      // dealDiscountPrice：优先用 deals.discount_price，否则回退到实际支付单价
      dealDiscountPrice: (() {
        final fromDeal = (orderJson['deal_discount_price'] as num?)?.toDouble()
            ?? (items.isNotEmpty ? items.first.dealDiscountPrice : null);
        if (fromDeal != null && fromDeal > 0) return fromDeal;
        return unitPrice; // 用实际支付单价作为最终兜底
      })(),
      paymentIntentIdMasked:
          orderJson['payment_intent_id_masked'] as String?,
      paymentStatus: orderJson['payment_status'] as String?,
      refundAmount: (orderJson['refund_amount'] as num?)?.toDouble(),
      couponExpiresAt: orderJson['coupon_expires_at'] != null
          ? DateTime.parse(orderJson['coupon_expires_at'] as String)
          : (items.isNotEmpty ? items.first.couponExpiresAt : null),
      timeline: OrderTimeline.fromJsonList(timelineJson),
      items: items,
      itemsAmount: (orderJson['merchant_items_amount'] as num?)?.toDouble()
          ?? (orderJson['items_amount'] as num?)?.toDouble()
          ?? 0.0,
      serviceFeeTotal: (orderJson['merchant_service_fee'] as num?)?.toDouble()
          ?? (orderJson['service_fee_total'] as num?)?.toDouble()
          ?? 0.0,
      storeCreditUsed: (orderJson['store_credit_used'] as num?)?.toDouble() ?? 0.0,
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
      case OrderStatus.unused:
        return 'unused';
      case OrderStatus.paid:
        return 'paid';
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
