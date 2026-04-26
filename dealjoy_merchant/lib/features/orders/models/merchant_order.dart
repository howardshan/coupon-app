// 订单管理数据模型
// 包含: MerchantOrder、OrderStatus、OrderTimeline、TimelineEvent、OrderFilter

import 'package:flutter/material.dart';

// =============================================================
// OrderStatus — 订单状态枚举
// =============================================================

/// 订单状态枚举（4 种核心状态 + 3 种展示用状态）
enum OrderStatus {
  /// 券未用（customer_status=unused）
  unused,
  /// 已核销，待结算（customer_status=used, merchant_status=unpaid）
  redeemed,
  /// 已核销，已结算（customer_status=used, merchant_status=paid）
  settled,
  /// 已退款（customer_status=refund_success）
  refunded,
  /// 已赠送
  gifted,
  /// 展示用：券已过期、未满 24h
  expired,
  /// 展示用：过期 ≥24h、待自动退款
  pendingRefund;

  /// 从 customer_status + merchant_status 组合映射
  static OrderStatus fromCombined(String customerStatus, String merchantStatus) {
    switch (customerStatus) {
      case 'used':
      case 'redeemed':
        if (merchantStatus == 'paid') return OrderStatus.settled;
        return OrderStatus.redeemed;
      case 'refund_success':
      case 'refunded':
        return OrderStatus.refunded;
      case 'gifted':
        return OrderStatus.gifted;
      case 'unused':
      default:
        return OrderStatus.unused;
    }
  }

  /// 向后兼容：从单个状态字符串映射
  factory OrderStatus.fromString(String value) {
    switch (value.toLowerCase()) {
      case 'gifted':
        return OrderStatus.gifted;
      case 'unused':
        return OrderStatus.unused;
      case 'used':
      case 'redeemed':
      case 'unpaid':
        return OrderStatus.redeemed;
      case 'settled':
      case 'paid':
        return OrderStatus.settled;
      case 'refunded':
      case 'refund_success':
        return OrderStatus.refunded;
      case 'expired':
        return OrderStatus.expired;
      default:
        return OrderStatus.unused;
    }
  }

  /// 根据原始状态 + 券过期时间计算展示用状态
  static OrderStatus displayStatus(OrderStatus raw, DateTime? couponExpiresAt) {
    if (raw != OrderStatus.unused) return raw;
    if (couponExpiresAt == null) return OrderStatus.unused;
    final now = DateTime.now();
    if (now.isBefore(couponExpiresAt)) return OrderStatus.unused;
    final elapsed = now.difference(couponExpiresAt);
    if (elapsed >= const Duration(hours: 24)) return OrderStatus.pendingRefund;
    return OrderStatus.expired;
  }

  /// UI 展示文本
  String get displayLabel {
    switch (this) {
      case OrderStatus.unused:
        return 'Unused';
      case OrderStatus.redeemed:
        return 'Redeemed';
      case OrderStatus.settled:
        return 'Settled';
      case OrderStatus.refunded:
        return 'Refunded';
      case OrderStatus.gifted:
        return 'Gifted';
      case OrderStatus.expired:
        return 'Expired';
      case OrderStatus.pendingRefund:
        return 'Pending Refund';
    }
  }

  /// Tab 标签文本（All 单独处理）
  static String tabLabel(OrderStatus? status) {
    if (status == null) return 'All';
    return status.displayLabel;
  }

  /// Badge 文字颜色
  Color get badgeColor {
    switch (this) {
      case OrderStatus.unused:
        return const Color(0xFF6366F1); // 靛蓝色
      case OrderStatus.redeemed:
        return const Color(0xFF10B981); // 绿色
      case OrderStatus.settled:
        return const Color(0xFF3B82F6); // 蓝色
      case OrderStatus.refunded:
        return const Color(0xFFF59E0B); // 琥珀色
      case OrderStatus.gifted:
        return const Color(0xFF8B5CF6); // 紫色
      case OrderStatus.expired:
        return const Color(0xFFDC2626); // 红色
      case OrderStatus.pendingRefund:
        return const Color(0xFFD97706); // 深琥珀色
    }
  }

