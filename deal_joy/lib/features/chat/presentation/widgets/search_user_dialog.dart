// 搜索用户弹窗组件
// 通过用户名 / 邮箱 / 手机号搜索用户，展示结果并支持发送好友申请

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/friend_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';

/// 搜索用户弹窗，从 ChatListScreen / FriendListScreen 触发
class SearchUserDialog extends ConsumerStatefulWidget {
  const SearchUserDialog({super.key});

  @override
  ConsumerState<SearchUserDialog> createState() => _SearchUserDialogState();
}

class _SearchUserDialogState extends ConsumerState<SearchUserDialog> {
  final _controller = TextEditingController();

  /// 搜索结果列表（原始 Map）
  List<Map<String, dynamic>> _results = [];

  /// 正在加载搜索结果
  bool _loading = false;

  /// 正在发送好友申请的用户 ID 集合（防止重复点击）
  final Set<String> _sendingIds = {};

  /// 已发送申请的用户 ID 集合（在本次弹窗会话中记录）
  final Set<String> _sentIds = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 执行搜索
  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() => _results = []);
      return;
    }

    final currentUser = await ref.read(currentUserProvider.future);
    if (currentUser == null) return;

    setState(() => _loading = true);

    try {
      final results = await ref
          .read(friendRepositoryProvider)
          .searchUsers(trimmed, currentUser.id);
      if (mounted) {
        setState(() {
          _results = results;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    }
  }

  /// 发送好友申请
  Future<void> _sendRequest(String targetUserId) async {
    final currentUser = await ref.read(currentUserProvider.future);
    if (currentUser == null) return;

    setState(() => _sendingIds.add(targetUserId));

    try {
      await ref
          .read(friendRepositoryProvider)
          .sendFriendRequest(currentUser.id, targetUserId);

      if (mounted) {
        setState(() {
          _sendingIds.remove(targetUserId);
          _sentIds.add(targetUserId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request sent!')),
        );
        // 刷新好友申请列表 badge
        ref.invalidate(pendingFriendRequestsProvider);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingIds.remove(targetUserId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send request: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            const Text(
              'Find People',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 14),

            // 搜索输入框
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              onChanged: (v) {
                // 清空时重置结果
                if (v.isEmpty) setState(() => _results = []);
              },
              decoration: InputDecoration(
                hintText: 'Search by name, email or phone',
                hintStyle: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 14,
                ),
                prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _controller.clear();
                              setState(() => _results = []);
                            },
                          )
                        : null,
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // 搜索结果
            if (_results.isEmpty && !_loading && _controller.text.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'No users found',
                    style: TextStyle(color: AppColors.textHint, fontSize: 14),
                  ),
                ),
              )
            else if (_results.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final user = _results[index];
                    final userId = user['id'] as String? ?? '';
                    final name = user['full_name'] as String? ?? '';
                    final username = user['username'] as String? ?? '';
                    final avatarUrl = user['avatar_url'] as String?;
                    final isSending = _sendingIds.contains(userId);
                    final isSent = _sentIds.contains(userId);

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      leading: _UserAvatar(avatarUrl: avatarUrl),
                      title: Text(
                        name.isNotEmpty ? name : username,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: username.isNotEmpty
                          ? Text(
                              '@$username',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textHint,
                              ),
                            )
                          : null,
                      trailing: isSent
                          ? const Text(
                              'Sent',
                              style: TextStyle(
                                color: AppColors.textHint,
                                fontSize: 13,
                              ),
                            )
                          : isSending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                )
                              : TextButton(
                                  onPressed: () => _sendRequest(userId),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: const BorderSide(
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'Add Friend',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 8),

            // 底部搜索按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _search(_controller.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Search', style: TextStyle(fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 用户头像组件
class _UserAvatar extends StatelessWidget {
  final String? avatarUrl;

  const _UserAvatar({this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: avatarUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          placeholder: (_, _) => _placeholder,
          errorWidget: (_, _, _) => _placeholder,
        ),
      );
    }
    return _placeholder;
  }

  Widget get _placeholder => Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: AppColors.surfaceVariant,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.person, color: AppColors.textHint, size: 20),
      );
}
