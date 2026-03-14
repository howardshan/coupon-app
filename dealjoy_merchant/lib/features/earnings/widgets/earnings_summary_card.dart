// 收入概览卡片组件
// 用于 EarningsPage 顶部 4 张汇总卡片
// 支持骨架屏加载状态

import 'package:flutter/material.dart';

// =============================================================
// EarningsSummaryCard — 收入概览单张卡片（ConsumerWidget 不适用于纯展示组件）
// =============================================================
class EarningsSummaryCard extends StatelessWidget {
  /// 卡片标题（如 "This Month"）
  final String title;

  /// 金额数值（已格式化为 $xx.xx）
  final String amount;

  /// 左上角图标
  final IconData icon;

  /// 主题色（图标 + 底部装饰条）
  final Color color;

  /// 是否显示骨架屏（加载中状态）
  final bool isLoading;

  /// 可选副标题（如 "T+7 days"）
  final String? subtitle;

  const EarningsSummaryCard({
    super.key,
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
    this.isLoading = false,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        // 底部左侧彩色装饰条
        border: Border(
          bottom: BorderSide(color: color, width: 3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13), // ~5%
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: isLoading ? _buildSkeleton() : _buildContent(),
    );
  }

  // ----------------------------------------------------------
  // 正常内容布局
  // ----------------------------------------------------------
  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 顶部：图标 + 标题
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withAlpha(26), // ~10%
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        // 金额数字
        Text(
          amount,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: -0.5,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // 可选副标题
        if (subtitle != null)
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  // ----------------------------------------------------------
  // 骨架屏布局（加载中）
  // ----------------------------------------------------------
  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            // 图标占位
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 8),
            // 标题占位
            Container(
              width: 64,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ],
        ),
        // 金额占位
        Container(
          width: 80,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ],
    );
  }
}
