// =============================================================
// FunnelBarWidget — 单个 Deal 的三段横向转化漏斗条
// 使用 Row + LayoutBuilder + FractionallySizedBox 实现
// 不依赖任何第三方图表库
//
// 布局结构:
//   Deal 标题
//   [Views 段 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓]  1234
//   [Orders 段 ▓▓▓▓▓▓▓▓]  567 (45.9%)
//   [Redemptions 段 ▓▓▓▓]  234 (41.3%)
// =============================================================

import 'package:flutter/material.dart';
import '../models/analytics_data.dart';

// =============================================================
// FunnelBarWidget
// =============================================================
class FunnelBarWidget extends StatelessWidget {
  /// 单个 Deal 的漏斗数据
  final DealFunnelData data;

  const FunnelBarWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Deal 标题（最多 2 行）
          Text(
            data.dealTitle,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A2E),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),

          // Views 段（基准，始终 100% 宽度）
          _FunnelRow(
            label:      'Views',
            count:      data.views,
            fraction:   1.0,               // 基准宽度
            color:      const Color(0xFFFF6B35),
            rateLabel:  null,              // 基准行无转化率
          ),
          const SizedBox(height: 6),

          // Orders 段（相对于 Views 的比例）
          _FunnelRow(
            label:     'Orders',
            count:     data.orders,
            fraction:  data.ordersFraction,
            color:     const Color(0xFFFF9A6C),
            rateLabel: data.views > 0
                ? '${data.viewToOrderRate.toStringAsFixed(1)}%'
                : null,
          ),
          const SizedBox(height: 6),

          // Redemptions 段（相对于 Views 的比例）
          _FunnelRow(
            label:     'Redemptions',
            count:     data.redemptions,
            fraction:  data.redemptionsFraction,
            color:     const Color(0xFFFFBF9B),
            rateLabel: data.orders > 0
                ? '${data.orderToRedemptionRate.toStringAsFixed(1)}%'
                : null,
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _FunnelRow — 单条漏斗横条（私有 Widget）
// =============================================================
class _FunnelRow extends StatelessWidget {
  /// 阶段标签（如 "Views"）
  final String label;

  /// 阶段数量
  final int count;

  /// 相对于最大值的宽度比例 (0.0 ~ 1.0)
  final double fraction;

  /// 颜色
  final Color color;

  /// 转化率文本（如 "45.9%"），null 则不展示
  final String? rateLabel;

  const _FunnelRow({
    required this.label,
    required this.count,
    required this.fraction,
    required this.color,
    this.rateLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 标签固定宽度区域
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
        ),

        // 漏斗横条（弹性宽度区域）
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 最小可见宽度：4px（避免 0 数据时完全不可见）
              final barWidth = count > 0
                  ? (constraints.maxWidth * fraction).clamp(4.0, constraints.maxWidth)
                  : 0.0;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 漏斗条
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    width: barWidth,
                    height: 18,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 数量文字
                  Text(
                    _formatCount(count),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  // 转化率（若有）
                  if (rateLabel != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      '($rateLabel)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// 格式化数量显示（超过 1000 显示为 "1.2k"）
  String _formatCount(int n) {
    if (n >= 1000) {
      final k = n / 1000.0;
      return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k';
    }
    return n.toString();
  }
}
