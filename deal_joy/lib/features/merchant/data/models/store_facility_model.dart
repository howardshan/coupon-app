/// 设施信息模型
class StoreFacilityModel {
  final String id;
  final String merchantId;
  final String facilityType; // 'private_room' | 'parking' | 'wifi' | 'baby_chair' | 'large_table' | 'no_smoking' | 'reservation' | 'other'
  final String name;
  final String? description;
  final String? imageUrl;
  final int? capacity;
  final bool isFree;
  final int sortOrder;

  const StoreFacilityModel({
    required this.id,
    required this.merchantId,
    required this.facilityType,
    required this.name,
    this.description,
    this.imageUrl,
    this.capacity,
    this.isFree = true,
    this.sortOrder = 0,
  });

  factory StoreFacilityModel.fromJson(Map<String, dynamic> json) =>
      StoreFacilityModel(
        id: json['id'] as String,
        merchantId: json['merchant_id'] as String,
        facilityType: json['facility_type'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        imageUrl: json['image_url'] as String?,
        capacity: json['capacity'] as int?,
        isFree: json['is_free'] as bool? ?? true,
        sortOrder: json['sort_order'] as int? ?? 0,
      );

  /// 设施类型对应的图标名（供 UI 层使用）
  String get iconName => switch (facilityType) {
        'private_room' => 'meeting_room',
        'parking' => 'local_parking',
        'wifi' => 'wifi',
        'baby_chair' => 'child_care',
        'large_table' => 'table_restaurant',
        'no_smoking' => 'smoke_free',
        'reservation' => 'event_available',
        _ => 'info',
      };
}
