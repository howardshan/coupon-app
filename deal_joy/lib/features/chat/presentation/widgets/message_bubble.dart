// 消息气泡组件
// 根据消息类型（text / image / coupon / emoji / system）渲染不同样式气泡
// 支持我的消息（右侧橙色）和对方消息（左侧灰色）

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/message_model.dart';

/// 消息气泡主组件
class MessageBubble extends StatelessWidget {
  final MessageModel message;

  /// 当前登录用户 ID，用于判断消息方向
  final String currentUserId;

  /// 是否为群聊（群聊需在气泡上方显示发送者名字）
  final bool isGroupChat;

  /// 是否显示日期分隔符（在此消息之前）
  final bool showDateSeparator;

  const MessageBubble({
    super.key,
    required this.message,
    required this.currentUserId,
    this.isGroupChat = false,
    this.showDateSeparator = false,
  });

  /// 判断是否为当前用户发送的消息
  bool get _isMine => message.senderId == currentUserId;

  @override
  Widget build(BuildContext context) {
    // system 类型消息居中展示
    if (message.isSystemMessage) {
      return Column(
        children: [
          if (showDateSeparator) _DateSeparator(date: message.createdAt),
          _SystemMessageBubble(content: message.content ?? ''),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 日期分隔符
        if (showDateSeparator) _DateSeparator(date: message.createdAt),

        // 消息气泡行（我的在右，对方在左）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment:
                _isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 对方头像（左侧消息）
              if (!_isMine) ...[
                _Avatar(avatarUrl: message.senderAvatarUrl),
                const SizedBox(width: 8),
              ],

              // 气泡内容区域
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                child: Column(
                  crossAxisAlignment: _isMine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    // 群聊中显示发送者名字
                    if (isGroupChat && !_isMine && message.senderName != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                        child: Text(
                          message.senderName!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),

                    // 根据消息类型渲染对应气泡
                    _buildBubbleContent(context),

                    // 消息时间戳
                    const SizedBox(height: 2),
                    _TimeStamp(
                      time: message.createdAt,
                      isMine: _isMine,
                    ),
                  ],
                ),
              ),

              // 我的头像（右侧消息）
              if (_isMine) ...[
                const SizedBox(width: 8),
                _Avatar(avatarUrl: message.senderAvatarUrl),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 根据消息类型构建气泡内容
  Widget _buildBubbleContent(BuildContext context) {
    // 已撤回消息
    if (message.isDeleted) {
      return _TextBubble(
        text: 'Message recalled',
        isMine: _isMine,
        isDeleted: true,
      );
    }

    switch (message.type) {
      case 'text':
        return _TextBubble(text: message.content ?? '', isMine: _isMine);
      case 'emoji':
        return _EmojiBubble(emoji: message.content ?? '');
      case 'image':
        return _ImageBubble(imageUrl: message.imageUrl ?? '');
      case 'coupon':
        return _CouponBubble(
          payload: message.couponPayload ?? {},
          onViewDeal: (dealId) => context.push('/deals/$dealId'),
        );
      default:
        return _TextBubble(text: message.content ?? '', isMine: _isMine);
    }
  }
}

// ============================================================
// 文字气泡
// ============================================================

class _TextBubble extends StatelessWidget {
  final String text;
  final bool isMine;
  final bool isDeleted;

  const _TextBubble({
    required this.text,
    required this.isMine,
    this.isDeleted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        // 我的消息用主色，对方消息用浅灰
        color: isMine ? AppColors.primary : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMine ? 18 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 18),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          color: isMine ? Colors.white : AppColors.textPrimary,
          fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }
}

// ============================================================
// Emoji 气泡（大号显示）
// ============================================================

class _EmojiBubble extends StatelessWidget {
  final String emoji;

  const _EmojiBubble({required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Text(
      emoji,
      style: const TextStyle(fontSize: 48),
    );
  }
}

// ============================================================
// 图片气泡
// ============================================================

class _ImageBubble extends StatelessWidget {
  final String imageUrl;

  const _ImageBubble({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFullScreenImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: 200,
          height: 200,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: 200,
            height: 200,
            color: AppColors.surfaceVariant,
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (context, url, error) => Container(
            width: 200,
            height: 200,
            color: AppColors.surfaceVariant,
            child: const Icon(Icons.broken_image, color: AppColors.textHint),
          ),
        ),
      ),
    );
  }

  /// 全屏查看图片
  void _showFullScreenImage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenImageViewer(imageUrl: imageUrl),
      ),
    );
  }
}

