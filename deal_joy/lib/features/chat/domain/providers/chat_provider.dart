import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/message_model.dart';
import '../../data/repositories/chat_repository.dart';

// ---- Repository Provider ----

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.watch(supabaseClientProvider));
});

// ---- 会话列表 Notifier ----

/// 管理当前用户的会话列表，支持手动刷新
class ConversationsNotifier extends AsyncNotifier<List<ConversationModel>> {
  @override
  Future<List<ConversationModel>> build() async {
    // 获取当前登录用户
    final user = await ref.watch(currentUserProvider.future);
    if (user == null) return [];
    return ref.read(chatRepositoryProvider).fetchConversations(user.id);
  }

  /// 手动刷新会话列表
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
  }
}

final conversationsProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<ConversationModel>>(
        ConversationsNotifier.new);

// ---- 消息列表 Notifier（按会话 ID 分组，支持分页） ----

/// 每页加载的消息数量
const _kMessagesPageSize = 30;

/// 管理指定会话的消息列表，支持分页加载更多以及 Realtime 新消息追加
class MessagesNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<MessageModel>, String> {
  int _page = 0;
  bool _hasMore = true;

  /// 是否还有更多历史消息可加载
  bool get hasMore => _hasMore;

  @override
  Future<List<MessageModel>> build(String conversationId) async {
    // 重置分页状态
    _page = 0;
    _hasMore = true;
    return ref.read(chatRepositoryProvider).fetchMessages(
          conversationId: conversationId,
          page: _page,
          pageSize: _kMessagesPageSize,
        );
  }

  /// 加载更多历史消息（向上翻页）
  Future<void> loadMore() async {
    if (!_hasMore) return;
    final current = state.valueOrNull ?? [];
    final nextPage = _page + 1;
    final more = await ref.read(chatRepositoryProvider).fetchMessages(
          conversationId: arg,
          page: nextPage,
          pageSize: _kMessagesPageSize,
        );
    if (more.length < _kMessagesPageSize) {
      _hasMore = false;
    }
    _page = nextPage;
    // 旧消息拼接到列表末尾（列表按时间倒序，末尾是更早的消息）
    state = AsyncValue.data([...current, ...more]);
  }

  /// Realtime 收到新消息时调用，将消息插入列表头部
  void addMessage(MessageModel message) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([message, ...current]);
  }
}

final messagesProvider = AsyncNotifierProvider.autoDispose
    .family<MessagesNotifier, List<MessageModel>, String>(
        MessagesNotifier.new);

// ---- 未读消息总数（用于底部 Tab badge）----

/// 获取当前用户所有会话的未读消息总数
final totalUnreadCountProvider = FutureProvider<int>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return 0;
  return ref.watch(chatRepositoryProvider).fetchTotalUnreadCount(user.id);
});
