// 客服聊天 Service
// 直接调用 Supabase 客户端，RLS 保证数据隔离

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/support_models.dart';

class SupportService {
  final SupabaseClient _client;

  SupportService(this._client);

  // ----------------------------------------------------------
  // 获取或创建当前商家的会话（upsert 保证幂等，防并发重复创建）
  // ----------------------------------------------------------
  Future<SupportConversation> getOrCreateConversation(String merchantId) async {
    final res = await _client
        .from('support_conversations')
        .upsert(
          {'merchant_id': merchantId},
          onConflict: 'merchant_id',
        )
        .select()
        .single();

    return SupportConversation.fromJson(res);
  }

  // ----------------------------------------------------------
  // 发送消息（商家端始终 sender_role = 'merchant'）
  // ----------------------------------------------------------
  Future<SupportMessage> sendMessage(String conversationId, String content) async {
    final res = await _client
        .from('support_messages')
        .insert({
          'conversation_id': conversationId,
          'sender_role':     'merchant',
          'content':         content.trim(),
        })
        .select()
        .single();

    return SupportMessage.fromJson(res);
  }

  // ----------------------------------------------------------
  // 拉取会话全部消息（按时间升序）
  // ----------------------------------------------------------
  Future<List<SupportMessage>> fetchMessages(String conversationId) async {
    final res = await _client
        .from('support_messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);

    return (res as List)
        .map((e) => SupportMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
