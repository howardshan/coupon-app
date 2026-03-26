// 通知中心页
// 展示当前用户的通知列表，支持标记已读、分页加载、点击跳转

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/notification_model.dart';
import '../../domain/providers/notification_provider.dart';

class NotificationScreen extends ConsumerStatefulWidget {
  const NotificationScreen({super.key});

  @override
  ConsumerState<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends ConsumerState<NotificationScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 监听滚动到底部以触发加载更多
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final current = _scrollController.offset;
    // 距离底部 100px 时触发加载更多
    if (current >= maxScroll - 100) {
      ref.read(notificationsProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          // 全部标记为已读
          TextButton(
            onPressed: () async {
              await notifier.markAllAsRead();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All notifications marked as read'),
                    backgroundColor: AppColors.textSecondary,
                  ),
                );
              }
            },
            child: const Text(
              'Mark all read',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 40),
              const SizedBox(height: 8),
              const Text(
                'Failed to load notifications',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(notificationsProvider),
                child: const Text(
                  'Retry',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ),
        ),
        data: (notifications) => notifications.isEmpty
            ? _EmptyState()
            : _NotificationList(
                notifications: notifications,
                scrollController: _scrollController,
                hasMore: notifier.hasMore,
                onTap: (n) => _handleTap(context, ref, n),
              ),
      ),
    );
  }

  // 点击通知：标记已读并根据 data 字段跳转
  void _handleTap(
    BuildContext context,
    WidgetRef ref,
    NotificationModel notification,
  ) {
    // 先标记已读
    if (!notification.isRead) {
      ref.read(notificationsProvider.notifier).markAsRead(notification.id);
    }

    // 根据通知类型和 data 字段决定跳转目标
    final data = notification.data ?? {};
    switch (notification.type) {
      case 'transaction':
        final orderId = data['order_id'] as String?;
        if (orderId != null) context.push('/order/$orderId');
      case 'friend_request':
        context.push('/chat/friend-requests');
      case 'friend_activity':
        final dealId = data['deal_id'] as String?;
        if (dealId != null) context.push('/deals/$dealId');
      case 'review_reply':
        final dealId = data['deal_id'] as String?;
        if (dealId != null) context.push('/deals/$dealId');
      case 'chat_message':
        final conversationId = data['conversation_id'] as String?;
        if (conversationId != null) context.push('/chat/$conversationId');
      case 'announcement':
      default:
        // 公告类无需特殊跳转
        break;
    }
  }
}

// 通知列表主体
class _NotificationList extends StatelessWidget {
  final List<NotificationModel> notifications;
  final ScrollController scrollController;
  final bool hasMore;
  final void Function(NotificationModel) onTap;

  const _NotificationList({
    required this.notifications,
    required this.scrollController,
    required this.hasMore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: notifications.length + (hasMore ? 1 : 0),
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        color: AppColors.surfaceVariant,
      ),
      itemBuilder: (context, index) {
        // 底部加载更多指示器
        if (index >= notifications.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
          );
        }
        final notification = notifications[index];
        return _NotificationTile(
          notification: notification,
          onTap: () => onTap(notification),
        );
      },
    );
  }
}

// 单条通知列表项
class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 未读通知使用浅橙色背景
    final bgColor = notification.isRead
        ? AppColors.surface
        : const Color(0xFFFFF8F5);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 类型图标
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _iconBackgroundColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _typeIcon,
                color: _iconBackgroundColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // 标题 + 正文 + 时间
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: notification.isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 时间
                      Text(
                        _formatTime(notification.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // 未读蓝点
            if (!notification.isRead)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 根据通知类型返回对应图标
  IconData get _typeIcon {
    switch (notification.type) {
      case 'transaction':
        return Icons.receipt_long_outlined;
      case 'announcement':
        return Icons.campaign_outlined;
      case 'friend_activity':
        return Icons.people_outlined;
      case 'friend_request':
        return Icons.person_add_outlined;
      case 'review_reply':
        return Icons.rate_review_outlined;
      case 'chat_message':
        return Icons.chat_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  // 根据通知类型返回图标背景色
  Color get _iconBackgroundColor {
    switch (notification.type) {
      case 'transaction':
        return AppColors.success;
      case 'announcement':
        return AppColors.info;
      case 'friend_activity':
      case 'friend_request':
        return AppColors.secondary;
      case 'review_reply':
        return AppColors.warning;
      case 'chat_message':
        return AppColors.primary;
      default:
        return AppColors.textHint;
    }
  }

  // 格式化时间：今天显示时分，昨天显示 Yesterday，更早显示日期
  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final date = DateTime(dt.year, dt.month, dt.day);

    if (date == today) {
      return DateFormat('h:mm a').format(dt);
    } else if (date == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d').format(dt);
    }
  }
}

// 无通知时的空状态
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_outlined,
            size: 64,
            color: AppColors.textHint.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No notifications',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "You're all caught up!",
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}
