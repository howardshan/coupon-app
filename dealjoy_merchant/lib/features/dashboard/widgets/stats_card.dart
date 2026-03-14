// 工作台数据卡片组件
// 显示: 图标 + 大数字 + 标题标签
// 用于: 今日订单数 / 核销数 / 收入 / 待核销

import 'package:flutter/material.dart';

// ============================================================
// StatsCard — 单个数据展示卡片
// ============================================================
class StatsCard extends StatelessWidget {
  /// 卡片标题（如 "Today Orders"）
  final String title;

  /// 展示数值（已格式化的字符串，如 "42" 或 "\$128.50"）
  final String value;

  /// 左上角图标
  final IconData icon;

  /// 主题颜色（图标背景 + 数字颜色）
  final Color color;

  /// 是否正在加载（显示占位 shimmer）
  final bool isLoading;

  const StatsCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: isLoading ? _buildSkeleton() : _buildContent(),
      ),
    );
  }

  // 正常内容布局（移除固定 SizedBox，由 spaceBetween 自动分配间距，防止不同设备溢出）
  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 图标圆形背景
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withAlpha(26), // ~10% 透明度背景
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 22,
            color: color,
          ),
        ),

        // 大数字
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1.1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        // 标题标签
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // 骨架屏占位（加载中，与正常布局一致使用 spaceBetween 无固定间距）
  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 图标骨架
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        // 数字骨架
        Container(
          width: 60,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        // 标题骨架
        Container(
          width: 80,
          height: 14,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}
