// 通知列表条目组件
// 每条通知显示：类型图标、标题、内容摘要、相对时间、未读蓝点
// 点击触发：标记已读 + 根据通知类型跳转到对应页面

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/merchant_notification.dart';
import '../providers/notifications_provider.dart';

class NotificationTile extends ConsumerWidget {
  const NotificationTile({
    super.key,
    required this.notification,
  });

  final MerchantNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme      = Theme.of(context);
    final isUnread   = !notification.isRead;
    final typeColor  = notification.type.color;

    return Material(
      color: isUnread
          ? theme.colorScheme.primary.withValues(alpha: 0.04) // 未读背景浅蓝
          : Colors.white,
      child: InkWell(
        onTap: () => _handleTap(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ----------------------------------------
              // 左侧：圆形图标（按类型着色）
              // ----------------------------------------
              _TypeIcon(type: notification.type, color: typeColor),
              const SizedBox(width: 12),

              // ----------------------------------------
              // 中间：标题 + 内容
              // ----------------------------------------
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题（未读时加粗）
                    Text(
                      notification.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            isUnread ? FontWeight.w600 : FontWeight.w400,
                        color: isUnread
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface.withValues(alpha: 0.75),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),

                    // 内容摘要（最多 2 行）
                    Text(
                      notification.body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),

                    // 相对时间
                    Text(
                      _formatRelativeTime(notification.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.40),
                      ),
                    ),
                  ],
                ),
              ),

              // ----------------------------------------
              // 右侧：未读蓝点指示器
              // ----------------------------------------
              if (isUnread) ...[
                const SizedBox(width: 8),
                Container(
                  width:       8,
                  height:      8,
                  margin:      const EdgeInsets.only(top: 4),
                  decoration:  BoxDecoration(
                    color:        theme.colorScheme.primary,
                    shape:        BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // =============================================================
  // _handleTap — 点击处理：标记已读 + 路由跳转
  // =============================================================
  void _handleTap(BuildContext context, WidgetRef ref) {
    // 1. 标记已读（乐观更新）
    if (!notification.isRead) {
      ref
          .read(notificationsNotifierProvider.notifier)
          .markRead(notification.id);
    }

    // 2. 根据通知类型跳转对应页面
    final route = notification.type.route;
    if (route != null && context.mounted) {
      context.go(route);
    }
  }

  // =============================================================
  // _formatRelativeTime — 相对时间格式化
  // 如：Just now / 5m ago / 2h ago / Yesterday / Mar 1
  // =============================================================
  String _formatRelativeTime(DateTime dt) {
    final now  = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    if (diff.inDays == 1)    return 'Yesterday';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';

    // 超过一周：显示具体日期
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

// =============================================================
// _TypeIcon — 通知类型图标（内部组件）
// =============================================================
class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.type, required this.color});

  final NotificationType type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  42,
      height: 42,
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Icon(
        type.icon,
        size:  20,
        color: color,
      ),
    );
  }
}
