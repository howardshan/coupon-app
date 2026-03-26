// 通知数据模型
// 支持多种通知类型：交易、公告、好友动态、好友申请、评价回复、聊天消息

class NotificationModel {
  /// 通知唯一 ID
  final String id;

  /// 通知类型：
  /// 'transaction'      — 订单/支付/退款相关
  /// 'announcement'     — 平台公告
  /// 'friend_activity'  — 好友动态（好友发布了评价等）
  /// 'friend_request'   — 好友申请
  /// 'review_reply'     — 商家回复评价
  /// 'chat_message'     — 新聊天消息提醒
  final String type;

  /// 通知标题（推送通知的 title）
  final String title;

  /// 通知正文
  final String body;

  /// 扩展数据（跳转参数等，如 order_id / deal_id / conversation_id）
  final Map<String, dynamic>? data;

  /// 是否已读
  final bool isRead;

  /// 通知创建时间
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    // data 字段可能是 Map 或 null
    final rawData = json['data'];
    Map<String, dynamic>? data;
    if (rawData is Map) {
      data = Map<String, dynamic>.from(rawData);
    }

    return NotificationModel(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'announcement',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      data: data,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// 是否为需要高优先级展示的通知类型
  bool get isHighPriority =>
      type == 'friend_request' || type == 'transaction';
}
