// 订单状态颜色 Badge 组件
// paid=蓝 / redeemed=绿 / refunded=橙 / cancelled=灰

import 'package:flutter/material.dart';
import '../models/merchant_order.dart';

/// 状态 Badge — 带颜色的圆角标签
/// 用于订单列表卡片和订单详情页
class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge({
    super.key,
    required this.status,
    this.fontSize = 12.0,
  });

  final OrderStatus status;

  /// 字体大小（详情页可以用更大的字号）
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.badgeBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: status.badgeColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 状态圆点
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: status.badgeColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          // 状态文字
          Text(
            status.displayLabel,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: status.badgeColor,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
