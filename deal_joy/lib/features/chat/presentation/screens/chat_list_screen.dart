// 会话列表主页（Chat Tab 入口）
// 客服会话固定在顶部，其余会话按时间倒序排列
// 右上角支持添加好友 / 进入通知中心

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/chat_repository.dart';
import '../../domain/providers/chat_provider.dart';
import '../../domain/providers/friend_provider.dart';
import '../../domain/providers/notification_provider.dart';
import '../../data/models/conversation_model.dart';
import '../widgets/conversation_tile.dart';
import '../../../auth/domain/providers/auth_provider.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationsProvider);
    final unreadNotifCount = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;
    final pendingRequestCount = ref.watch(pendingRequestCountProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // AppBar 区域
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Chats',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  // 添加好友按钮
                  _AppBarIconButton(
                    icon: Icons.person_add_outlined,
                    badge: pendingRequestCount,
                    onTap: () => context.push('/chat/friends'),
                  ),
                  const SizedBox(width: 4),
                  // 通知中心按钮
                  _AppBarIconButton(
                    icon: Icons.notifications_outlined,
                    badge: unreadNotifCount,
                    onTap: () => context.push('/chat/notifications'),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),

            // 搜索栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: GestureDetector(
                onTap: () => context.push('/chat/search'),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: const Row(
                    children: [
                      Icon(Icons.search, size: 18, color: AppColors.textHint),
                      SizedBox(width: 8),
                      Text(
                        'Search users, chats...',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 会话列表
            Expanded(
              child: conversationsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 40),
                      const SizedBox(height: 8),
                      Text(
                        'Failed to load chats',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () =>
                            ref.read(conversationsProvider.notifier).refresh(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (conversations) => _ConversationList(
                  conversations: conversations,
                  onRefresh: () =>
                      ref.read(conversationsProvider.notifier).refresh(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 会话列表主体，分组展示客服会话和普通会话
class _ConversationList extends ConsumerWidget {
  final List<ConversationModel> conversations;
  final Future<void> Function() onRefresh;

  const _ConversationList({
    required this.conversations,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 分离客服会话和其他会话
    final supportConvs = conversations.where((c) => c.type == 'support').toList();
    final otherConvs = conversations.where((c) => c.type != 'support').toList();

    // 置顶的排在前面，其次按更新时间倒序
    otherConvs.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });

    if (conversations.isEmpty) {
      return const _EmptyState();
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
        children: [
          // 客服会话分组
          if (supportConvs.isNotEmpty) ...[
            _SectionHeader(label: 'Support'),
            ...supportConvs.map((c) => ConversationTile(
                  conversation: c,
                  onTap: () => context.push('/chat/${c.id}'),
                )),
            const SizedBox(height: 8),
          ],

          // 好友/群聊分组
          if (otherConvs.isNotEmpty) ...[
            _SectionHeader(label: 'Messages'),
            ...otherConvs.map((c) => _SwipeableConversationTile(
                  conversation: c,
                  onTap: () => context.push('/chat/${c.id}'),
                  onPin: () => _togglePin(ref, c),
                  onDelete: () => _deleteConversation(context, ref, c),
                )),
          ],
        ],
      ),
    );
  }

  void _togglePin(WidgetRef ref, ConversationModel c) async {
    final userId = ref.read(currentUserProvider).valueOrNull?.id;
    if (userId == null) return;
    await ref.read(chatRepositoryProvider).togglePin(c.id, userId, !c.isPinned);
    ref.read(conversationsProvider.notifier).refresh();
  }

  void _deleteConversation(BuildContext context, WidgetRef ref, ConversationModel c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: const Text('This conversation will be removed from your list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final userId = ref.read(currentUserProvider).valueOrNull?.id;
              if (userId == null) return;
              await ref.read(chatRepositoryProvider).leaveConversation(c.id, userId);
              ref.read(conversationsProvider.notifier).refresh();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// 支持左滑操作的会话 tile（Pin + Delete）
class _SwipeableConversationTile extends StatefulWidget {
  final ConversationModel conversation;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  const _SwipeableConversationTile({
    required this.conversation,
    required this.onTap,
    required this.onPin,
    required this.onDelete,
  });

  @override
  State<_SwipeableConversationTile> createState() =>
      _SwipeableConversationTileState();
}

class _SwipeableConversationTileState
    extends State<_SwipeableConversationTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnim;
  // 按钮总宽度（Pin 64 + Delete 64）
  static const _actionWidth = 128.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _slideAnim = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-_actionWidth, 0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isOpen = false;

  void _toggle() {
    if (_isOpen) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    _isOpen = !_isOpen;
  }

  void _close() {
    if (_isOpen) {
      _controller.reverse();
      _isOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPinned = widget.conversation.isPinned;

    return SizedBox(
      height: 78, // ConversationTile 大约高度
      child: Stack(
        children: [
          // 右侧操作按钮（固定在底层）
          Positioned(
            right: 0,
            top: 0,
            bottom: 10, // 匹配 ConversationTile margin
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pin 按钮
                GestureDetector(
                  onTap: () {
                    _close();
                    widget.onPin();
                  },
                  child: Container(
                    width: 64,
                    color: isPinned ? AppColors.textSecondary : AppColors.primary,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isPinned ? 'Unpin' : 'Pin',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Delete 按钮
                GestureDetector(
                  onTap: () {
                    _close();
                    widget.onDelete();
                  },
                  child: Container(
                    width: 64,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(12),
                      ),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_outline, color: Colors.white, size: 20),
                        SizedBox(height: 2),
                        Text(
                          'Delete',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 滑动的会话卡片
          AnimatedBuilder(
            animation: _slideAnim,
            builder: (context, child) {
              return Transform.translate(
                offset: _slideAnim.value,
                child: child,
              );
            },
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                // 左滑打开，右滑关闭
                final delta = details.primaryDelta ?? 0;
                if (delta < -5 && !_isOpen) _toggle();
                if (delta > 5 && _isOpen) _toggle();
              },
              onTap: () {
                if (_isOpen) {
                  _close();
                } else {
                  widget.onTap();
                }
              },
              child: ConversationTile(
                conversation: widget.conversation,
                onTap: () {}, // 由外层 GestureDetector 处理
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 分组标题
class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textHint,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// 右上角图标按钮，支持 badge
class _AppBarIconButton extends StatelessWidget {
  final IconData icon;
  final int badge;
  final VoidCallback onTap;

  const _AppBarIconButton({
    required this.icon,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 20),
          ),
          // 数字 badge
          if (badge > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// 空状态提示
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 64,
            color: AppColors.textHint.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No conversations yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
