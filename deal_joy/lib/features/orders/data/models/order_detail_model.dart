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
      event: json['event'] as String,
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

  final String? paymentIntentIdMasked;
  final String? paymentStatus;
  final double? refundAmount;

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
    this.paymentIntentIdMasked,
    this.paymentStatus,
    this.refundAmount,
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

    // V3：解析 items 列表（Edge Function 将 items 放在 json['order']['items'] 或顶层 json['items']）
    // 顶层直接传入时用 json['items']，通过 order 包装时调用方应先解包 json['order']
    final rawItems = json['items'] as List?;
    final items = rawItems
            ?.map((e) => OrderItemModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <OrderItemModel>[];

    return OrderDetailModel(
      id: json['id'] as String,
      orderNumber: json['order_number'] as String? ?? 'DJ-????????',
      status: json['status'] as String? ?? 'unused',
      dealId: json['deal_id'] as String? ?? '',
      dealTitle: json['deal_title'] as String? ?? '',
      dealOriginalPrice: (json['deal_original_price'] as num?)?.toDouble() ?? 0.0,
      dealDiscountPrice: (json['deal_discount_price'] as num?)?.toDouble() ?? 0.0,
      dealImageUrl: json['deal_image_url'] as String?,
      merchantName: json['merchant_name'] as String?,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      paymentIntentIdMasked: json['payment_intent_id_masked'] as String?,
      paymentStatus: json['payment_status'] as String?,
      refundAmount: (json['refund_amount'] as num?)?.toDouble(),
      refundReason: json['refund_reason'] as String?,
      couponId: json['coupon_id'] as String?,
      couponCode: json['coupon_code'] as String?,
      couponStatus: json['coupon_status'] as String?,
      couponExpiresAt: json['coupon_expires_at'] != null
          ? DateTime.parse(json['coupon_expires_at'] as String)
          : null,
      couponUsedAt: json['coupon_used_at'] != null
          ? DateTime.parse(json['coupon_used_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      refundRequestedAt: json['refund_requested_at'] != null
          ? DateTime.parse(json['refund_requested_at'] as String)
          : null,
      refundedAt: json['refunded_at'] != null
          ? DateTime.parse(json['refunded_at'] as String)
          : null,
      refundRejectedAt: json['refund_rejected_at'] != null
          ? DateTime.parse(json['refund_rejected_at'] as String)
          : null,
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
