class ReviewModel {
  final String id;
  final String dealId;
  final String userId;
  final int rating;
  final String? comment;
  final bool isVerified;
  final DateTime createdAt;
  final String? userName;
  final String? userAvatarUrl;
  final String? merchantReply; // 商家回复
  final DateTime? repliedAt; // 回复时间
  final List<String> photoUrls; // 评价照片

  const ReviewModel({
    required this.id,
    required this.dealId,
    required this.userId,
    required this.rating,
    this.comment,
    this.isVerified = false,
    required this.createdAt,
    this.userName,
    this.userAvatarUrl,
    this.merchantReply,
    this.repliedAt,
    this.photoUrls = const [],
  });

  factory ReviewModel.fromJson(Map<String, dynamic> json) {
    // 解析 review_photos 嵌套数据（若有）
    final photosRaw = json['review_photos'] as List?;
    final photoUrls = photosRaw
            ?.map((p) => (p as Map<String, dynamic>)['image_url'] as String)
            .toList() ??
        [];

    return ReviewModel(
      id: json['id'] as String,
      dealId: json['deal_id'] as String,
      userId: json['user_id'] as String,
      rating: json['rating'] as int,
      comment: json['comment'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      userName:
          (json['users'] as Map<String, dynamic>?)?['full_name'] as String?,
      userAvatarUrl:
          (json['users'] as Map<String, dynamic>?)?['avatar_url'] as String?,
      merchantReply: json['merchant_reply'] as String?,
      repliedAt: json['replied_at'] != null
          ? DateTime.parse(json['replied_at'] as String)
          : null,
      photoUrls: photoUrls,
    );
  }
}
