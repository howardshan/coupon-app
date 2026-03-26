// 好友管理页
// 展示当前用户的好友列表，支持删除好友和搜索用户

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/friend_model.dart';
import '../../domain/providers/friend_provider.dart';
import '../widgets/search_user_dialog.dart';

class FriendListScreen extends ConsumerWidget {
  const FriendListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendsAsync = ref.watch(friendsProvider);
    final pendingCount = ref.watch(pendingRequestCountProvider);

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
          'Friends',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          // 搜索用户按钮
          IconButton(
            icon: const Icon(Icons.search, color: AppColors.textSecondary),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const SearchUserDialog(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 好友申请入口（有待处理申请时显示）
          if (pendingCount > 0)
            _FriendRequestsBanner(count: pendingCount),

          // 好友列表主体
          Expanded(
            child: friendsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 40,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Failed to load friends',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => ref.invalidate(friendsProvider),
                      child: const Text(
                        'Retry',
                        style: TextStyle(color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
              data: (friends) => friends.isEmpty
                  ? _EmptyFriendsState(
                      onSearch: () => showDialog(
                        context: context,
                        builder: (_) => const SearchUserDialog(),
                      ),
                    )
                  : _FriendsList(friends: friends),
            ),
          ),
        ],
      ),
    );
  }
}

// 好友申请入口 Banner
class _FriendRequestsBanner extends StatelessWidget {
  final int count;

  const _FriendRequestsBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/chat/friend-requests'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            bottom: BorderSide(
              color: AppColors.surfaceVariant,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_add_outlined,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Friend Requests ($count)',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textHint,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// 好友列表
class _FriendsList extends ConsumerWidget {
  final List<FriendModel> friends;

  const _FriendsList({required this.friends});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: friends.length,
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        indent: 72,
        endIndent: 20,
        color: AppColors.surfaceVariant,
      ),
      itemBuilder: (context, index) {
        final friend = friends[index];
        return _FriendTile(
          friend: friend,
          onRemove: () => _confirmRemoveFriend(context, ref, friend),
        );
      },
    );
  }

  // 确认删除好友的对话框
  Future<void> _confirmRemoveFriend(
    BuildContext context,
    WidgetRef ref,
    FriendModel friend,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Friend'),
        content: Text(
          'Are you sure you want to remove ${friend.displayName} from your friends?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final currentUser = await ref.read(currentUserProvider.future);
        if (currentUser == null) return;

        await ref
            .read(friendRepositoryProvider)
            .removeFriend(currentUser.id, friend.friendId);

        // 刷新好友列表
        ref.invalidate(friendsProvider);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${friend.displayName} removed from friends'),
              backgroundColor: AppColors.textSecondary,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to remove friend: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
}

// 单个好友列表项
class _FriendTile extends StatelessWidget {
  final FriendModel friend;
  final VoidCallback onRemove;

  const _FriendTile({
    required this.friend,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onLongPress: () => _showOptionsBottomSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            // 头像
            _Avatar(
              avatarUrl: friend.avatarUrl,
              displayName: friend.displayName,
            ),
            const SizedBox(width: 12),
            // 名称信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend.displayName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (friend.username != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '@${friend.username}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 长按弹出操作菜单
  void _showOptionsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.textHint.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  _Avatar(
                    avatarUrl: friend.avatarUrl,
                    displayName: friend.displayName,
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    friend.displayName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 删除好友选项
            ListTile(
              leading: const Icon(Icons.person_remove_outlined, color: AppColors.error),
              title: const Text(
                'Remove Friend',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                onRemove();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// 圆形头像组件
class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  final String displayName;
  final double size;

  const _Avatar({
    required this.avatarUrl,
    required this.displayName,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => _PlaceholderAvatar(
            displayName: displayName,
            size: size,
          ),
          errorWidget: (context, url, error) => _PlaceholderAvatar(
            displayName: displayName,
            size: size,
          ),
        ),
      );
    }
    return _PlaceholderAvatar(displayName: displayName, size: size);
  }
}

// 无头像时的占位头像
class _PlaceholderAvatar extends StatelessWidget {
  final String displayName;
  final double size;

  const _PlaceholderAvatar({
    required this.displayName,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
      child: Text(
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
        style: TextStyle(
          color: AppColors.primary,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// 无好友时的空状态
class _EmptyFriendsState extends StatelessWidget {
  final VoidCallback onSearch;

  const _EmptyFriendsState({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: AppColors.textHint.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No friends yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Search for people to add as friends',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onSearch,
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Search and add friends'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
