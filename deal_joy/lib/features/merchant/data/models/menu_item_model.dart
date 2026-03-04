/// 菜品模型
class MenuItemModel {
  final String id;
  final String merchantId;
  final String name;
  final String? imageUrl;
  final double? price;
  final String category; // 'signature' | 'popular' | 'regular'
  final int recommendationCount;
  final bool isSignature;
  final int sortOrder;

  const MenuItemModel({
    required this.id,
    required this.merchantId,
    required this.name,
    this.imageUrl,
    this.price,
    this.category = 'regular',
    this.recommendationCount = 0,
    this.isSignature = false,
    this.sortOrder = 0,
  });

  factory MenuItemModel.fromJson(Map<String, dynamic> json) => MenuItemModel(
        id: json['id'] as String,
        merchantId: json['merchant_id'] as String,
        name: json['name'] as String,
        imageUrl: json['image_url'] as String?,
        price: (json['price'] as num?)?.toDouble(),
        category: json['category'] as String? ?? 'regular',
        recommendationCount: json['recommendation_count'] as int? ?? 0,
        isSignature: json['is_signature'] as bool? ?? false,
        sortOrder: json['sort_order'] as int? ?? 0,
      );
}
