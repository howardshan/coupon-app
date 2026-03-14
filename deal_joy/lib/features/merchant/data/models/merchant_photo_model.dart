/// 门店照片模型
class MerchantPhotoModel {
  final String id;
  final String merchantId;
  final String photoType; // 'storefront' | 'environment' | 'product'
  final String? category; // 'main_hall' | 'entrance' | 'interior' | 'private_room'
  final String photoUrl;
  final int sortOrder;

  const MerchantPhotoModel({
    required this.id,
    required this.merchantId,
    required this.photoType,
    this.category,
    required this.photoUrl,
    this.sortOrder = 0,
  });

  factory MerchantPhotoModel.fromJson(Map<String, dynamic> json) =>
      MerchantPhotoModel(
        id: json['id'] as String,
        merchantId: json['merchant_id'] as String,
        photoType: json['photo_type'] as String,
        category: json['category'] as String?,
        photoUrl: json['photo_url'] as String,
        sortOrder: json['sort_order'] as int? ?? 0,
      );

  /// 照片分类的英文展示名
  String get categoryLabel => switch (category) {
        'main_hall' => 'Main Hall',
        'entrance' => 'Entrance',
        'interior' => 'Interior',
        'private_room' => 'Private Room',
        _ => switch (photoType) {
            'storefront' => 'Storefront',
            'environment' => 'Environment',
            'license' => 'License',
            _ => 'Photo',
          },
      };
}
