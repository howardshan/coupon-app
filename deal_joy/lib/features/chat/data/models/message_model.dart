// 消息数据模型
// 支持 text / image / coupon / emoji / system 五种消息类型
// senderName / senderAvatarUrl 来自 join users 表

class MessageModel {
  /// 消息唯一 ID
  final String id;

  /// 所属会话 ID
  final String conversationId;

  /// 发送者用户 ID（system 消息为 null）
  final String? senderId;

  /// 消息类型：'text' | 'image' | 'coupon' | 'emoji' | 'system'
  final String type;

  /// 文字内容（text / emoji / system 类型有值）
  final String? content;

  /// 图片 URL（image 类型有值）
  final String? imageUrl;

  /// Coupon 卡片数据（coupon 类型有值）
  /// 结构示例：{ "coupon_id": "...", "deal_title": "...", "amount": 9.9 }
  final Map<String, dynamic>? couponPayload;

  /// 是否为 AI 自动回复消息（客服会话）
  final bool isAiMessage;

  /// 是否已被删除（软删除，UI 显示"消息已撤回"）
  final bool isDeleted;

  /// 消息发送时间
  final DateTime createdAt;

  // ---------- join 字段（来自 users 表） ----------

  /// 发送者显示名称
  final String? senderName;

  /// 发送者头像 URL
  final String? senderAvatarUrl;

  const MessageModel({
    required this.id,
    required this.conversationId,
    this.senderId,
    required this.type,
    this.content,
    this.imageUrl,
    this.couponPayload,
    this.isAiMessage = false,
    this.isDeleted = false,
    required this.createdAt,
    this.senderName,
    this.senderAvatarUrl,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    // 从 join users 对象解析发送者信息
    final senderObj = json['sender'] as Map<String, dynamic>?;
    // 如果 join 用 users 别名也兼容
    final usersObj = json['users'] as Map<String, dynamic>?;
    final resolvedSender = senderObj ?? usersObj;

    // coupon_payload 可能是 Map 也可能是 null，统一处理
    final rawPayload = json['coupon_payload'];
    Map<String, dynamic>? couponPayload;
    if (rawPayload is Map) {
      couponPayload = Map<String, dynamic>.from(rawPayload);
    }

    return MessageModel(
      id: json['id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      senderId: json['sender_id'] as String?,
      type: json['type'] as String? ?? 'text',
      content: json['content'] as String?,
      imageUrl: json['image_url'] as String?,
      couponPayload: couponPayload,
      isAiMessage: json['is_ai_message'] as bool? ?? false,
      isDeleted: json['is_deleted'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      senderName: resolvedSender?['full_name'] as String?,
      senderAvatarUrl: resolvedSender?['avatar_url'] as String?,
    );
  }

  /// 判断是否为系统消息（不显示发送者气泡）
  bool get isSystemMessage => type == 'system';

  /// 获取消息预览文字（用于会话列表最后一条消息展示）
  String get previewText {
    if (isDeleted) return '[Message recalled]';
    switch (type) {
      case 'text':
      case 'emoji':
        return content ?? '';
      case 'image':
        return '[Image]';
      case 'coupon':
        final giftAction = couponPayload?['gift_action'] as String?;
        if (giftAction == 'gift_sent') return '[Gift] Sent you a coupon';
        if (giftAction == 'gift_recalled') return '[Gift] Recalled a coupon';
        return '[Coupon]';
      case 'deal_share':
        final title = couponPayload?['deal_title'] as String? ?? 'Deal';
        return '[Deal] $title';
      case 'merchant_share':
        final name = couponPayload?['merchant_name'] as String? ?? 'Store';
        return '[Store] $name';
      case 'system':
        return content ?? '';
      default:
        return '';
    }
  }
}
