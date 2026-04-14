// 地区数据模型（对应 service_areas 表）

class ServiceAreaModel {
  final String id;
  final String level; // 'state' | 'metro' | 'city'
  final String stateName;
  final String? metroName;
  final String? cityName;
  final int sortOrder;
  final bool isActive;

  ServiceAreaModel({
    required this.id,
    required this.level,
    required this.stateName,
    this.metroName,
    this.cityName,
    required this.sortOrder,
    required this.isActive,
  });

  factory ServiceAreaModel.fromJson(Map<String, dynamic> json) {
    return ServiceAreaModel(
      id: json['id'] as String? ?? '',
      level: json['level'] as String? ?? '',
      stateName: json['state_name'] as String? ?? '',
      metroName: json['metro_name'] as String?,
      cityName: json['city_name'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