  /// Badge 背景颜色
  Color get badgeBackground {
    switch (this) {
      case OrderStatus.unused:
        return const Color(0xFFEEF2FF); // 靛蓝浅色
      case OrderStatus.redeemed:
        return const Color(0xFFECFDF5); // 绿色浅色
      case OrderStatus.settled:
        return const Color(0xFFEFF6FF); // 蓝色浅色
      case OrderStatus.refunded:
        return const Color(0xFFFFFBEB); // 琥珀浅色
      case OrderStatus.gifted:
        return const Color(0xFFF5F3FF); // 紫色浅色
      case OrderStatus.expired:
        return const Color(0xFFFEF2F2); // 红色浅色
      case OrderStatus.pendingRefund:
        return const Color(0xFFFFFBEB); // 琥珀浅色
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
        return 'Automatically refunded by Crunchy Plum';
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
// MerchantGiftEvent — 商家端订单详情赠礼时间线（脱敏）
// =============================================================

/// 单条赠礼事件（来自 merchant-orders gift_events）
class MerchantGiftEvent {
  final String kind;
  final DateTime at;
  final String? toHint;

  const MerchantGiftEvent({
    required this.kind,
    required this.at,
    this.toHint,
  });

  factory MerchantGiftEvent.fromJson(Map<String, dynamic> json) {
    return MerchantGiftEvent(
      kind: json['kind'] as String? ?? 'sent',
      at: DateTime.parse(json['at'] as String),
      toHint: json['to_hint'] as String?,
    );
  }

  bool get isRecalled => kind == 'recalled';
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

  /// 退款时间
  final DateTime? refundedAt;

  /// 退款原因
  final String? refundReason;

  /// 退款金额
  final double? refundAmount;

  /// 平台费费率（如 0.15 = 15%）
  final double platformFeeRate;

  /// 平台费金额
  final double platformFee;

  /// 品牌佣金费率（如 0.15 = 15%，非品牌 Deal 时为 0）
  final double brandFeeRate;

  /// 品牌佣金金额
  final double brandFee;

  /// Stripe 手续费
  final double stripeFee;

  /// 商家实收净额
  final double netAmount;

  /// 赠礼 / 收回事件（与退款块类似的多段展示）
  final List<MerchantGiftEvent> giftEvents;

  /// 已支付小费金额（USD，来自 merchant-orders `tip.amount_cents`）
  final double? tipAmountUsd;

  /// 小费支付时间
  final DateTime? tipPaidAt;

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
    this.couponCode,
    this.couponStatus,
    this.couponExpiresAt,
    this.couponRedeemedAt,
    this.refundedAt,
    this.refundReason,
    this.refundAmount,
    this.platformFeeRate = 0.0,
    this.platformFee = 0.0,
    this.brandFeeRate = 0.0,
    this.brandFee = 0.0,
    this.stripeFee = 0.0,
    this.netAmount = 0.0,
    this.giftEvents = const [],
    this.tipAmountUsd,
    this.tipPaidAt,
  });

  /// 从 Edge Function 返回的 JSON 构造（null-safe）
  factory MerchantOrderItem.fromJson(Map<String, dynamic> json) {
    final ge = json['gift_events'] as List<dynamic>?;
    final giftEvents = ge == null || ge.isEmpty
        ? const <MerchantGiftEvent>[]
        : ge
            .map((e) => MerchantGiftEvent.fromJson(e as Map<String, dynamic>))
            .toList();

    final tipObj = json['tip'] as Map<String, dynamic>?;
    double? tipUsd;
    DateTime? tipPaid;
    if (tipObj != null && tipObj['amount_cents'] != null) {
      tipUsd = (tipObj['amount_cents'] as num).toDouble() / 100.0;
    }
    if (tipObj != null && tipObj['paid_at'] != null) {
      tipPaid = DateTime.tryParse(tipObj['paid_at'] as String);
    }

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
      couponCode: json['coupon_code'] as String?,
      couponStatus: json['coupon_status'] as String?,
      couponExpiresAt: json['coupon_expires_at'] != null
          ? DateTime.parse(json['coupon_expires_at'] as String)
          : null,
      couponRedeemedAt: (json['coupon_redeemed_at'] ?? json['redeemed_at']) != null
          ? DateTime.parse((json['coupon_redeemed_at'] ?? json['redeemed_at']) as String)
          : null,
      refundedAt: json['refunded_at'] != null
          ? DateTime.parse(json['refunded_at'] as String)
          : null,
      refundReason: json['refund_reason'] as String?,
      refundAmount: (json['refund_amount'] as num?)?.toDouble(),
      platformFeeRate: (json['platform_fee_rate'] as num?)?.toDouble() ?? 0.0,
      platformFee: (json['platform_fee'] as num?)?.toDouble() ?? 0.0,
      brandFeeRate: (json['brand_fee_rate'] as num?)?.toDouble() ?? 0.0,
      brandFee: (json['brand_fee'] as num?)?.toDouble() ?? 0.0,
      stripeFee: (json['stripe_fee'] as num?)?.toDouble() ?? 0.0,
      netAmount: (json['net_amount'] as num?)?.toDouble() ?? 0.0,
      giftEvents: giftEvents,
      tipAmountUsd: tipUsd,
      tipPaidAt: tipPaid,
    );
  }

