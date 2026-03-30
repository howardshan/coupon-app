// 分享给好友的底部弹窗
// 展示好友列表，支持多选，发送 deal/merchant 分享消息

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/friend_model.dart';
import '../../domain/providers/chat_provider.dart';
import '../../domain/providers/friend_provider.dart';

/// 分享给好友弹窗
/// [payload] 包含分享数据，必须有 'type' 字段（'deal_share' / 'merchant_share'）
class ShareToFriendSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> payload;

  const ShareToFriendSheet({super.key, required this.payload});

  @override
  ConsumerState<ShareToFriendSheet> createState() => _ShareToFriendSheetState();
}

class _ShareToFriendSheetState extends ConsumerState<ShareToFriendSheet> {
  final _searchCtrl = TextEditingController();
  final _selectedIds = <String>{};
  bool _isSending = false;
  String _filterText = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _send(List<FriendModel> friends) async {
    final userId = ref.read(currentUserProvider).valueOrNull?.id;
    if (userId == null || _selectedIds.isEmpty) return;

    setState(() => _isSending = true);
    final repo = ref.read(chatRepositoryProvider);
    int sentCount = 0;

    for (final fid in _selectedIds) {
      try {
        // 获取或创建 direct 会话
        final convId = await repo.getOrCreateDirectChat(userId, fid);
        // 发送分享消息
        await repo.sendShareMessage(convId, userId, widget.payload);
        sentCount++;
      } catch (e) {
        debugPrint('[ShareToFriend] send failed for $fid: $e');
      }
    }

    // 刷新会话列表
    ref.invalidate(conversationsProvider);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shared to $sentCount friend(s)'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Share to Friends',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          // 搜索框
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _filterText = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search friends...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 好友列表
          Flexible(
            child: friendsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('Failed to load friends')),
              data: (friends) {
                final filtered = _filterText.isEmpty
                    ? friends
                    : friends.where((f) {
                        final name = f.displayName.toLowerCase();
                        final uname = (f.username ?? '').toLowerCase();
                        return name.contains(_filterText) || uname.contains(_filterText);
                      }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No friends found',
                        style: TextStyle(color: AppColors.textHint),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _FriendItem(
                    friend: filtered[i],
                    isSelected: _selectedIds.contains(filtered[i].friendId),
                    onToggle: () {
                      setState(() {
                        if (_selectedIds.contains(filtered[i].friendId)) {
                          _selectedIds.remove(filtered[i].friendId);
                        } else {
                          _selectedIds.add(filtered[i].friendId);
                        }
                      });
                    },
                  ),
                );
              },
            ),
          ),
          // 底部发送按钮
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _selectedIds.isEmpty || _isSending
                      ? null
                      : () => _send(ref.read(friendsProvider).valueOrNull ?? []),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: const StadiumBorder(),
                  ),
                  child: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _selectedIds.isEmpty
                              ? 'Select friends'
                              : 'Send (${_selectedIds.length})',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
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

// 好友列表项
class _FriendItem extends StatelessWidget {
  final FriendModel friend;
  final bool isSelected;
  final VoidCallback onToggle;

  const _FriendItem({
    required this.friend,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onToggle,
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.surfaceVariant,
        backgroundImage: friend.avatarUrl != null
            ? CachedNetworkImageProvider(friend.avatarUrl!)
            : null,
        child: friend.avatarUrl == null
            ? Text(
                friend.displayName[0].toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      title: Text(
        friend.displayName,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      subtitle: friend.username != null
          ? Text(
              '@${friend.username}',
              style: const TextStyle(fontSize: 12, color: AppColors.textHint),
            )
          : null,
      trailing: Checkbox(
        value: isSelected,
        onChanged: (_) => onToggle(),
        activeColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}
