// 会话列表项组件
// 展示单个会话的头像、名称、最后消息预览、未读数 badge 和时间

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/conversation_model.dart';

class ConversationTile extends StatelessWidget {
  final ConversationModel conversation;
  final VoidCallback onTap;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 头像
            _ConversationAvatar(conversation: conversation),
            const SizedBox(width: 12),

            // 中间：名称 + 最后消息预览
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 会话名称
                      Expanded(
                        child: Text(
                          conversation.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: conversation.unreadCount > 0
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      // 置顶图标
                      if (conversation.isPinned)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.push_pin, size: 12, color: AppColors.primary),
                        ),
                      const SizedBox(width: 4),
                      // 时间
                      Text(
                        _formatTime(conversation.lastMessageAt ?? conversation.updatedAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // 最后消息预览
                      Expanded(
                        child: Text(
                          _buildPreviewText(conversation),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: conversation.unreadCount > 0
                                ? AppColors.textSecondary
                                : AppColors.textHint,
                          ),
                        ),
                      ),
                      // 未读数 badge
                      if (conversation.unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        _UnreadBadge(count: conversation.unreadCount),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建最后消息预览文本，客服会话时带 sender 前缀
  String _buildPreviewText(ConversationModel c) {
    final content = c.lastMessageContent;
    if (content == null || content.isEmpty) return 'No messages yet';

    // 图片类型消息
    if (c.lastMessageType == 'image') return '[Image]';
    // 券码消息
    if (c.lastMessageType == 'coupon') return '[Coupon]';
    // 系统消息
    if (c.lastMessageType == 'system') return content;

    // group / support 会话加 sender 名称前缀
    final senderName = c.lastMessageSenderName;
    if (senderName != null && senderName.isNotEmpty) {
      return '$senderName: $content';
    }
    return content;
  }

  /// 将 DateTime 格式化为友好时间字符串
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return DateFormat('h:mm a').format(time);
    if (diff.inDays < 7) return DateFormat('EEE').format(time);
    return DateFormat('MMM d').format(time);
  }
}

// 会话头像组件，支持网络图片 / 本地占位
class _ConversationAvatar extends StatelessWidget {
  final ConversationModel conversation;

  const _ConversationAvatar({required this.conversation});

  @override
  Widget build(BuildContext context) {
    // 客服会话显示机器人图标
    if (conversation.type == 'support') {
      return Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: AppColors.primaryGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.support_agent, color: Colors.white, size: 22),
      );
    }

    final avatarUrl = conversation.displayAvatarUrl;

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: avatarUrl,
          width: 46,
          height: 46,
          fit: BoxFit.cover,
          placeholder: (_, _) => _PlaceholderAvatar(
            isGroup: conversation.type == 'group',
          ),
          errorWidget: (_, _, _) => _PlaceholderAvatar(
            isGroup: conversation.type == 'group',
          ),
        ),
      );
    }

    return _PlaceholderAvatar(isGroup: conversation.type == 'group');
  }
}

// 占位头像
class _PlaceholderAvatar extends StatelessWidget {
  final bool isGroup;

  const _PlaceholderAvatar({this.isGroup = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
      ),
      child: Icon(
        isGroup ? Icons.group : Icons.person,
        color: AppColors.textHint,
        size: 22,
      ),
    );
  }
}

// 未读消息数量红色 badge
class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          count > 99 ? '99+' : '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
