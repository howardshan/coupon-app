// 好友申请页
// 分组展示收到的申请（Received）和发出的申请（Sent）

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/friend_model.dart';
import '../../domain/providers/friend_provider.dart';

/// 发出的申请列表 Provider（当前用户作为 sender、status=pending）
final _sentRequestsProvider = FutureProvider<List<FriendRequestModel>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return [];
  final client = ref.watch(friendRepositoryProvider);
  return client.fetchSentRequests(user.id);
});

class FriendRequestsScreen extends ConsumerWidget {
  const FriendRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receivedAsync = ref.watch(pendingFriendRequestsProvider);
    final sentAsync = ref.watch(_sentRequestsProvider);

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
          'Friend Requests',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(pendingFriendRequestsProvider);
          ref.invalidate(_sentRequestsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // 收到的申请
            _SectionHeader(label: 'Received'),
            receivedAsync.when(
              loading: () => const _LoadingItem(),
              error: (e, _) => _ErrorItem(message: 'Failed to load received requests'),
              data: (requests) => requests.isEmpty
                  ? const _EmptyItem(message: 'No received requests')
                  : Column(
                      children: requests
                          .map((r) => _ReceivedRequestTile(request: r))
                          .toList(),
                    ),
            ),

            const SizedBox(height: 16),

            // 发出的申请
            _SectionHeader(label: 'Sent'),
            sentAsync.when(
              loading: () => const _LoadingItem(),
              error: (e, _) => _ErrorItem(message: 'Failed to load sent requests'),
              data: (requests) => requests.isEmpty
                  ? const _EmptyItem(message: 'No sent requests')
                  : Column(
                      children: requests
                          .map((r) => _SentRequestTile(request: r))
                          .toList(),
                    ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textHint,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// 加载中占位
class _LoadingItem extends StatelessWidget {
  const _LoadingItem();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}

// 错误占位
class _ErrorItem extends StatelessWidget {
  final String message;

  const _ErrorItem({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.error, fontSize: 13),
      ),
    );
  }
}

// 空状态占位
class _EmptyItem extends StatelessWidget {
  final String message;

  const _EmptyItem({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.textHint, fontSize: 13),
      ),
    );
  }
}

// 收到的申请列表项：显示发送者信息 + Accept / Decline 按钮
class _ReceivedRequestTile extends ConsumerWidget {
  final FriendRequestModel request;

  const _ReceivedRequestTile({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // 头像
          _Avatar(
            avatarUrl: request.senderAvatarUrl,
            displayName: request.senderName ?? request.senderUsername ?? '?',
          ),
          const SizedBox(width: 12),
          // 名称信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.senderName ?? request.senderUsername ?? 'Unknown',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (request.senderUsername != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@${request.senderUsername}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 操作按钮
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Decline 按钮（红色边框）
              OutlinedButton(
                onPressed: () => _respond(context, ref, accept: false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  minimumSize: const Size(64, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Decline', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              // Accept 按钮（橙色填充）
              ElevatedButton(
                onPressed: () => _respond(context, ref, accept: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(64, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: const Text('Accept', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref, {
    required bool accept,
  }) async {
    try {
      await ref
          .read(friendRepositoryProvider)
          .respondToFriendRequest(request.id, accept);

      // 刷新申请列表和好友列表
      ref.invalidate(pendingFriendRequestsProvider);
      if (accept) ref.invalidate(friendsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept ? 'Friend request accepted' : 'Friend request declined',
            ),
            backgroundColor: accept ? AppColors.success : AppColors.textSecondary,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

// 发出的申请列表项：显示接收者信息 + Cancel 按钮
class _SentRequestTile extends ConsumerWidget {
  final FriendRequestModel request;

  const _SentRequestTile({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // 头像
          _Avatar(
            avatarUrl: request.receiverAvatarUrl,
            displayName: request.receiverName ?? request.receiverUsername ?? '?',
          ),
          const SizedBox(width: 12),
          // 名称信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.receiverName ?? request.receiverUsername ?? 'Unknown',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (request.receiverUsername != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@${request.receiverUsername}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 状态/取消按钮
          if (request.isPending)
            OutlinedButton(
              onPressed: () => _cancelRequest(context, ref),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                minimumSize: const Size(64, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 12)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                request.status.capitalize(),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _cancelRequest(BuildContext context, WidgetRef ref) async {
    try {
      // 取消申请：将状态改为 cancelled
      await ref
          .read(friendRepositoryProvider)
          .cancelFriendRequest(request.id);

      ref.invalidate(_sentRequestsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request cancelled'),
            backgroundColor: AppColors.textSecondary,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

// 圆形头像组件
class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  final String displayName;

  const _Avatar({
    required this.avatarUrl,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    const double size = 44;
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => _placeholder(size),
          errorWidget: (context, url, error) => _placeholder(size),
        ),
      );
    }
    return _placeholder(size);
  }

  Widget _placeholder(double size) {
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

// String 扩展：首字母大写
extension _StringExt on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
