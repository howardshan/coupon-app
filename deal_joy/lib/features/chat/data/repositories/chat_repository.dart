// ChatRepository — 聊天模块数据访问层
// 直接查询 Supabase 表（conversations / conversation_members / messages）
// 不走 Edge Function

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';

class ChatRepository {
  final SupabaseClient _client;

  ChatRepository(this._client);

  // ================================================================
  // 会话列表
  // ================================================================

  /// 获取当前用户的所有会话列表
  /// 流程：
  ///   1. 查 conversation_members 获取用户加入的所有会话 ID + last_read_at
  ///   2. 查 conversations 基本信息
  ///   3. 批量获取每个会话最新消息（含发送者名称）
  ///   4. 对于 direct 类型，从 conversation_members 获取对方用户信息
  ///   5. 计算每个会话未读数（messages.created_at > last_read_at 且 sender_id != 当前用户）
  Future<List<ConversationModel>> fetchConversations(String userId) async {
    try {
      // 第一步：获取用户加入的会话 ID 和 last_read_at
      final memberRows = await _client
          .from('conversation_members')
          .select('conversation_id, last_read_at')
          .eq('user_id', userId);

      final memberList = memberRows as List;
      if (memberList.isEmpty) return [];

      final conversationIds =
          memberList.map((r) => r['conversation_id'] as String).toList();
      if (conversationIds.isEmpty) return [];

      // 第二步：查询会话基本信息
      final convRows = await _client
          .from('conversations')
          .select(
            'id, type, name, avatar_url, support_status, updated_at, created_at',
          )
          .inFilter('id', conversationIds)
          .order('updated_at', ascending: false);

      // 构建 last_read_at 映射：conversation_id -> DateTime?
      final lastReadMap = <String, DateTime?>{};
      for (final r in memberRows) {
        final raw = r['last_read_at'] as String?;
        lastReadMap[r['conversation_id'] as String] =
            raw != null ? DateTime.tryParse(raw) : null;
      }

      // 第三步：批量获取所有消息（用于最新消息预览 + 未读数计算）
      // 不使用 FK join（避免 users 表关联问题），单独查发送者信息
      final allMsgRows = await _client
          .from('messages')
          .select(
            'id, conversation_id, sender_id, type, content, image_url, '
            'is_deleted, created_at',
          )
          .inFilter('conversation_id', conversationIds)
          .order('created_at', ascending: false);

      // 按 conversation_id 分组，取最新一条作为 last_message
      final latestMsgMap = <String, Map<String, dynamic>>{};
      for (final msg in allMsgRows as List) {
        final cid = msg['conversation_id'] as String;
        if (!latestMsgMap.containsKey(cid)) {
          latestMsgMap[cid] = msg as Map<String, dynamic>;
        }
      }

      // 第四步：对 direct 类型会话，获取对方用户信息
      final directIds = (convRows as List)
          .where((r) => r['type'] == 'direct')
          .map((r) => r['id'] as String)
          .toList();

      final otherUserMap = <String, Map<String, dynamic>>{};
      if (directIds.isNotEmpty) {
        // 先查对方的 user_id
        final otherMembers = await _client
            .from('conversation_members')
            .select('conversation_id, user_id')
            .inFilter('conversation_id', directIds)
            .neq('user_id', userId);

        // 收集对方 user_id 列表
        final otherUserIds = <String>{};
        for (final row in otherMembers as List) {
          otherUserIds.add(row['user_id'] as String);
        }

        // 批量查询对方用户信息
        final userInfoMap = <String, Map<String, dynamic>>{};
        if (otherUserIds.isNotEmpty) {
          final userRows = await _client
              .from('users')
              .select('id, full_name, avatar_url')
              .inFilter('id', otherUserIds.toList());
          for (final u in userRows as List) {
            userInfoMap[u['id'] as String] = u as Map<String, dynamic>;
          }
        }

        for (final row in otherMembers) {
          final cid = row['conversation_id'] as String;
          if (!otherUserMap.containsKey(cid)) {
            final uid = row['user_id'] as String;
            final userInfo = userInfoMap[uid];
            otherUserMap[cid] = {
              'user_id': uid,
              'full_name': userInfo?['full_name'] as String?,
              'avatar_url': userInfo?['avatar_url'] as String?,
            };
          }
        }
      }

      // 第五步：计算每个会话的未读消息数
      // 未读条件：sender_id != 当前用户 且 created_at > last_read_at
      final unreadCountMap = <String, int>{};
      for (final cid in conversationIds) {
        final lastRead = lastReadMap[cid];
        int count = 0;
        for (final msg in allMsgRows) {
          if (msg['conversation_id'] != cid) continue;
          if (msg['sender_id'] == userId) continue;
          if (lastRead == null) {
            count++;
          } else {
            final msgTimeStr = msg['created_at'] as String?;
            if (msgTimeStr != null) {
              final t = DateTime.tryParse(msgTimeStr);
              if (t != null && t.isAfter(lastRead)) count++;
            }
          }
        }
        unreadCountMap[cid] = count;
      }

      // 第六步：组装 ConversationModel 列表
      return convRows.map((row) {
        final cid = row['id'] as String;
        final lastMsg = latestMsgMap[cid];
        final otherUser = otherUserMap[cid];

        // 注入附加字段供 ConversationModel.fromJson 解析
        final enrichedJson = Map<String, dynamic>.from(row);
        if (lastMsg != null) {
          enrichedJson['last_message'] = lastMsg;
        }
        if (otherUser != null) {
          enrichedJson['other_user_id'] = otherUser['user_id'];
          enrichedJson['other_user_name'] = otherUser['full_name'];
          enrichedJson['other_user_avatar_url'] = otherUser['avatar_url'];
        }
        enrichedJson['unread_count'] = unreadCountMap[cid] ?? 0;

        return ConversationModel.fromJson(enrichedJson);
      }).toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to load conversations: ${e.message}',
        code: e.code,
      );
    }
  }

  // ================================================================
  // 消息列表
  // ================================================================

  /// 获取指定会话的消息列表（分页，按 created_at DESC，最新在前）
  /// [conversationId] 会话 ID（具名参数，与 provider 调用方式对齐）
  /// [page] 页码从 0 开始，[pageSize] 每页条数，默认 30
  Future<List<MessageModel>> fetchMessages({
    required String conversationId,
    int page = 0,
    int pageSize = 30,
  }) async {
    try {
      final from = page * pageSize;
      final to = from + pageSize - 1;

      final data = await _client
          .from('messages')
          .select(
            'id, conversation_id, sender_id, type, content, image_url, '
            'coupon_payload, is_ai_message, is_deleted, created_at',
          )
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .range(from, to);

      final messages = (data as List)
          .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
          .toList();

      // 批量查询发送者信息
      final senderIds = messages
          .map((m) => m.senderId)
          .where((id) => id != null && id.isNotEmpty)
          .toSet();
      final senderMap = <String, Map<String, dynamic>>{};
      if (senderIds.isNotEmpty) {
        final userRows = await _client
            .from('users')
            .select('id, full_name, avatar_url')
            .inFilter('id', senderIds.toList());
        for (final u in userRows as List) {
          senderMap[u['id'] as String] = u as Map<String, dynamic>;
        }
      }

      // 注入发送者信息
      return messages.map((m) {
        if (m.senderId != null && senderMap.containsKey(m.senderId)) {
          final u = senderMap[m.senderId]!;
          return MessageModel(
            id: m.id,
            conversationId: m.conversationId,
            senderId: m.senderId,
            type: m.type,
            content: m.content,
            imageUrl: m.imageUrl,
            couponPayload: m.couponPayload,
            isAiMessage: m.isAiMessage,
            isDeleted: m.isDeleted,
            createdAt: m.createdAt,
            senderName: u['full_name'] as String?,
            senderAvatarUrl: u['avatar_url'] as String?,
          );
        }
        return m;
      }).toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to load messages: ${e.message}',
        code: e.code,
      );
    }
  }

  // ================================================================
  // 图片上传
  // ================================================================

  /// 上传聊天图片到 Storage，返回公开 URL
  /// [userId] 当前用户 ID，用于构造存储路径
  /// [file] 从 image_picker 选取的 XFile
  Future<String> uploadChatImage({
    required String userId,
    required XFile file,
  }) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storagePath = '$userId/$fileName';
      final bytes = await file.readAsBytes();
      await _client.storage.from('chat-media').uploadBinary(
        storagePath,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );
      return _client.storage.from('chat-media').getPublicUrl(storagePath);
    } on StorageException catch (e) {
      throw AppException('Failed to upload image: ${e.message}');
    }
  }

  // ================================================================
  // 发送消息
  // ================================================================

  /// 发送文字消息
  Future<MessageModel> sendTextMessage(
    String conversationId,
    String senderId,
    String content,
  ) async {
    return _sendMessage(conversationId, senderId, {
      'type': 'text',
      'content': content,
    });
  }

  /// 发送图片消息
  Future<MessageModel> sendImageMessage(
    String conversationId,
    String senderId,
    String imageUrl,
  ) async {
    return _sendMessage(conversationId, senderId, {
      'type': 'image',
      'image_url': imageUrl,
    });
  }

  /// 发送 Coupon 卡片消息
  Future<MessageModel> sendCouponMessage(
    String conversationId,
    String senderId,
    Map<String, dynamic> couponPayload,
  ) async {
    return _sendMessage(conversationId, senderId, {
      'type': 'coupon',
      'coupon_payload': couponPayload,
    });
  }

  /// 内部通用发送方法：插入消息并同步更新会话 updated_at
  Future<MessageModel> _sendMessage(
    String conversationId,
    String senderId,
    Map<String, dynamic> fields,
  ) async {
    try {
      final insertData = {
        'conversation_id': conversationId,
        'sender_id': senderId,
        'is_ai_message': false,
        'is_deleted': false,
        ...fields,
      };

      final result = await _client
          .from('messages')
          .insert(insertData)
          .select(
            'id, conversation_id, sender_id, type, content, image_url, '
            'coupon_payload, is_ai_message, is_deleted, created_at',
          )
          .single();

      // 同步更新会话最后活跃时间
      await _client
          .from('conversations')
          .update({'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', conversationId);

      return MessageModel.fromJson(result);
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to send message: ${e.message}',
        code: e.code,
      );
    }
  }

  // ================================================================
  // 已读状态
  // ================================================================

  /// 标记会话已读（更新 conversation_members.last_read_at 为当前时间）
  Future<void> markAsRead(String conversationId, String userId) async {
    try {
      await _client
          .from('conversation_members')
          .update({
            'last_read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('conversation_id', conversationId)
          .eq('user_id', userId);
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to mark as read: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 获取用户所有会话的未读消息总数
  Future<int> fetchTotalUnreadCount(String userId) async {
    try {
      // 获取用户所有会话成员记录（含 last_read_at）
      final memberRows = await _client
          .from('conversation_members')
          .select('conversation_id, last_read_at')
          .eq('user_id', userId);

      if ((memberRows as List).isEmpty) return 0;

      int total = 0;
      for (final row in memberRows) {
        final cid = row['conversation_id'] as String;
        final rawLastRead = row['last_read_at'] as String?;
        final lastRead =
            rawLastRead != null ? DateTime.tryParse(rawLastRead) : null;

        // 查询该会话中当前用户未读的消息数
        // 条件：sender_id != 当前用户，且 created_at > last_read_at
        var query = _client
            .from('messages')
            .select('id')
            .eq('conversation_id', cid)
            .neq('sender_id', userId);

        if (lastRead != null) {
          query = query.gt(
            'created_at',
            lastRead.toUtc().toIso8601String(),
          );
        }

        final unread = await query;
        total += (unread as List).length;
      }

      return total;
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to fetch unread count: ${e.message}',
        code: e.code,
      );
    }
  }

  // ================================================================
  // 客服会话
  // ================================================================

  // ================================================================
  // 群聊
  // ================================================================

  /// 创建群聊
  /// 流程：
  ///   1. 插入 conversations 表（type = 'group'）
  ///   2. 批量插入 conversation_members（创建者为 owner，其余为 member）
  ///   3. 发送一条系统消息 "Group created"
  ///   4. 返回新建的 ConversationModel
  Future<ConversationModel> createGroupChat({
    required String creatorId,
    required String name,
    required List<String> memberIds, // 不含创建者
  }) async {
    try {
      // 第一步：创建群聊 conversation 记录
      final convData = await _client
          .from('conversations')
          .insert({
            'type': 'group',
            'name': name,
            'created_by': creatorId,
          })
          .select(
            'id, type, name, avatar_url, support_status, updated_at, created_at',
          )
          .single();

      final convId = convData['id'] as String;

      // 第二步：批量添加成员（创建者为 owner，其余为 member）
      final members = <Map<String, dynamic>>[
        {'conversation_id': convId, 'user_id': creatorId, 'role': 'owner'},
        ...memberIds.map((id) => {
              'conversation_id': convId,
              'user_id': id,
              'role': 'member',
            }),
      ];
      await _client.from('conversation_members').insert(members);

      // 第三步：发送系统消息
      await _client.from('messages').insert({
        'conversation_id': convId,
        'sender_id': creatorId,
        'type': 'system',
        'content': 'Group created',
        'is_ai_message': false,
        'is_deleted': false,
      });

      // 返回新建的 ConversationModel
      return ConversationModel.fromJson(convData);
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to create group chat: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 获取或创建客服会话
  /// 若用户已有 support 类型会话则直接返回；否则新建并加入
  Future<ConversationModel> getOrCreateSupportChat(String userId) async {
    try {
      // 查找用户已有的 support 会话（通过 conversation_members inner join conversations）
      final existingMembers = await _client
          .from('conversation_members')
          .select('conversation_id, conversations!inner(id, type)')
          .eq('user_id', userId)
          .eq('conversations.type', 'support');

      if ((existingMembers as List).isNotEmpty) {
        final cid = existingMembers.first['conversation_id'] as String;
        final conv = await _client
            .from('conversations')
            .select(
              'id, type, name, avatar_url, support_status, updated_at, created_at',
            )
            .eq('id', cid)
            .single();
        return ConversationModel.fromJson(conv);
      }

      // 新建 support 会话
      final newConv = await _client
          .from('conversations')
          .insert({
            'type': 'support',
            'support_status': 'ai',
            'name': 'Support',
          })
          .select(
            'id, type, name, avatar_url, support_status, updated_at, created_at',
          )
          .single();

      final convId = newConv['id'] as String;

      // 将用户加入该会话
      await _client.from('conversation_members').insert({
        'conversation_id': convId,
        'user_id': userId,
      });

      return ConversationModel.fromJson(newConv);
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to get or create support chat: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 发送客服消息（调用 support-chat Edge Function，由 AI 回复）
  /// 返回 AI 回复内容（如果有）
  Future<({String? aiReply, bool handoff})> sendSupportMessage({
    required String conversationId,
    required String message,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'support-chat',
        body: {
          'conversation_id': conversationId,
          'message': message,
        },
      );

      if (response.status != 200) {
        throw AppException('Support chat failed: ${response.data}');
      }

      final data = response.data as Map<String, dynamic>;
      return (
        aiReply: data['ai_reply'] as String?,
        handoff: data['handoff'] as bool? ?? false,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Failed to send support message: $e');
    }
  }
}
