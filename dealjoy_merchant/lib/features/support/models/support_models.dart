// 客服聊天数据模型

// ============================================================
// SupportConversation — 每个商家唯一一个会话
// ============================================================
class SupportConversation {
  final String id;
  final String merchantId;
  final String status; // 'open' | 'closed'
  final DateTime createdAt;
  final DateTime updatedAt;

  const SupportConversation({
    required this.id,
    required this.merchantId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SupportConversation.fromJson(Map<String, dynamic> json) {
    return SupportConversation(
      id:         json['id'] as String? ?? '',
      merchantId: json['merchant_id'] as String? ?? '',
      status:     json['status'] as String? ?? 'open',
      createdAt:  json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt:  json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }
}

// ============================================================
// SupportMessage — 单条消息
// ============================================================
class SupportMessage {
  final String id;
  final String conversationId;
  final String senderRole; // 'merchant' | 'admin'
  final String content;
  final DateTime createdAt;

  const SupportMessage({
    required this.id,
    required this.conversationId,
    required this.senderRole,
    required this.content,
    required this.createdAt,
  });

  bool get isFromMerchant => senderRole == 'merchant';
  bool get isFromAdmin    => senderRole == 'admin';

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    return SupportMessage(
      id:             json['id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      senderRole:     json['sender_role'] as String? ?? 'merchant',
      content:        json['content'] as String? ?? '',
      createdAt:      json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}
