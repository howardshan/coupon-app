// 商家通知数据模型
// 对应数据库表：merchant_notifications
// 包含：NotificationType 枚举 + MerchantNotification 不可变模型

import 'package:flutter/material.dart';

// =============================================================
// NotificationType — 通知类型枚举
// 与数据库 merchant_notification_type 枚举保持一致
// =============================================================
enum NotificationType {
  newOrder,      // 新订单
  redemption,    // 核销（券被使用）
  reviewResult,  // 评价通知
  dealApproved,  // Deal 审核通过
  dealRejected,  // Deal 审核拒绝
  system,        // 系统公告
  ;

  // 从数据库字符串解析枚举
  static NotificationType fromString(String value) {
    switch (value) {
      case 'new_order':
        return NotificationType.newOrder;
      case 'redemption':
        return NotificationType.redemption;
      case 'review_result':
        return NotificationType.reviewResult;
      case 'deal_approved':
        return NotificationType.dealApproved;
      case 'deal_rejected':
        return NotificationType.dealRejected;
      case 'system':
        return NotificationType.system;
      default:
        return NotificationType.system;
    }
  }

  // 获取对应的 Material 图标
  IconData get icon {
    switch (this) {
      case NotificationType.newOrder:
        return Icons.shopping_cart_outlined;
      case NotificationType.redemption:
        return Icons.qr_code_scanner;
      case NotificationType.reviewResult:
        return Icons.star_outline;
      case NotificationType.dealApproved:
        return Icons.check_circle_outline;
      case NotificationType.dealRejected:
        return Icons.cancel_outlined;
      case NotificationType.system:
        return Icons.campaign_outlined;
    }
  }

  // 获取图标背景色
  Color get color {
    switch (this) {
      case NotificationType.newOrder:
        return const Color(0xFF4CAF50);    // 绿色：新订单
      case NotificationType.redemption:
        return const Color(0xFF2196F3);    // 蓝色：核销
      case NotificationType.reviewResult:
        return const Color(0xFFFF9800);    // 橙色：评价
      case NotificationType.dealApproved:
        return const Color(0xFF4CAF50);    // 绿色：审核通过
      case NotificationType.dealRejected:
        return const Color(0xFFF44336);    // 红色：审核拒绝
      case NotificationType.system:
        return const Color(0xFF9C27B0);    // 紫色：系统消息
    }
  }

  // 获取对应的路由路径（用于点击通知后跳转）
  // 返回 null 表示不需要跳转（如系统公告）
  String? get route {
    switch (this) {
      case NotificationType.newOrder:
        return '/orders';
      case NotificationType.redemption:
        return '/scan';
      case NotificationType.reviewResult:
        return '/reviews';
      case NotificationType.dealApproved:
        return '/deals';
      case NotificationType.dealRejected:
        return '/deals';
      case NotificationType.system:
        return null;
    }
  }

  // 用于显示的标签文字
  String get label {
    switch (this) {
      case NotificationType.newOrder:
        return 'New Order';
      case NotificationType.redemption:
        return 'Redemption';
      case NotificationType.reviewResult:
        return 'Review';
      case NotificationType.dealApproved:
        return 'Deal Approved';
      case NotificationType.dealRejected:
        return 'Deal Rejected';
      case NotificationType.system:
        return 'System';
    }
  }
}

// =============================================================
// MerchantNotification — 通知数据模型（不可变）
// =============================================================
class MerchantNotification {
  const MerchantNotification({
    required this.id,
    required this.merchantId,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String merchantId;
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic> data; // 附加 JSON 载荷，如 {order_id, deal_id}
  final bool isRead;
  final DateTime createdAt;

  // 从 JSON（数据库返回）构建模型
  factory MerchantNotification.fromJson(Map<String, dynamic> json) {
    return MerchantNotification(
      id:         json['id'] as String,
      merchantId: json['merchant_id'] as String,
      type:       NotificationType.fromString(json['type'] as String? ?? 'system'),
      title:      json['title'] as String? ?? '',
      body:       json['body'] as String? ?? '',
      data:       (json['data'] as Map<String, dynamic>?) ?? {},
      isRead:     json['is_read'] as bool? ?? false,
      createdAt:  DateTime.parse(json['created_at'] as String),
    );
  }

  // 转换为 JSON（调试/序列化使用）
  Map<String, dynamic> toJson() {
    return {
      'id':          id,
      'merchant_id': merchantId,
      'type':        type.name,
      'title':       title,
      'body':        body,
      'data':        data,
      'is_read':     isRead,
      'created_at':  createdAt.toIso8601String(),
    };
  }

  // 不可变更新（用于标记已读等操作）
  MerchantNotification copyWith({
    String? id,
    String? merchantId,
    NotificationType? type,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return MerchantNotification(
      id:         id         ?? this.id,
      merchantId: merchantId ?? this.merchantId,
      type:       type       ?? this.type,
      title:      title      ?? this.title,
      body:       body       ?? this.body,
      data:       data       ?? this.data,
      isRead:     isRead     ?? this.isRead,
      createdAt:  createdAt  ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MerchantNotification &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'MerchantNotification(id: $id, type: ${type.name}, title: $title, isRead: $isRead)';
}
