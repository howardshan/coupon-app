// 未读通知 Badge 组件
// 在子 Widget 右上角叠加显示红色数字角标
// count <= 0 时不显示 Badge，count >= 100 时显示 '99+'

import 'package:flutter/material.dart';

class NotificationBadge extends StatelessWidget {
  const NotificationBadge({
    super.key,
    required this.child,
    required this.count,
  });

  final Widget child;

  // 未读数量，0 或负数不显示 Badge
  final int count;

  @override
  Widget build(BuildContext context) {
    // 无未读：直接返回子 Widget，不添加 Badge
    if (count <= 0) return child;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -6,
          top:   -4,
          child: _BadgeLabel(count: count),
        ),
      ],
    );
  }
}

// =============================================================
// _BadgeLabel — 红色角标数字标签（仅内部使用）
// =============================================================
class _BadgeLabel extends StatelessWidget {
  const _BadgeLabel({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // 超过 99 显示 '99+'，否则显示数字
    final label = count > 99 ? '99+' : '$count';
    final isLong = count > 99;

    return Container(
      constraints: BoxConstraints(
        minWidth:  isLong ? 30 : 18,
        minHeight: 18,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color:        Colors.red,
        borderRadius: BorderRadius.circular(9),
        // 白色描边，防止 Badge 与底色混淆
        border: Border.all(color: Colors.white, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color:      Colors.white,
          fontSize:   10,
          fontWeight: FontWeight.bold,
          height:     1.0,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
