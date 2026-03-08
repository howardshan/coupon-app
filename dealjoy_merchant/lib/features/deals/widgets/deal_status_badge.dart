// Deal状态徽章 Widget
// 根据 DealStatus 显示对应颜色和文字的 Badge

import 'package:flutter/material.dart';
import '../models/merchant_deal.dart';

// ============================================================
// DealStatusBadge — 状态颜色 Badge（StatelessWidget）
// pending=橙色, active=绿色, inactive=灰色, rejected=红色
// ============================================================
class DealStatusBadge extends StatelessWidget {
  const DealStatusBadge({
    super.key,
    required this.status,
    this.fontSize = 11.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  });

  final DealStatus status;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final config = _badgeConfig(status);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: config.backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 状态指示点
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: config.dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          // 状态文字
          Text(
            status.displayLabel,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: config.textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 内部配置类（颜色方案）
// ============================================================
class _BadgeConfig {
  const _BadgeConfig({
    required this.backgroundColor,
    required this.textColor,
    required this.dotColor,
  });

  final Color backgroundColor;
  final Color textColor;
  final Color dotColor;
}

/// 根据状态返回对应的颜色配置
_BadgeConfig _badgeConfig(DealStatus status) {
  switch (status) {
    case DealStatus.pending:
      return const _BadgeConfig(
        backgroundColor: Color(0xFFFFF3E0),
        textColor:       Color(0xFFF57C00),
        dotColor:        Color(0xFFFF9800),
      );
    case DealStatus.active:
      return const _BadgeConfig(
        backgroundColor: Color(0xFFE8F5E9),
        textColor:       Color(0xFF2E7D32),
        dotColor:        Color(0xFF4CAF50),
      );
    case DealStatus.inactive:
      return const _BadgeConfig(
        backgroundColor: Color(0xFFF5F5F5),
        textColor:       Color(0xFF757575),
        dotColor:        Color(0xFF9E9E9E),
      );
    case DealStatus.rejected:
      return const _BadgeConfig(
        backgroundColor: Color(0xFFFFEBEE),
        textColor:       Color(0xFFC62828),
        dotColor:        Color(0xFFEF5350),
      );
    case DealStatus.expired:
      return const _BadgeConfig(
        backgroundColor: Color(0xFFEEEEEE),
        textColor:       Color(0xFF616161),
        dotColor:        Color(0xFF757575),
      );
  }
}