  /// 从 customer_status + merchant_status 组合解析 OrderStatus（用于展示）
  OrderStatus get orderStatus =>
      OrderStatus.fromCombined(customerStatus, merchantStatus);
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

  /// 商家侧主状态（从 merchant_status 字段取得）
  final String merchantStatusRaw;

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
    this.merchantStatusRaw = 'unused',
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

    // 商家侧状态（用于区分 redeemed 待结算 / settled 已结算）
    final rawMerchantStatus = json['merchant_status'] as String? ?? 'unused';

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
      merchantStatusRaw: rawMerchantStatus,
      status: OrderStatus.fromCombined(rawStatus, rawMerchantStatus),
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

  /// 平台费合计（从 items 汇总）
  final double totalPlatformFee;

  /// 品牌佣金合计（从 items 汇总，仅品牌 Deal 时 > 0）
  final double totalBrandFee;

  /// Stripe 手续费合计（从 items 汇总）
  final double totalStripeFee;

  /// 商家实收净额合计（从 items 汇总）
  final double totalNetAmount;

  /// 订单子项列表（每行=一张券，仅属于本商家）
  final List<MerchantOrderItem> items;

  /// 完整时间线
  final OrderTimeline timeline;

  /// 创建时间
  final DateTime createdAt;

  /// 支付时间
  final DateTime? paidAt;

  const MerchantOrderDetail({
    required this.id,
    required this.orderNumber,
    required this.userName,
    this.customerEmail,
    required this.merchantTotal,
    this.itemsAmount = 0.0,
    this.serviceFeeTotal = 0.0,
    this.totalPlatformFee = 0.0,
    this.totalBrandFee = 0.0,
    this.totalStripeFee = 0.0,
    this.totalNetAmount = 0.0,
    this.items = const [],
    required this.timeline,
    required this.createdAt,
    this.paidAt,
  });

