// 会话列表主页（Chat Tab 入口）
// 客服会话固定在顶部，其余会话按时间倒序排列
// 右上角支持添加好友 / 进入通知中心

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/chat_provider.dart';
import '../../domain/providers/friend_provider.dart';
import '../../domain/providers/notification_provider.dart';
import '../../data/models/conversation_model.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/search_user_dialog.dart';

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
      // 搜索用户 / 新建聊天 FAB
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const SearchUserDialog(),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }
}

// 会话列表主体，分组展示客服会话和普通会话
class _ConversationList extends StatelessWidget {
  final List<ConversationModel> conversations;
  final Future<void> Function() onRefresh;

  const _ConversationList({
    required this.conversations,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    // 分离客服会话和其他会话
    final supportConvs = conversations.where((c) => c.type == 'support').toList();
    final otherConvs = conversations.where((c) => c.type != 'support').toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (conversations.isEmpty) {
      return _EmptyState(onAdd: () => context.push('/chat/friends'));
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
            ...otherConvs.map((c) => ConversationTile(
                  conversation: c,
                  onTap: () => context.push('/chat/${c.id}'),
                )),
          ],
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
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

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
          const SizedBox(height: 8),
          const Text(
            'Add friends to start chatting',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add_outlined, size: 18),
            label: const Text('Add Friends'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
