// 群聊创建页面
// 用户输入群名、从好友列表多选成员后创建群聊
// 路由：/chat/create-group

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/friend_model.dart';
import '../../domain/providers/chat_provider.dart';
import '../../domain/providers/friend_provider.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  /// 群名输入 controller
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// 已选中的好友 user ID 集合
  final Set<String> _selectedIds = {};

  /// 是否正在提交创建请求
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ============================================================
  // 创建群聊
  // ============================================================

  Future<void> _createGroup() async {
    // 表单校验（群名不能为空）
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 至少选 1 个好友
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least 1 member'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final currentUserId = ref.read(currentUserProvider).valueOrNull?.id;
    if (currentUserId == null) return;

    setState(() => _isCreating = true);

    try {
      final conversation = await ref.read(chatRepositoryProvider).createGroupChat(
            creatorId: currentUserId,
            name: _nameController.text.trim(),
            memberIds: _selectedIds.toList(),
          );

      // 刷新会话列表，让新群聊出现在列表中
      await ref.read(conversationsProvider.notifier).refresh();

      if (mounted) {
        // 跳转到新建的群聊详情页
        context.go('/chat/${conversation.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create group: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  // ============================================================
  // 选中 / 取消好友
  // ============================================================

  void _toggleFriend(String friendId) {
    setState(() {
      if (_selectedIds.contains(friendId)) {
        _selectedIds.remove(friendId);
      } else {
        _selectedIds.add(friendId);
      }
    });
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black12,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'New Group',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          // 右上角创建按钮
          _isCreating
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _createGroup,
                  child: const Text(
                    'Create',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 群名输入区域
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'Group Name',
                  hintStyle: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 15,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                  prefixIcon: const Icon(
                    Icons.group_outlined,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Group name is required';
                  }
                  if (value.trim().length > 50) {
                    return 'Group name must be under 50 characters';
                  }
                  return null;
                },
              ),
            ),

            const SizedBox(height: 8),

            // 好友选择区域标题
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  const Text(
                    'Select Members',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textHint,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  // 显示已选数量
                  if (_selectedIds.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_selectedIds.length} selected',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 好友列表
            Expanded(
              child: friendsAsync.when(
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
                      const Text(
                        'Failed to load friends',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                data: (friends) => friends.isEmpty
                    ? _EmptyFriendsHint()
                    : _FriendSelectList(
                        friends: friends,
                        selectedIds: _selectedIds,
                        onToggle: _toggleFriend,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 好友选择列表
// ============================================================

class _FriendSelectList extends StatelessWidget {
  final List<FriendModel> friends;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  const _FriendSelectList({
    required this.friends,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: friends.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        indent: 72,
        endIndent: 20,
        color: AppColors.surfaceVariant,
      ),
      itemBuilder: (context, index) {
        final friend = friends[index];
        final isSelected = selectedIds.contains(friend.friendId);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 4,
          ),
          // 头像
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.surfaceVariant,
            backgroundImage: friend.avatarUrl != null && friend.avatarUrl!.isNotEmpty
                ? NetworkImage(friend.avatarUrl!)
                : null,
            child: friend.avatarUrl == null || friend.avatarUrl!.isEmpty
                ? Text(
                    friend.displayName.isNotEmpty
                        ? friend.displayName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          // 显示名
          title: Text(
            friend.displayName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          // 用户名 @xxx
          subtitle: friend.username != null
              ? Text(
                  '@${friend.username}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textHint,
                  ),
                )
              : null,
          // 右侧勾选框
          trailing: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? AppColors.primary : Colors.transparent,
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textHint,
                width: 1.5,
              ),
            ),
            child: isSelected
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
          onTap: () => onToggle(friend.friendId),
        );
      },
    );
  }
}

// ============================================================
// 没有好友时的空状态提示
// ============================================================

class _EmptyFriendsHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline,
            size: 56,
            color: AppColors.textHint.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          const Text(
            'No friends yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add friends first to create a group',
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
