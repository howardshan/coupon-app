// 订单时间线组件
// 竖排步骤：purchased → redeemed → refunded
// 每个节点：图标 + 标题 + 副标题 + 时间戳

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/merchant_order.dart';

/// 订单时间线（竖排步骤列表）
class OrderTimelineWidget extends StatelessWidget {
  const OrderTimelineWidget({
    super.key,
    required this.timeline,
  });

  final OrderTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final events = timeline.events;
    if (events.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(events.length, (index) {
        final event = events[index];
        final isLast = index == events.length - 1;
        return _TimelineItem(
          event: event,
          isLast: isLast,
        );
      }),
    );
  }
}

// =============================================================
// 单个时间线节点
// =============================================================
class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.event,
    required this.isLast,
  });

  final TimelineEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final tsFormatter = DateFormat('MMM d, yyyy · h:mm a');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：图标 + 连接线
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // 图标圆圈
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: event.completed
                        ? event.iconColor.withValues(alpha: 0.12)
                        : Colors.grey.shade100,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: event.completed
                          ? event.iconColor.withValues(alpha: 0.3)
                          : Colors.grey.shade200,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    event.icon,
                    size: 18,
                    color: event.completed
                        ? event.iconColor
                        : Colors.grey.shade400,
                  ),
                ),
                // 连接线（最后一项不显示）
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // 右侧：文字内容
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 7), // 对齐图标中心
                  // 事件标题
                  Text(
                    event.displayTitle,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: event.completed
                          ? const Color(0xFF1A1A1A)
                          : Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 副标题说明
                  if (event.displaySubtitle.isNotEmpty)
                    Text(
                      event.displaySubtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  // 时间戳
                  if (event.timestamp != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      tsFormatter.format(event.timestamp!.toLocal()),
                      style: TextStyle(
                        fontSize: 12,
                        color: event.iconColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
