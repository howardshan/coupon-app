// 聊天详情页
// 显示指定会话的消息列表，支持发送文字消息和 Realtime 实时订阅
// 使用 ConsumerStatefulWidget：既能访问 Riverpod providers，又能管理 ScrollController 等本地状态

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/message_model.dart';
import '../../domain/providers/chat_provider.dart';
import '../../domain/providers/friend_provider.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/coupon_picker_sheet.dart';
import '../widgets/message_bubble.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  /// 会话 ID（从路由参数传入）
  final String conversationId;

  const ChatDetailScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  /// Supabase Realtime channel（用于监听新消息）
  RealtimeChannel? _realtimeChannel;

  /// 是否正在加载更多历史消息（防止重复触发）
  bool _isLoadingMore = false;

  /// 兜底用户名（当 conversationsProvider 中找不到时使用）
  String? _fallbackName;

  @override
  void initState() {
    super.initState();
    // 监听滚动到顶部，触发加载更多历史消息
    _scrollController.addListener(_onScroll);
    // 延迟执行，等 provider 初始化完成后再订阅 Realtime
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initRealtime();
      _markAsRead();
      _loadFallbackName();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  // ============================================================
  // Realtime 订阅
  // ============================================================

  /// 订阅 Supabase Realtime，监听当前会话的新消息插入事件
  void _initRealtime() {
    final currentUserId = _getCurrentUserId();
    if (currentUserId == null) return;

    _realtimeChannel = Supabase.instance.client
        .channel('messages:${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) {
            // 解析新消息
            final msg = MessageModel.fromJson(payload.newRecord);
            // 只处理对方发来的消息（自己发的消息在 send 时已本地添加）
            if (msg.senderId != currentUserId) {
              ref
                  .read(messagesProvider(widget.conversationId).notifier)
                  .addMessage(msg);
              // 自动标记已读
              _markAsRead();
              // 自动滚动到底部
              _scrollToBottom();
            }
          },
        )
        .subscribe();
  }

  // ============================================================
  // 标记已读
  // ============================================================

  /// 兜底加载对方用户名（当 conversationsProvider 中找不到时）
  Future<void> _loadFallbackName() async {
    final currentUserId = _getCurrentUserId();
    if (currentUserId == null) return;
    final name = await ref.read(chatRepositoryProvider).fetchOtherUserName(
          widget.conversationId,
          currentUserId,
        );
    if (mounted && name != null) {
      setState(() => _fallbackName = name);
    }
  }

  Future<void> _markAsRead() async {
    final currentUserId = _getCurrentUserId();
    if (currentUserId == null) return;
    try {
      await ref.read(chatRepositoryProvider).markAsRead(
            widget.conversationId,
            currentUserId,
          );
      // 刷新会话列表，更新未读计数
      ref.invalidate(conversationsProvider);
      ref.invalidate(totalUnreadCountProvider);
    } catch (_) {
      // 标记已读失败不影响用户体验，静默处理
    }
  }

  // ============================================================
  // 加载更多历史消息（滚动到顶部触发）
  // ============================================================

  void _onScroll() {
    // 列表用 reverse: true，滚到"顶部"实际是 maxScrollExtent
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 100 &&
        !_isLoadingMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final notifier =
        ref.read(messagesProvider(widget.conversationId).notifier);
    if (!notifier.hasMore) return;

    setState(() => _isLoadingMore = true);
    try {
      await notifier.loadMore();
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  // ============================================================
  // 发送消息
  // ============================================================

  Future<void> _sendTextMessage(String text) async {
    final currentUserId = _getCurrentUserId();
    if (currentUserId == null) return;

    // 判断是否为客服会话
    final conversation = ref.read(conversationsProvider).valueOrNull
        ?.where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final isSupport = conversation?.type == 'support';

    try {
      if (isSupport) {
        // 客服会话：调用 support-chat Edge Function（AI 回答）
        // 用户消息由 Edge Function 保存，这里先本地追加一条
        final userMsg = MessageModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          conversationId: widget.conversationId,
          senderId: currentUserId,
          type: 'text',
          content: text,
          isAiMessage: false,
          isDeleted: false,
          createdAt: DateTime.now(),
        );
        ref
            .read(messagesProvider(widget.conversationId).notifier)
            .addMessage(userMsg);
        _scrollToBottom();

        final result = await ref.read(chatRepositoryProvider).sendSupportMessage(
              conversationId: widget.conversationId,
              message: text,
            );

        // AI 回复通过 Realtime 自动接收，无需手动添加
        // 如果转人工，刷新会话列表以更新状态
        if (result.handoff) {
          ref.read(conversationsProvider.notifier).refresh();
        }
      } else {
        // 普通会话：直接发送
        final msg = await ref.read(chatRepositoryProvider).sendTextMessage(
              widget.conversationId,
              currentUserId,
              text,
            );
        ref
            .read(messagesProvider(widget.conversationId).notifier)
            .addMessage(msg);
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// 选择图片并发送
  Future<void> _handlePickImage() async {
    final currentUserId = _getCurrentUserId();
    if (currentUserId == null) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text('Sending image...'),
          ]),
          duration: Duration(seconds: 10),
        ),
      );
    }

    try {
      final imageUrl = await ref.read(chatRepositoryProvider).uploadChatImage(
            userId: currentUserId,
            file: picked,
          );
      final msg = await ref.read(chatRepositoryProvider).sendImageMessage(
            widget.conversationId,
            currentUserId,
            imageUrl,
          );
      ref.read(messagesProvider(widget.conversationId).notifier).addMessage(msg);
      _scrollToBottom();
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send image: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// 选择 Coupon 卡片并发送
  Future<void> _handlePickCoupon() async {
    final currentUserId = _getCurrentUserId();
    if (currentUserId == null) return;

    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => CouponPickerSheet(
        onSelect: (p) => Navigator.of(context).pop(p),
      ),
    );
    if (payload == null) return;

    try {
      final msg = await ref.read(chatRepositoryProvider).sendCouponMessage(
            widget.conversationId,
            currentUserId,
            payload,
          );
      ref.read(messagesProvider(widget.conversationId).notifier).addMessage(msg);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send coupon: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // ============================================================
  // 工具方法
  // ============================================================

  /// 获取当前登录用户 ID（同步读取缓存值）
  String? _getCurrentUserId() {
    return ref.read(currentUserProvider).valueOrNull?.id;
  }

  /// 滚动到底部（列表 reverse: true，滚到 minScrollExtent 即底部）
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // 监听会话信息（用于显示对方名称 / 群名）
    final conversationsAsync = ref.watch(conversationsProvider);
    final currentUserId = _getCurrentUserId() ?? '';

    // 从会话列表中找到当前会话
    final conversation = conversationsAsync.valueOrNull
        ?.where((c) => c.id == widget.conversationId)
        .firstOrNull;

    // 会话标题：优先用 provider 中的名字，fallback 到直接查询的名字
    final providerName = conversation?.displayName;
    final title = (providerName != null && providerName != 'Unknown')
        ? providerName
        : (_fallbackName ?? 'Chat');
    final isGroupChat = conversation?.type == 'group';

    // 监听消息列表
    final messagesAsync = ref.watch(messagesProvider(widget.conversationId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(title, conversation?.displayAvatarUrl, conversation),
      body: Column(
        children: [
          // 客服状态 banner（仅 support 会话显示）
          if (conversation?.type == 'support')
            _SupportStatusBanner(status: conversation?.supportStatus ?? 'ai'),

          // 消息列表区域
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Failed to load messages',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              data: (messages) => _buildMessageList(
                messages: messages,
                currentUserId: currentUserId,
                isGroupChat: isGroupChat,
              ),
            ),
          ),

          // 客服快捷回复（仅 AI 模式下显示）
          if (conversation?.type == 'support' && conversation?.supportStatus == 'ai')
            _SupportQuickReplies(onTap: _sendTextMessage),

          // 底部输入栏
          ChatInputBar(
            onSendText: _sendTextMessage,
            onPickImage: _handlePickImage,
            onPickCoupon: _handlePickCoupon,
          ),
        ],
      ),
    );
  }

  /// 构建 AppBar
  PreferredSizeWidget _buildAppBar(String title, String? avatarUrl, ConversationModel? conversation) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Colors.black12,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          // 头像
          if (avatarUrl != null && avatarUrl.isNotEmpty)
            CircleAvatar(
              radius: 18,
              backgroundImage: NetworkImage(avatarUrl),
              backgroundColor: AppColors.surfaceVariant,
            )
          else
            const CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.surfaceVariant,
              child: Icon(Icons.person, size: 18, color: AppColors.textHint),
            ),
          const SizedBox(width: 10),
          // 会话名称
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_horiz, color: AppColors.textPrimary),
          onPressed: () => _showMoreActions(conversation),
        ),
      ],
    );
  }

  /// 显示更多操作菜单（置顶、删除聊天、取消好友）
  void _showMoreActions(ConversationModel? conversation) {
    final userId = ref.read(currentUserProvider).valueOrNull?.id;
    if (userId == null || conversation == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖动指示条
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 置顶/取消置顶
            ListTile(
              leading: Icon(
                conversation.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                color: AppColors.primary,
              ),
              title: Text(conversation.isPinned ? 'Unpin' : 'Pin to Top'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await ref.read(chatRepositoryProvider).togglePin(
                  conversation.id, userId, !conversation.isPinned,
                );
                ref.read(conversationsProvider.notifier).refresh();
              },
            ),
            // 删除聊天
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('Delete Chat'),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDeleteChat(conversation, userId);
              },
            ),
            // 取消好友（仅 direct 类型）
            if (conversation.type == 'direct' && conversation.otherUserId != null)
              ListTile(
                leading: const Icon(Icons.person_remove_outlined, color: AppColors.error),
                title: const Text('Remove Friend'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _confirmRemoveFriend(conversation, userId);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 确认删除聊天对话框
  void _confirmDeleteChat(ConversationModel conversation, String userId) {
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
              await ref.read(chatRepositoryProvider).leaveConversation(conversation.id, userId);
              ref.read(conversationsProvider.notifier).refresh();
              if (mounted) Navigator.of(context).pop(); // 返回聊天列表
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// 确认取消好友对话框
  void _confirmRemoveFriend(ConversationModel conversation, String userId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove friend?'),
        content: Text('Remove ${conversation.displayName} from your friends list? This will also delete the chat.'),
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
              // 取消好友
              await ref.read(friendRepositoryProvider).removeFriend(userId, conversation.otherUserId!);
              // 删除聊天
              await ref.read(chatRepositoryProvider).leaveConversation(conversation.id, userId);
              ref.read(conversationsProvider.notifier).refresh();
              if (mounted) Navigator.of(context).pop(); // 返回聊天列表
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  /// 构建消息列表
  Widget _buildMessageList({
    required List<MessageModel> messages,
    required String currentUserId,
    required bool isGroupChat,
  }) {
    // 消息列表为空时显示友好提示
    if (messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 56, color: AppColors.textHint),
            SizedBox(height: 12),
            Text(
              'Start a conversation!',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      // reverse: true 使最新消息自动显示在底部
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // 加载更多指示器（显示在列表末尾，即历史消息方向）
        if (index == messages.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final message = messages[index];

        // 判断是否需要显示日期分隔符
        // messages 列表按时间倒序（最新在前），index 0 是最新消息
        // 需要在"时间更早的那条消息"之前显示日期分隔符
        bool showDateSeparator = false;
        if (index < messages.length - 1) {
          final current = messages[index];
          final older = messages[index + 1]; // 更早的消息
          final currentDay = DateTime(
            current.createdAt.year,
            current.createdAt.month,
            current.createdAt.day,
          );
          final olderDay = DateTime(
            older.createdAt.year,
            older.createdAt.month,
            older.createdAt.day,
          );
          // 如果日期不同，在 older 那条消息上方显示分隔符
          // 在 reverse 列表中，index+1 的 widget 渲染在更高位置
          showDateSeparator = currentDay != olderDay;
        } else {
          // 最后一条（最旧的）消息始终显示日期
          showDateSeparator = true;
        }

        return MessageBubble(
          message: message,
          currentUserId: currentUserId,
          isGroupChat: isGroupChat,
          showDateSeparator: showDateSeparator,
        );
      },
    );
  }
}

// 客服快捷回复 chip 列表（仅 AI 模式显示）
class _SupportQuickReplies extends StatelessWidget {
  final void Function(String) onTap;
  const _SupportQuickReplies({required this.onTap});

  static const _chips = [
    // (显示文案, 发送文本, isLiveAgent)
    ('🎧  Live Agent', 'live agent', true),
    ('Check order status', 'I want to check my order status', false),
    ('Refund policy', 'What is your refund policy?', false),
    ('How to use coupon', 'How do I use my coupon?', false),
    ('Cancel order', 'I want to cancel my order', false),
    ('Coupon expired', 'My coupon has expired, what can I do?', false),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _chips.map<Widget>((chip) {
            final label = chip.$1;
            final sendText = chip.$2;
            final isLiveAgent = chip.$3;
            if (isLiveAgent) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ElevatedButton(
                  onPressed: () => onTap(sendText),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(label, style: const TextStyle(fontSize: 13)),
                onPressed: () => onTap(sendText),
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                labelStyle: const TextStyle(color: AppColors.textPrimary),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// 客服状态 banner — AI 模式 / 已转人工 / 已解决
class _SupportStatusBanner extends StatelessWidget {
  final String status;
  const _SupportStatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final (icon, label, bg, fg) = switch (status) {
      'human' => (
          Icons.support_agent,
          'Connected to a support agent',
          const Color(0xFFE8F5E9),
          const Color(0xFF2E7D32),
        ),
      'resolved' => (
          Icons.check_circle_outline,
          'This conversation has been resolved',
          const Color(0xFFF5F5F5),
          const Color(0xFF757575),
        ),
      _ => (
          Icons.smart_toy_outlined,
          'Chatting with AI assistant',
          const Color(0xFFE3F2FD),
          const Color(0xFF1565C0),
        ),
    };

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: fg, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