/// 全屏图片查看器
class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;

  const _FullScreenImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) =>
                const CircularProgressIndicator(color: Colors.white),
            errorWidget: (context, url, error) =>
                const Icon(Icons.broken_image, color: Colors.white, size: 64),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Coupon 卡片气泡
// ============================================================

class _CouponBubble extends StatelessWidget {
  final Map<String, dynamic> payload;
  final void Function(String dealId) onViewDeal;

  const _CouponBubble({required this.payload, required this.onViewDeal});

  @override
  Widget build(BuildContext context) {
    // 从 payload 中提取字段（null-safe）
    final dealTitle = payload['deal_title'] as String? ?? 'Deal';
    final merchantName = payload['merchant_name'] as String? ?? '';
    final amount = payload['amount'];
    final dealId = payload['deal_id'] as String? ?? '';
    final dealImageUrl = payload['deal_image_url'] as String?;
    final expiresAt = payload['expires_at'] as String?;

    // 格式化价格
    String priceText = '';
    if (amount != null) {
      final price = double.tryParse(amount.toString()) ?? 0.0;
      priceText = '\$${price.toStringAsFixed(2)}';
    }

    // 格式化过期时间
    String expText = '';
    if (expiresAt != null) {
      final dt = DateTime.tryParse(expiresAt);
      if (dt != null) {
        expText = 'Exp: ${DateFormat('MMM d').format(dt)}';
      }
    }

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
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
          // 顶部图片
          if (dealImageUrl != null && dealImageUrl.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: CachedNetworkImage(
                imageUrl: dealImageUrl,
                height: 100,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: 100,
                  color: AppColors.surfaceVariant,
                ),
                errorWidget: (context, url, error) => Container(
                  height: 100,
                  color: AppColors.surfaceVariant,
                  child: const Icon(Icons.image, color: AppColors.textHint),
                ),
              ),
            ),

          // 券标题行
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                const Icon(Icons.confirmation_number,
                    color: AppColors.primary, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    dealTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 商家名
          if (merchantName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                merchantName,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),

          // 价格 + 过期时间
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                if (priceText.isNotEmpty)
                  Text(
                    priceText,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                const Spacer(),
                if (expText.isNotEmpty)
                  Text(
                    expText,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          // View Deal 按钮
          GestureDetector(
            onTap: dealId.isNotEmpty ? () => onViewDeal(dealId) : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: const Text(
                'View Deal',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// System 消息（居中小标签）
// ============================================================

class _SystemMessageBubble extends StatelessWidget {
  final String content;

  const _SystemMessageBubble({required this.content});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEEEEEE),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          content,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 头像组件
// ============================================================

class _Avatar extends StatelessWidget {
  final String? avatarUrl;

  const _Avatar({this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 16,
        backgroundImage: CachedNetworkImageProvider(avatarUrl!),
        backgroundColor: AppColors.surfaceVariant,
      );
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppColors.surfaceVariant,
      child: const Icon(Icons.person, size: 18, color: AppColors.textHint),
    );
  }
}

// ============================================================
// 时间戳组件
// ============================================================

class _TimeStamp extends StatelessWidget {
  final DateTime time;
  final bool isMine;

  const _TimeStamp({required this.time, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return Text(
      DateFormat('h:mm a').format(time),
      style: const TextStyle(
        fontSize: 10,
        color: AppColors.textHint,
      ),
    );
  }
}

// ============================================================
// 日期分隔符（不同日期之间显示）
// ============================================================

class _DateSeparator extends StatelessWidget {
  final DateTime date;

  const _DateSeparator({required this.date});

  /// 格式化日期：Today / Yesterday / Mar 20, 2026
  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(msgDay).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEEEEEE),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
