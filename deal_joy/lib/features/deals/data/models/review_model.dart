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
  });

  factory ReviewModel.fromJson(Map<String, dynamic> json) => ReviewModel(
    id: json['id'] as String,
    dealId: json['deal_id'] as String,
    userId: json['user_id'] as String,
    rating: json['rating'] as int,
    comment: json['comment'] as String?,
    isVerified: json['is_verified'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at'] as String),
    userName: (json['users'] as Map<String, dynamic>?)?['full_name'] as String?,
    userAvatarUrl:
        (json['users'] as Map<String, dynamic>?)?['avatar_url'] as String?,
  );
}
