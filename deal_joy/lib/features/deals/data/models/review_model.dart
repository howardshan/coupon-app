// 评价数据模型，支持 5 维度评分 + hashtags + 媒体，兼容旧版单维度 rating
class ReviewModel {
  final String id;
  final String? dealId;
  final String? merchantId;
  final String? orderItemId;
  final String userId;
  final String? reviewerUserId;

  // 5 维度评分
  final int ratingOverall;
  final int? ratingEnvironment;
  final int? ratingHygiene;
  final int? ratingService;
  final int? ratingProduct;

  // 旧字段兼容（旧数据只有 rating）
  final int rating;

  final String? comment;
  final bool isVerified;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // 用户信息（join users 表）
  final String? userName;
  final String? userAvatarUrl;

  // Hashtag IDs + 媒体（新版）
  final List<String> hashtagIds;
  final List<String> mediaUrls;

  // 照片（旧版 review_photos 表兼容）
  final List<String> photoUrls;

  // 商家回复
  final String? merchantReply;
  final DateTime? repliedAt;

  // Deal 标题（join deals 表）
  final String? dealTitle;

  const ReviewModel({
    required this.id,
    this.dealId,
    this.merchantId,
    this.orderItemId,
    required this.userId,
    this.reviewerUserId,
    required this.ratingOverall,
    this.ratingEnvironment,
    this.ratingHygiene,
    this.ratingService,
    this.ratingProduct,
    required this.rating,
    this.comment,
    this.isVerified = false,
    required this.createdAt,
    this.updatedAt,
    this.userName,
    this.userAvatarUrl,
    this.hashtagIds = const [],
    this.mediaUrls = const [],
    this.photoUrls = const [],
    this.merchantReply,
    this.repliedAt,
    this.dealTitle,
  });

  // 是否有商家回复
  bool get hasReply => merchantReply != null && merchantReply!.isNotEmpty;

  factory ReviewModel.fromJson(Map<String, dynamic> json) {
    // 解析旧版 review_photos 嵌套数据
    final photosRaw = json['review_photos'] as List?;
    final photoUrls = photosRaw
            ?.map((p) => (p as Map<String, dynamic>)['image_url'] as String? ?? '')
            .where((url) => url.isNotEmpty)
            .toList() ??
        [];

    // 解析新版 media_urls 数组字段
    final mediaUrlsRaw = json['media_urls'] as List?;
    final mediaUrls = mediaUrlsRaw?.cast<String>() ?? [];

    // 解析 hashtag_ids 数组字段
    final hashtagIdsRaw = json['hashtag_ids'] as List?;
    final hashtagIds = hashtagIdsRaw?.cast<String>() ?? [];

    // 综合评分：优先取 rating_overall，回退到旧 rating 字段
    final ratingOverall =
        (json['rating_overall'] as int?) ?? (json['rating'] as int?) ?? 0;
    final rating = (json['rating'] as int?) ?? ratingOverall;

    // Deal 标题：从 join 嵌套对象或扁平字段读取
    final dealsObj = json['deals'] as Map<String, dynamic>?;
    final dealTitle =
        dealsObj?['title'] as String? ?? json['deal_title'] as String?;

    return ReviewModel(
      id: json['id'] as String? ?? '',
      dealId: json['deal_id'] as String?,
      merchantId: json['merchant_id'] as String?,
      orderItemId: json['order_item_id'] as String?,
      userId: json['user_id'] as String? ?? '',
      reviewerUserId: json['reviewer_user_id'] as String?,
      ratingOverall: ratingOverall,
      ratingEnvironment: json['rating_environment'] as int?,
      ratingHygiene: json['rating_hygiene'] as int?,
      ratingService: json['rating_service'] as int?,
      ratingProduct: json['rating_product'] as int?,
      rating: rating,
      comment: json['comment'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      userName:
          (json['users'] as Map<String, dynamic>?)?['full_name'] as String?,
      userAvatarUrl:
          (json['users'] as Map<String, dynamic>?)?['avatar_url'] as String?,
      hashtagIds: hashtagIds,
      mediaUrls: mediaUrls,
      photoUrls: photoUrls,
      merchantReply: json['merchant_reply'] as String?,
      repliedAt: json['replied_at'] != null
          ? DateTime.tryParse(json['replied_at'] as String)
          : null,
      dealTitle: dealTitle,
    );
  }
}
