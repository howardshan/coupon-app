// 好友和好友申请数据模型

/// 好友关系模型
/// 对应 friends（或 friendships）表中一条已接受的好友关系记录
class FriendModel {
  /// 好友关系记录 ID（friendships.id）
  final String id;

  /// 好友的 user ID（来自 users 表）
  final String friendId;

  /// 好友显示名称
  final String? fullName;

  /// 好友用户名（@username）
  final String? username;

  /// 好友头像 URL
  final String? avatarUrl;

  /// 成为好友的时间
  final DateTime createdAt;

  const FriendModel({
    required this.id,
    required this.friendId,
    this.fullName,
    this.username,
    this.avatarUrl,
    required this.createdAt,
  });

  factory FriendModel.fromJson(Map<String, dynamic> json) {
    // 好友信息来自 join users 表（可能在 friend_user 或 users 字段）
    final friendUser = json['friend_user'] as Map<String, dynamic>?
        ?? json['users'] as Map<String, dynamic>?;

    return FriendModel(
      id: json['id'] as String? ?? '',
      friendId: json['friend_id'] as String?
          ?? friendUser?['id'] as String? ?? '',
      fullName: friendUser?['full_name'] as String?,
      username: friendUser?['username'] as String?,
      avatarUrl: friendUser?['avatar_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// 展示名：优先用 fullName，否则用 username，最后显示 Unknown
  String get displayName => fullName ?? username ?? 'Unknown';
}

/// 好友申请模型
/// 对应 friend_requests 表
class FriendRequestModel {
  /// 申请记录 ID
  final String id;

  /// 申请发送者 user ID
  final String senderId;

  /// 申请接收者 user ID
  final String receiverId;

  /// 申请状态：'pending' | 'accepted' | 'rejected' | 'cancelled'
  final String status;

  /// 申请发送时间
  final DateTime createdAt;

  // ---------- join 字段：发送者信息 ----------
  final String? senderName;
  final String? senderUsername;
  final String? senderAvatarUrl;

  // ---------- join 字段：接收者信息 ----------
  final String? receiverName;
  final String? receiverUsername;
  final String? receiverAvatarUrl;

  const FriendRequestModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
    this.senderName,
    this.senderUsername,
    this.senderAvatarUrl,
    this.receiverName,
    this.receiverUsername,
    this.receiverAvatarUrl,
  });

  factory FriendRequestModel.fromJson(Map<String, dynamic> json) {
    // 发送者信息来自 join（字段名可能是 sender 或 sender_user）
    final senderObj = json['sender'] as Map<String, dynamic>?
        ?? json['sender_user'] as Map<String, dynamic>?;
    // 接收者信息来自 join（字段名可能是 receiver 或 receiver_user）
    final receiverObj = json['receiver'] as Map<String, dynamic>?
        ?? json['receiver_user'] as Map<String, dynamic>?;

    return FriendRequestModel(
      id: json['id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      receiverId: json['receiver_id'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      senderName: senderObj?['full_name'] as String?,
      senderUsername: senderObj?['username'] as String?,
      senderAvatarUrl: senderObj?['avatar_url'] as String?,
      receiverName: receiverObj?['full_name'] as String?,
      receiverUsername: receiverObj?['username'] as String?,
      receiverAvatarUrl: receiverObj?['avatar_url'] as String?,
    );
  }

  /// 是否仍在待处理状态
  bool get isPending => status == 'pending';
}
