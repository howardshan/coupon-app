// 用户端订单详情模型（与 user-order-detail Edge Function 返回结构一致）
// V3 新增：items 字段，从 json['order']['items'] 解析 OrderItemModel 列表

import 'package:flutter/material.dart';
import 'order_item_model.dart';

// =============================================================
// TimelineEvent — 时间线单节点
// =============================================================

class TimelineEvent {
  final String event;
  final DateTime? timestamp;
  final bool completed;

  const TimelineEvent({
    required this.event,
    this.timestamp,
    required this.completed,
  });

  factory TimelineEvent.fromJson(Map<String, dynamic> json) {
    return TimelineEvent(
      event: json['event'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
      completed: json['completed'] as bool? ?? false,
    );
  }

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
      case 'voided':
        return 'Offer Updated';
      default:
        return event;
    }
  }

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
      case 'voided':
        return Icons.cancel_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  Color get iconColor {
    switch (event) {
      case 'purchased':
        return const Color(0xFF3B82F6);
      case 'redeemed':
        return const Color(0xFF10B981);
      case 'refund_requested':
      case 'refunded':
        return const Color(0xFFF59E0B);
      case 'voided':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF9CA3AF);
    }
  }
}

// =============================================================
// OrderTimeline
// =============================================================

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
// OrderDetailModel — 订单详情（API 返回结构）
// =============================================================

class OrderDetailModel {
  final String id;
  final String orderNumber;
  final String status;

  final String dealId;
  final String dealTitle;
  final double dealOriginalPrice;
  final double dealDiscountPrice;
  final String? dealImageUrl;
  final String? merchantName;

  final int quantity;
  final double unitPrice;
  final double totalAmount;
  /// 整单税费合计（快照，等于所有 items 的 tax_amount 之和）
  final double taxAmount;

  final String? paymentIntentIdMasked;
  final String? paymentStatus;
  final double? refundAmount;

  /// 本单使用的 Store Credit 金额（用于退款时判断混合支付）
  final double storeCreditUsed;

  final String? refundReason;

  final String? couponId;
  final String? couponCode;
  final String? couponStatus;
  final DateTime? couponExpiresAt;
  final DateTime? couponUsedAt;

  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? refundRequestedAt;
  final DateTime? refundedAt;
  final DateTime? refundRejectedAt;

  final OrderTimeline timeline;

  /// V3 新增：order items 列表，从 json['order']['items'] 或 json['items'] 解析
  final List<OrderItemModel> items;

  const OrderDetailModel({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.dealId,
    required this.dealTitle,
    required this.dealOriginalPrice,
    required this.dealDiscountPrice,
    this.dealImageUrl,
    this.merchantName,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    this.taxAmount = 0.0,
    this.paymentIntentIdMasked,
    this.paymentStatus,
    this.refundAmount,
    this.storeCreditUsed = 0.0,
    this.refundReason,
    this.couponId,
    this.couponCode,
    this.couponStatus,
    this.couponExpiresAt,
    this.couponUsedAt,
    required this.createdAt,
    this.updatedAt,
    this.refundRequestedAt,
    this.refundedAt,
    this.refundRejectedAt,
    required this.timeline,
    this.items = const [],
  });

