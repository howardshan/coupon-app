// =============================================================
// CustomerPieWidget — 新老客户占比可视化
// 使用 CustomPainter 绘制简单饼图（两段弧形）
// 不依赖任何第三方图表库
//
// 布局结构:
//   [饼图] | 新客 / 老客 图例说明
//            复购率 大数字
// =============================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/analytics_data.dart';

// =============================================================
// CustomerPieWidget
// =============================================================
class CustomerPieWidget extends StatelessWidget {
  /// 客群分析数据
  final CustomerAnalysis data;

  const CustomerPieWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    // 无数据时显示空状态
    if (data.totalCustomers == 0) {
      return _buildEmptyState();
    }

    return Row(
      children: [
        // 左侧：饼图
        SizedBox(
          width: 100,
          height: 100,
          child: CustomPaint(
            painter: _PieChartPainter(
              newFraction:       data.newCustomersFraction,
              returningFraction: data.returningCustomersFraction,
            ),
          ),
        ),
        const SizedBox(width: 20),

        // 右侧：图例 + 复购率
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 新客图例
              _LegendItem(
                color: const Color(0xFF4CAF50),
                label: 'New Customers',
                count: data.newCustomersCount,
                fraction: data.newCustomersFraction,
              ),
              const SizedBox(height: 8),
              // 老客图例
              _LegendItem(
                color: const Color(0xFFFF6B35),
                label: 'Returning Customers',
                count: data.returningCustomersCount,
                fraction: data.returningCustomersFraction,
              ),
              const SizedBox(height: 12),
              // 复购率大数字
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${data.repeatRate.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFF6B35),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Repeat Rate',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 无数据占位
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(
            'No customer data yet',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _PieChartPainter — 自定义饼图 Painter（私有）
// 绘制两段弧形，新客（绿色）+ 老客（橙色）
// =============================================================
class _PieChartPainter extends CustomPainter {
  /// 新客占比 (0.0 ~ 1.0)
  final double newFraction;

  /// 老客占比 (0.0 ~ 1.0)
  final double returningFraction;

  _PieChartPainter({
    required this.newFraction,
    required this.returningFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4; // 留 4px 边距
    final rect   = Rect.fromCircle(center: center, radius: radius);

    // 新客弧：从 -90° 开始，顺时针绘制
    final newSweep        = 2 * math.pi * newFraction;
    final returningSweep  = 2 * math.pi * returningFraction;

    final newPaint = Paint()
      ..color = const Color(0xFF4CAF50)
      ..style = PaintingStyle.fill;

    final returningPaint = Paint()
      ..color = const Color(0xFFFF6B35)
      ..style = PaintingStyle.fill;

    // 分隔线颜色（白色，2px）
    final separatorPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // 绘制新客扇区（从 -90° 起）
    canvas.drawArc(rect, -math.pi / 2, newSweep, true, newPaint);

    // 绘制老客扇区（紧接新客结束角度）
    canvas.drawArc(rect, -math.pi / 2 + newSweep, returningSweep, true, returningPaint);

    // 绘制分隔线（覆盖在上方，增加视觉分割感）
    canvas.drawCircle(center, radius, separatorPaint);

    // 绘制中心白色圆（甜甜圈效果）
    final holePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.55, holePaint);
  }

  @override
  bool shouldRepaint(_PieChartPainter oldDelegate) =>
      oldDelegate.newFraction != newFraction ||
      oldDelegate.returningFraction != returningFraction;
}

// =============================================================
// _LegendItem — 图例条目（私有 Widget）
// =============================================================
class _LegendItem extends StatelessWidget {
  final Color  color;
  final String label;
  final int    count;
  final double fraction;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.count,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (fraction * 100).toStringAsFixed(1);
    return Row(
      children: [
        // 颜色圆点
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ),
        Text(
          '$count ($pct%)',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }
}
