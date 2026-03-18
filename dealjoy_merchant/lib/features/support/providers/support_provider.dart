// 客服聊天 Provider
// 复用 notifications_provider.dart 的 Realtime 模式

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/support_models.dart';
import '../services/support_service.dart';

// ============================================================
// 全局 SupportService 单例
// ============================================================
final supportServiceProvider = Provider<SupportService>((ref) {
  return SupportService(Supabase.instance.client);
});

// ============================================================
// SupportState — Provider 状态
// ============================================================
class SupportState {
  final SupportConversation? conversation;
  final List<SupportMessage> messages;
  final bool isLoading;
  final String? error;

  const SupportState({
    this.conversation,
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  SupportState copyWith({
    SupportConversation? conversation,
    List<SupportMessage>? messages,
    bool? isLoading,
    String? error,
  }) {
    return SupportState(
      conversation: conversation ?? this.conversation,
      messages:     messages     ?? this.messages,
      isLoading:    isLoading    ?? this.isLoading,
      error:        error,
    );
  }
}

// ============================================================
// SupportNotifier — 消息列表 + Realtime 订阅
// ============================================================
class SupportNotifier extends AsyncNotifier<SupportState> {
  RealtimeChannel? _channel;

  @override
  Future<SupportState> build() async {
    // 注册 dispose 回调，防内存泄漏
    ref.onDispose(_unsubscribeRealtime);
    return await _load();
  }

  // ----------------------------------------------------------
  // 初始化：获取/创建会话，拉取历史消息，订阅 Realtime
  // ----------------------------------------------------------
  Future<SupportState> _load() async {
    final supabase  = Supabase.instance.client;
    final user      = supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final service = ref.read(supportServiceProvider);

    // 查询当前用户对应的 merchant_id
    final merchantRes = await supabase
        .from('merchants')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle();

    if (merchantRes == null) throw Exception('Merchant not found');
    final merchantId = merchantRes['id'] as String;

    // 获取或创建会话
    final conversation = await service.getOrCreateConversation(merchantId);

    // 拉取历史消息
    final messages = await service.fetchMessages(conversation.id);

    // 订阅新消息
    _subscribeRealtime(conversation.id);

    return SupportState(conversation: conversation, messages: messages);
  }

  // ----------------------------------------------------------
  // Realtime 订阅（复用 notifications_provider 模式）
  // ----------------------------------------------------------
  void _subscribeRealtime(String conversationId) {
    _unsubscribeRealtime();

    _channel = Supabase.instance.client
        .channel('support_$conversationId')
        .onPostgresChanges(
          event:  PostgresChangeEvent.insert,
          schema: 'public',
          table:  'support_messages',
          callback: (payload) {
            // 回调里过滤，只处理属于本会话的消息
            final record = payload.newRecord;
            if (record['conversation_id'] == conversationId) {
              _onNewMessage(record);
            }
          },
        )
        .subscribe();
  }

  void _unsubscribeRealtime() {
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
      _channel = null;
    }
  }

  // ----------------------------------------------------------
  // 新消息到达（Realtime 回调）
  // ----------------------------------------------------------
  void _onNewMessage(Map<String, dynamic> record) {
    final current = state.valueOrNull;
    if (current == null) return;

    final newMsg = SupportMessage.fromJson(record);

    // 防重复（Realtime 有时会触发两次）
    if (current.messages.any((m) => m.id == newMsg.id)) return;

    state = AsyncData(current.copyWith(
      messages: [...current.messages, newMsg],
    ));
  }

  // ----------------------------------------------------------
  // 发送消息（乐观更新：先追加到列表，再持久化）
  // ----------------------------------------------------------
  Future<void> sendMessage(String content) async {
    final current = state.valueOrNull;
    if (current?.conversation == null) return;

    final service        = ref.read(supportServiceProvider);
    final conversationId = current!.conversation!.id;

    // 乐观临时消息（无真实 id）
    final optimistic = SupportMessage(
      id:             'temp_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: conversationId,
      senderRole:     'merchant',
      content:        content,
      createdAt:      DateTime.now(),
    );

    state = AsyncData(current.copyWith(
      messages: [...current.messages, optimistic],
    ));

    try {
      final saved = await service.sendMessage(conversationId, content);
      // 替换乐观消息为真实消息
      final updated = state.valueOrNull;
      if (updated == null) return;
      final msgs = updated.messages.map((m) =>
        m.id == optimistic.id ? saved : m
      ).toList();
      state = AsyncData(updated.copyWith(messages: msgs));
    } catch (e) {
      // 发送失败，移除乐观消息
      final updated = state.valueOrNull;
      if (updated == null) return;
      state = AsyncData(updated.copyWith(
        messages: updated.messages.where((m) => m.id != optimistic.id).toList(),
        error:    e.toString(),
      ));
    }
  }

  // ----------------------------------------------------------
  // 下拉刷新
  // ----------------------------------------------------------
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }
}

// 全局 Provider
final supportProvider =
    AsyncNotifierProvider<SupportNotifier, SupportState>(SupportNotifier.new);