  /// 计算主状态（从 items 中推导，取优先级最高的状态）
  OrderStatus get primaryStatus {
    if (items.isEmpty) return OrderStatus.unused;
    // 优先级：redeemed(待结算) > unused / gifted > refunded > settled
    const priority = {
      OrderStatus.redeemed: 5,
      OrderStatus.unused: 4,
      OrderStatus.gifted: 4,
      OrderStatus.refunded: 3,
      OrderStatus.settled: 2,
    };
    int maxP = -1;
    OrderStatus primary = OrderStatus.unused;
    for (final item in items) {
      final status = item.orderStatus;
      final p = priority[status] ?? 0;
      if (p > maxP) {
        maxP = p;
        primary = status;
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

    // items 列表（V4 在顶层，V3 在 order 内）
    final itemsJson = json['items'] as List<dynamic>?
        ?? orderJson['items'] as List<dynamic>?
        ?? [];
    final items = itemsJson
        .map((e) => MerchantOrderItem.fromJson(e as Map<String, dynamic>))
        .toList();

    // 用户名
    final userName = customerJson?['name'] as String?
        ?? orderJson['user_display_name'] as String?
        ?? 'Customer';

    // 商家专属金额（混合订单：Edge Function 返回 merchant_*；旧接口则从本页 items 汇总）
    final fromItemsSubtotal =
        items.fold<double>(0, (s, i) => s + i.unitPrice);
    final fromItemsServiceFee =
        items.fold<double>(0, (s, i) => s + i.serviceFee);

    final double itemsAmount;
    if (orderJson.containsKey('merchant_items_amount') &&
        orderJson['merchant_items_amount'] != null) {
      itemsAmount = (orderJson['merchant_items_amount'] as num).toDouble();
    } else if (items.isNotEmpty) {
      itemsAmount = fromItemsSubtotal;
    } else {
      itemsAmount = (orderJson['items_amount'] as num?)?.toDouble() ?? 0.0;
    }

    final double serviceFeeTotal;
    if (orderJson.containsKey('merchant_service_fee') &&
        orderJson['merchant_service_fee'] != null) {
      serviceFeeTotal = (orderJson['merchant_service_fee'] as num).toDouble();
    } else if (items.isNotEmpty) {
      serviceFeeTotal = fromItemsServiceFee;
    } else {
      serviceFeeTotal = (orderJson['service_fee_total'] as num?)?.toDouble() ?? 0.0;
    }

    final double merchantTotal;
    if (orderJson.containsKey('merchant_total') &&
        orderJson['merchant_total'] != null) {
      merchantTotal = (orderJson['merchant_total'] as num).toDouble();
    } else if (items.isNotEmpty) {
      merchantTotal = fromItemsSubtotal + fromItemsServiceFee;
    } else {
      merchantTotal = (orderJson['total_amount'] as num?)?.toDouble() ??
          (itemsAmount + serviceFeeTotal);
    }

    // 佣金明细汇总字段（Edge Function 返回，若无则默认 0）
    final totalPlatformFee = (orderJson['total_platform_fee'] as num?)?.toDouble() ?? 0.0;
    final totalBrandFee = (orderJson['total_brand_fee'] as num?)?.toDouble() ?? 0.0;
    final totalStripeFee = (orderJson['total_stripe_fee'] as num?)?.toDouble() ?? 0.0;
    final totalNetAmount = (orderJson['total_net_amount'] as num?)?.toDouble() ?? 0.0;

    return MerchantOrderDetail(
      id: orderJson['id'] as String? ?? '',
      orderNumber: orderJson['order_number'] as String? ?? 'DJ-????????',
      userName: userName,
      customerEmail: customerJson?['email'] as String?,
      merchantTotal: merchantTotal,
      itemsAmount: itemsAmount,
      serviceFeeTotal: serviceFeeTotal,
      totalPlatformFee: totalPlatformFee,
      totalBrandFee: totalBrandFee,
      totalStripeFee: totalStripeFee,
      totalNetAmount: totalNetAmount,
      items: items,
      timeline: OrderTimeline.fromJsonList(timelineJson),
      createdAt: DateTime.parse(
          orderJson['created_at'] as String? ?? DateTime.now().toIso8601String()),
      paidAt: orderJson['paid_at'] != null
          ? DateTime.parse(orderJson['paid_at'] as String)
          : null,
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

  /// 生成状态字符串（传给 API 的 display_status 参数）
  String? get statusParam {
    if (status == null) return null;
    switch (status!) {
      case OrderStatus.unused:
        return 'unused';
      case OrderStatus.redeemed:
        return 'redeemed';
      case OrderStatus.settled:
        return 'settled';
      case OrderStatus.refunded:
        return 'refunded';
      case OrderStatus.gifted:
      case OrderStatus.expired:
      case OrderStatus.pendingRefund:
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
