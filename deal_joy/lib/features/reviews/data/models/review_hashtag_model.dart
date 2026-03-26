// 评价 Hashtag 数据模型，对应 review_hashtags 表
class ReviewHashtagModel {
  final String id;
  final String tag; // 标签文本，如 '#GreatValue'
  final String category; // 'positive' 或 'negative'
  final int sortOrder; // 排序权重
  final bool isActive; // 是否启用

  const ReviewHashtagModel({
    required this.id,
    required this.tag,
    required this.category,
    required this.sortOrder,
    this.isActive = true,
  });

  factory ReviewHashtagModel.fromJson(Map<String, dynamic> json) {
    return ReviewHashtagModel(
      id: json['id'] as String? ?? '',
      tag: json['tag'] as String? ?? '',
      category: json['category'] as String? ?? 'positive',
      sortOrder: json['sort_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
