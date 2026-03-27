// 会话数据模型
// 支持 direct（私聊）、group（群聊）、support（客服）三种类型
// 通过 join conversation_members + users 获取对方信息和未读数

class ConversationModel {
  /// 会话唯一 ID
  final String id;

  /// 会话类型：'direct' | 'group' | 'support'
  final String type;

  /// 群聊名称（direct 类型为 null）
  final String? name;

  /// 会话头像 URL（群聊头像 / support 头像）
  final String? avatarUrl;

  /// 客服会话状态：'ai' | 'human' | 'resolved'（仅 support 类型有效）
  final String? supportStatus;

  /// 最后一条消息更新时间
  final DateTime updatedAt;

  /// 会话创建时间
  final DateTime createdAt;

  // ---------- join 附加字段（来自最新消息） ----------

  /// 最新消息内容预览
  final String? lastMessageContent;

  /// 最新消息类型：'text' | 'image' | 'coupon' | 'emoji' | 'system'
  final String? lastMessageType;

  /// 最新消息时间
  final DateTime? lastMessageAt;

  /// 最新消息发送者名称
  final String? lastMessageSenderName;

  /// 当前用户未读消息数
  final int unreadCount;

  /// 是否被当前用户置顶
  final bool isPinned;

  // ---------- direct 类型：对方用户信息 ----------

  /// 对方用户 ID（direct 类型专用）
  final String? otherUserId;

  /// 对方用户名称
  final String? otherUserName;

  /// 对方用户头像 URL
  final String? otherUserAvatarUrl;

  const ConversationModel({
    required this.id,
    required this.type,
    this.name,
    this.avatarUrl,
    this.supportStatus,
    required this.updatedAt,
    required this.createdAt,
    this.lastMessageContent,
    this.lastMessageType,
    this.lastMessageAt,
    this.lastMessageSenderName,
    this.unreadCount = 0,
    this.isPinned = false,
    this.otherUserId,
    this.otherUserName,
    this.otherUserAvatarUrl,
  });

  /// 标准 fromJson — 解析 Supabase 直查表返回的嵌套数据
  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    // 从嵌套的 last_message 对象（join 查询）提取最新消息字段
    final lastMsg = json['last_message'] as Map<String, dynamic>?;

    // 最新消息发送者名称（来自 last_message.sender.full_name）
    String? lastSenderName;
    if (lastMsg != null) {
      final sender = lastMsg['sender'] as Map<String, dynamic>?;
      lastSenderName = sender?['full_name'] as String?;
    }

    return ConversationModel(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'direct',
      name: json['name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      supportStatus: json['support_status'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastMessageContent: lastMsg?['content'] as String?,
      lastMessageType: lastMsg?['type'] as String?,
      lastMessageAt: lastMsg?['created_at'] != null
          ? DateTime.tryParse(lastMsg!['created_at'] as String)
          : null,
      lastMessageSenderName: lastSenderName,
      unreadCount: json['unread_count'] as int? ?? 0,
      isPinned: json['is_pinned'] as bool? ?? false,
      otherUserId: json['other_user_id'] as String?,
      otherUserName: json['other_user_name'] as String?,
      otherUserAvatarUrl: json['other_user_avatar_url'] as String?,
    );
  }

  /// 用于在 Repository 层手动组装 direct 会话的对方用户信息
  ConversationModel copyWithOtherUser({
    required String otherUserId,
    String? otherUserName,
    String? otherUserAvatarUrl,
  }) {
    return ConversationModel(
      id: id,
      type: type,
      name: name,
      avatarUrl: avatarUrl,
      supportStatus: supportStatus,
      updatedAt: updatedAt,
      createdAt: createdAt,
      lastMessageContent: lastMessageContent,
      lastMessageType: lastMessageType,
      lastMessageAt: lastMessageAt,
      lastMessageSenderName: lastMessageSenderName,
      unreadCount: unreadCount,
      isPinned: isPinned,
      otherUserId: otherUserId,
      otherUserName: otherUserName,
      otherUserAvatarUrl: otherUserAvatarUrl,
    );
  }

  /// 用于更新未读数（Repository 层计算后注入）
  ConversationModel copyWithUnreadCount(int count) {
    return ConversationModel(
      id: id,
      type: type,
      name: name,
      avatarUrl: avatarUrl,
      supportStatus: supportStatus,
      updatedAt: updatedAt,
      createdAt: createdAt,
      lastMessageContent: lastMessageContent,
      lastMessageType: lastMessageType,
      lastMessageAt: lastMessageAt,
      lastMessageSenderName: lastMessageSenderName,
      unreadCount: count,
      isPinned: isPinned,
      otherUserId: otherUserId,
      otherUserName: otherUserName,
      otherUserAvatarUrl: otherUserAvatarUrl,
    );
  }

  /// 展示名：direct 用对方姓名，group 用群名，support 固定 "Support"
  String get displayName {
    if (type == 'direct') return otherUserName ?? 'Unknown';
    if (type == 'support') return 'Support';
    return name ?? 'Group';
  }

  /// 展示头像 URL：direct 用对方头像，其余用 avatarUrl
  String? get displayAvatarUrl {
    if (type == 'direct') return otherUserAvatarUrl;
    return avatarUrl;
  }
}
