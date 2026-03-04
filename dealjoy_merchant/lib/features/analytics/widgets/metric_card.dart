// =============================================================
// MetricCard — 单指标数据卡片
// 展示: 图标 + 大数字 + 标签 + 可选趋势箭头
// 用于经营概览的 4 张数据卡片
// =============================================================

import 'package:flutter/material.dart';

// =============================================================
// MetricCard Widget
// =============================================================
class MetricCard extends StatelessWidget {
  /// 指标图标
  final IconData icon;

  /// 指标数值（格式化后的字符串，如 "1,234" 或 "$99.50"）
  final String value;

  /// 指标标签（如 "Views", "Orders"）
  final String label;

  /// 卡片强调色（默认橙色 #FF6B35）
  final Color color;

  /// 可选趋势方向：true=上升, false=下降, null=无趋势
  final bool? trendUp;

  const MetricCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color = const Color(0xFFFF6B35),
    this.trendUp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        // 细微阴影，保持卡片层次感
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：图标 + 可选趋势箭头
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 图标背景圆角方块
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              // 趋势箭头（P2：暂时静态展示）
              if (trendUp != null)
                Icon(
                  trendUp! ? Icons.trending_up : Icons.trending_down,
                  color: trendUp! ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                  size: 18,
                ),
            ],
          ),
          const SizedBox(height: 12),
          // 数值（大字体）
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          // 标签
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
