// Chat 搜索页 — 搜索用户 + 历史聊天消息关键词
// 输入即搜索（debounce 300ms），结果分两组：Users / Messages

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../domain/providers/friend_provider.dart';

class ChatSearchScreen extends ConsumerStatefulWidget {
  const ChatSearchScreen({super.key});

  @override
  ConsumerState<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends ConsumerState<ChatSearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _userResults = [];
  List<Map<String, dynamic>> _messageResults = [];
  bool _isLoading = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final query = _controller.text.trim();
    if (query == _lastQuery) return;
    _lastQuery = query;

    if (query.isEmpty) {
      setState(() {
        _userResults = [];
        _messageResults = [];
      });
      return;
    }

    // debounce 300ms
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_controller.text.trim() == query) {
        _search(query);
      }
    });
  }

  Future<void> _search(String query) async {
    final userId = ref.read(currentUserProvider).valueOrNull?.id;
    if (userId == null) return;

    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;

      // 先获取好友 ID 列表，只搜索已添加的好友
      final friendsList = ref.read(friendsProvider).valueOrNull ?? [];
      final friendUserIds = friendsList.map((f) => f.friendId).toList();

      // 搜索好友（从已有好友中按名字/用户名过滤）
      Future<List<dynamic>> userFuture;
      if (friendUserIds.isEmpty) {
        userFuture = Future.value([]);
      } else {
        userFuture = client
            .from('users')
            .select('id, full_name, username, avatar_url')
            .inFilter('id', friendUserIds)
            .or(
              'username.ilike.%$query%,'
              'full_name.ilike.%$query%',
            )
            .limit(10);
      }

      // 搜索当前用户参与的会话中的消息
      // 先获取用户的会话 ID
      final memberRows = await client
          .from('conversation_members')
          .select('conversation_id')
          .eq('user_id', userId);
      final convIds = (memberRows as List)
          .map((r) => r['conversation_id'] as String)
          .toList();

      List<Map<String, dynamic>> msgResults = [];
      if (convIds.isNotEmpty) {
        final msgRows = await client
            .from('messages')
            .select('id, conversation_id, sender_id, content, type, created_at')
            .inFilter('conversation_id', convIds)
            .eq('type', 'text')
            .ilike('content', '%$query%')
            .order('created_at', ascending: false)
            .limit(20);

        // 批量查发送者信息 + 会话信息
        final senderIds = <String>{};
        final msgConvIds = <String>{};
        for (final m in msgRows as List) {
          if (m['sender_id'] != null) senderIds.add(m['sender_id'] as String);
          msgConvIds.add(m['conversation_id'] as String);
        }

        final senderMap = <String, Map<String, dynamic>>{};
        if (senderIds.isNotEmpty) {
          final users = await client
              .from('users')
              .select('id, full_name, avatar_url')
              .inFilter('id', senderIds.toList());
          for (final u in users as List) {
            senderMap[u['id'] as String] = u as Map<String, dynamic>;
          }
        }

        final convMap = <String, Map<String, dynamic>>{};
        if (msgConvIds.isNotEmpty) {
          final convs = await client
              .from('conversations')
              .select('id, type, name')
              .inFilter('id', msgConvIds.toList());
          for (final c in convs as List) {
            convMap[c['id'] as String] = c as Map<String, dynamic>;
          }
        }

        msgResults = (msgRows).map((m) {
          final sender = senderMap[m['sender_id'] as String?];
          final conv = convMap[m['conversation_id'] as String];
          return {
            ...Map<String, dynamic>.from(m as Map),
            'sender_name': sender?['full_name'] as String? ?? '',
            'sender_avatar_url': sender?['avatar_url'] as String?,
            'conv_name': conv?['name'] as String?,
            'conv_type': conv?['type'] as String? ?? 'direct',
          };
        }).toList();
      }

      final userRows = await userFuture;

      if (mounted) {
        setState(() {
          _userResults = (userRows as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _messageResults = msgResults;
        });
      }
    } catch (_) {
      // 搜索失败静默处理
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 打开与好友的聊天（查找已有 direct 会话或创建新的）
  Future<void> _openChatWithUser(String friendUserId) async {
    final userId = ref.read(currentUserProvider).valueOrNull?.id;
    if (userId == null) return;

    try {
      final client = Supabase.instance.client;

      // 查找两人共同的 direct 会话
      final myConvs = await client
          .from('conversation_members')
          .select('conversation_id')
          .eq('user_id', userId);
      final myConvIds = (myConvs as List)
          .map((r) => r['conversation_id'] as String)
          .toList();

      String? existingConvId;
      if (myConvIds.isNotEmpty) {
        // 找对方也在的 direct 会话
        final shared = await client
            .from('conversation_members')
            .select('conversation_id, conversations!inner(type)')
            .eq('user_id', friendUserId)
            .inFilter('conversation_id', myConvIds);

        for (final row in shared as List) {
          final conv = row['conversations'] as Map<String, dynamic>?;
          if (conv?['type'] == 'direct') {
            existingConvId = row['conversation_id'] as String;
            break;
          }
        }
      }

      if (existingConvId != null) {
        if (mounted) context.push('/chat/$existingConvId');
        return;
      }

      // 没有已有会话，通过 RPC 创建（SECURITY DEFINER 绕过 RLS）
      final newConvId = await client.rpc('create_direct_conversation', params: {
        'p_user_id': userId,
        'p_friend_id': friendUserId,
      }) as String;

      if (mounted) context.push('/chat/$newConvId');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open chat: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _sendFriendRequest(String receiverId) async {
    final userId = ref.read(currentUserProvider).valueOrNull?.id;
    if (userId == null) return;

    try {
      await ref.read(friendRepositoryProvider).sendFriendRequest(userId, receiverId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request sent!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final friendIds = ref.watch(friendsProvider).valueOrNull
        ?.map((f) => f.friendId)
        .toSet() ?? {};
    final hasResults = _userResults.isNotEmpty || _messageResults.isNotEmpty;
    final isEmpty = _controller.text.isNotEmpty && !_isLoading && !hasResults;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black12,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppColors.textPrimary,
          onPressed: () => context.pop(),
        ),
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: const TextStyle(fontSize: 15),
          decoration: const InputDecoration(
            hintText: 'Search users, messages...',
            hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: AppColors.textSecondary,
              onPressed: () {
                _controller.clear();
                setState(() {
                  _userResults = [];
                  _messageResults = [];
                });
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : isEmpty
              ? const Center(
                  child: Text(
                    'No results found',
                    style: TextStyle(color: AppColors.textHint, fontSize: 14),
                  ),
                )
              : !hasResults
                  ? const Center(
                      child: Text(
                        'Search for users or chat messages',
                        style: TextStyle(color: AppColors.textHint, fontSize: 14),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        // 用户搜索结果
                        if (_userResults.isNotEmpty) ...[
                          _SectionHeader(
                            label: 'Users',
                            count: _userResults.length,
                          ),
                          ..._userResults.map((user) {
                            final uid = user['id'] as String? ?? '';
                            final name = user['full_name'] as String? ?? '';
                            final username = user['username'] as String? ?? '';
                            final avatarUrl = user['avatar_url'] as String?;
                            final isFriend = friendIds.contains(uid);

                            return ListTile(
                              leading: _Avatar(url: avatarUrl, icon: Icons.person),
                              title: Text(
                                name.isNotEmpty ? name : username,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                              subtitle: username.isNotEmpty
                                  ? Text('@$username',
                                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))
                                  : null,
                              // 点击好友跳转到聊天（创建或打开已有会话）
                              onTap: () => _openChatWithUser(uid),
                            );
                          }),
                        ],

                        // 消息搜索结果
                        if (_messageResults.isNotEmpty) ...[
                          _SectionHeader(
                            label: 'Messages',
                            count: _messageResults.length,
                          ),
                          ..._messageResults.map((msg) {
                            final convId = msg['conversation_id'] as String? ?? '';
                            final content = msg['content'] as String? ?? '';
                            final senderName = msg['sender_name'] as String? ?? '';
                            final senderAvatar = msg['sender_avatar_url'] as String?;
                            final convName = msg['conv_name'] as String?;
                            final createdAt = msg['created_at'] != null
                                ? DateTime.tryParse(msg['created_at'] as String)
                                : null;

                            // 显示名：群名 > 发送者名
                            final displayName = convName ?? senderName;
                            final timeStr = createdAt != null
                                ? DateFormat('MMM d, h:mm a').format(createdAt)
                                : '';

                            return ListTile(
                              leading: _Avatar(url: senderAvatar, icon: Icons.chat_bubble_outline),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      displayName,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    timeStr,
                                    style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                                  ),
                                ],
                              ),
                              subtitle: _HighlightText(
                                text: content,
                                query: _controller.text.trim(),
                              ),
                              onTap: () => context.push('/chat/$convId'),
                            );
                          }),
                        ],
                      ],
                    ),
    );
  }
}

// ── 分组标题 ──────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  const _SectionHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        '$label ($count)',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textHint,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── 头像 ─────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final String? url;
  final IconData icon;
  const _Avatar({this.url, required this.icon});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFFF0F0F0),
      backgroundImage:
          url != null && url!.isNotEmpty ? CachedNetworkImageProvider(url!) : null,
      child: url == null || url!.isEmpty
          ? Icon(icon, color: AppColors.textHint, size: 22)
          : null,
    );
  }
}

// ── Friends 标签 ──────────────────────────────────────
class _StatusChip extends StatelessWidget {
  final String label;
  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    );
  }
}

// ── Add 按钮 ─────────────────────────────────────────
class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('Add',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

// ── 高亮匹配文本 ─────────────────────────────────────
class _HighlightText extends StatelessWidget {
  final String text;
  final String query;
  const _HighlightText({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary));
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final idx = lowerText.indexOf(lowerQuery);

    if (idx < 0) {
      return Text(text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary));
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + query.length),
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: text.substring(idx + query.length)),
        ],
      ),
    );
  }
}