  factory OrderDetailModel.fromJson(Map<String, dynamic> json) {
    final timelineJson = json['timeline'] as List<dynamic>? ?? [];

    // 辅助函数：同时尝试 snake_case 和 camelCase 字段名
    T? pick<T>(String snake, String camel) =>
        (json[snake] ?? json[camel]) as T?;
    DateTime? pickDate(String snake, String camel) {
      final v = json[snake] ?? json[camel];
      return v != null ? DateTime.tryParse(v as String) : null;
    }

    final orderNum = pick<String>('order_number', 'orderNumber') ?? '';
    // 订单级下单时间：item 缺 created_at 时回填，避免聚合页误用 DateTime.now()
    final orderCreatedRaw = json['created_at'] ?? json['createdAt'];
    // V3：解析 items；把订单号写入每条 item 便于聚合页按单展示
    final rawItems = json['items'] as List?;
    final items = rawItems
            ?.map((e) {
              final m = Map<String, dynamic>.from(e as Map<String, dynamic>);
              if (orderNum.isNotEmpty &&
                  m['order_number'] == null &&
                  m['orderNumber'] == null) {
                m['order_number'] = orderNum;
              }
              if (m['created_at'] == null &&
                  m['createdAt'] == null &&
                  orderCreatedRaw != null) {
                m['created_at'] = orderCreatedRaw;
              }
              return OrderItemModel.fromJson(m);
            })
            .toList() ??
        const <OrderItemModel>[];

    return OrderDetailModel(
      id: pick<String>('id', 'id') ?? '',
      orderNumber: orderNum,
      status: pick<String>('status', 'status') ?? 'unused',
      dealId: pick<String>('deal_id', 'dealId') ?? '',
      dealTitle: pick<String>('deal_title', 'dealTitle') ?? '',
      dealOriginalPrice: (pick<num>('deal_original_price', 'dealOriginalPrice'))?.toDouble() ?? 0.0,
      dealDiscountPrice: (pick<num>('deal_discount_price', 'dealDiscountPrice'))?.toDouble() ?? 0.0,
      dealImageUrl: pick<String>('deal_image_url', 'dealImageUrl'),
      merchantName: pick<String>('merchant_name', 'merchantName'),
      quantity: (pick<num>('quantity', 'quantity'))?.toInt() ?? 1,
      unitPrice: (pick<num>('unit_price', 'unitPrice'))?.toDouble() ?? 0.0,
      totalAmount: (pick<num>('total_amount', 'totalAmount'))?.toDouble() ?? 0.0,
      taxAmount: (pick<num>('tax_amount', 'taxAmount'))?.toDouble() ?? 0.0,
      paymentIntentIdMasked: pick<String>('payment_intent_id_masked', 'paymentIntentIdMasked'),
      paymentStatus: pick<String>('payment_status', 'paymentStatus'),
      refundAmount: (pick<num>('refund_amount', 'refundAmount'))?.toDouble(),
      storeCreditUsed: (pick<num>('store_credit_used', 'storeCreditUsed'))?.toDouble() ?? 0.0,
      refundReason: pick<String>('refund_reason', 'refundReason'),
      couponId: pick<String>('coupon_id', 'couponId'),
      couponCode: pick<String>('coupon_code', 'couponCode'),
      couponStatus: pick<String>('coupon_status', 'couponStatus'),
      couponExpiresAt: pickDate('coupon_expires_at', 'couponExpiresAt'),
      couponUsedAt: pickDate('coupon_used_at', 'couponUsedAt'),
      createdAt: pickDate('created_at', 'createdAt') ?? DateTime.now(),
      updatedAt: pickDate('updated_at', 'updatedAt'),
      refundRequestedAt: pickDate('refund_requested_at', 'refundRequestedAt'),
      refundedAt: pickDate('refunded_at', 'refundedAt'),
      refundRejectedAt: pickDate('refund_rejected_at', 'refundRejectedAt'),
      timeline: OrderTimeline.fromJsonList(timelineJson),
      items: items,
    );
  }

  bool get isRefunded => status == 'refunded';
  bool get isVoided => status == 'voided';
  bool get isRefundRequested => status == 'refund_requested';
  bool get isRefundFailed => status == 'refund_failed';
  bool get isUnused => status == 'unused';
  bool get isUsed => status == 'used';
  bool get isExpired => status == 'expired';
  bool get isRefundRejected => refundRejectedAt != null;
  bool get isExpiredByDate =>
      couponExpiresAt != null && DateTime.now().isAfter(couponExpiresAt!);

  /// 展示用状态（与商家端一致：已退款优先，再按过期/其他）
  bool get canRequestAfterSales {
    if (!isUsed || couponUsedAt == null) return false;
    final diff = DateTime.now().difference(couponUsedAt!);
    return diff.inDays <= 7;
  }

  String get displayStatus {
    if (status == 'voided') return 'voided';
    if (status == 'refunded') return 'refunded';
    if (status == 'expired') return 'expired';
    if (isRefundFailed) return 'refund_failed';
    if (isUnused && isExpiredByDate) return 'expired';
    return status;
  }

  /// 详情页多状态标签（与商家端 detailStatusTags 逻辑一致）
  List<String> get detailStatusTags {
    if (status == 'refund_failed') return ['refund_failed'];
    if (status == 'voided') return ['voided'];
    if (status != 'unused') return [status];
    final tags = <String>['unused'];
    if (refundRejectedAt != null) tags.add('refund_rejected');
    if (couponExpiresAt == null) return tags;
    final now = DateTime.now();
    if (now.isBefore(couponExpiresAt!)) return tags;
    final elapsed = now.difference(couponExpiresAt!);
    if (elapsed >= const Duration(hours: 24)) {
      tags.add('pending_refund');
    } else {
      tags.add('expired');
    }
    return tags;
  }
}
