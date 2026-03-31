// 赠券记录数据模型 — 对应 Supabase coupon_gifts 表

// 赠送状态枚举
enum GiftStatus {
  pending,   // 已赠出，等待领取
  claimed,   // 已领取
  recalled,  // 已撤回
  expired;   // 赠送期间券已到期

  static GiftStatus fromString(String s) => switch (s) {
    'pending'  => pending,
    'claimed'  => claimed,
    'recalled' => recalled,
    'expired'  => expired,
    _ => pending,
  };

  String get displayLabel => switch (this) {
    pending  => 'Waiting to be claimed',
    claimed  => 'Claimed',
    recalled => 'Recalled',
    expired  => 'Expired',
  };
}

class CouponGiftModel {
  final String id;
  final String orderItemId;
  final String gifterUserId;
  final String? recipientEmail;
  final String? recipientPhone;
  final String? recipientUserId;
  final String? giftMessage;
  final String claimToken;
  final GiftStatus status;
  final DateTime? claimedAt;
  final DateTime? recalledAt;
  final DateTime? tokenExpiresAt;
  final DateTime createdAt;

  /// 赠送渠道：'external'（email/phone）| 'in_app'（好友赠送）
  final String giftType;

  const CouponGiftModel({
    required this.id,
    required this.orderItemId,
    required this.gifterUserId,
    this.recipientEmail,
    this.recipientPhone,
    this.recipientUserId,
    this.giftMessage,
    required this.claimToken,
    required this.status,
    this.claimedAt,
    this.recalledAt,
    this.tokenExpiresAt,
    required this.createdAt,
    this.giftType = 'external',
  });

  /// 是否为好友赠送
  bool get isInApp => giftType == 'in_app';

  /// 展示用：优先显示邮箱，其次电话
  String get recipientDisplay => recipientEmail ?? recipientPhone ?? 'Unknown';

  /// 可撤回：pending 状态，或好友赠送的 claimed 状态（后端会检查券是否已使用）
  bool get canRecall =>
      status == GiftStatus.pending ||
      (isInApp && status == GiftStatus.claimed);

  /// 可修改受赠方：仅 pending 状态
  bool get canEdit => status == GiftStatus.pending;

  factory CouponGiftModel.fromJson(Map<String, dynamic> json) {
    return CouponGiftModel(
      id: json['id'] as String? ?? '',
      orderItemId: json['order_item_id'] as String? ?? '',
      gifterUserId: json['gifter_user_id'] as String? ?? '',
      recipientEmail: json['recipient_email'] as String?,
      recipientPhone: json['recipient_phone'] as String?,
      recipientUserId: json['recipient_user_id'] as String?,
      giftMessage: json['gift_message'] as String?,
      claimToken: json['claim_token'] as String? ?? '',
      giftType: json['gift_type'] as String? ?? 'external',
      status: GiftStatus.fromString(json['status'] as String? ?? 'pending'),
      claimedAt: json['claimed_at'] != null
          ? DateTime.tryParse(json['claimed_at'] as String)
          : null,
      recalledAt: json['recalled_at'] != null
          ? DateTime.tryParse(json['recalled_at'] as String)
          : null,
      tokenExpiresAt: json['token_expires_at'] != null
          ? DateTime.tryParse(json['token_expires_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}
