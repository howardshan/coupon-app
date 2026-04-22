import 'package:flutter/material.dart';

/// 门店设施数据模型（对应 store_facilities 表）
class StoreFacilityModel {
  final String id;
  final String merchantId;
  final String facilityType;
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
    required this.isFree,
    required this.sortOrder,
  });

  factory StoreFacilityModel.fromJson(Map<String, dynamic> json) {
    return StoreFacilityModel(
      id: json['id'] as String? ?? '',
      merchantId: json['merchant_id'] as String? ?? '',
      facilityType: json['facility_type'] as String? ?? 'other',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      capacity: (json['capacity'] as num?)?.toInt(),
      isFree: json['is_free'] as bool? ?? true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'merchant_id': merchantId,
        'facility_type': facilityType,
        'name': name,
        'description': description,
        'image_url': imageUrl,
        'capacity': capacity,
        'is_free': isFree,
        'sort_order': sortOrder,
      };

  StoreFacilityModel copyWith({
    String? id,
    String? merchantId,
    String? facilityType,
    String? name,
    String? description,
    String? imageUrl,
    int? capacity,
    bool? isFree,
    int? sortOrder,
    bool clearImageUrl = false,
    bool clearDescription = false,
    bool clearCapacity = false,
  }) {
    return StoreFacilityModel(
      id: id ?? this.id,
      merchantId: merchantId ?? this.merchantId,
      facilityType: facilityType ?? this.facilityType,
      name: name ?? this.name,
      description: clearDescription ? null : (description ?? this.description),
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      capacity: clearCapacity ? null : (capacity ?? this.capacity),
      isFree: isFree ?? this.isFree,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// facility_type → Material 图标
  IconData get icon {
    switch (facilityType) {
      case 'private_room':
        return Icons.meeting_room_outlined;
      case 'parking':
        return Icons.local_parking_outlined;
      case 'wifi':
        return Icons.wifi_outlined;
      case 'baby_chair':
        return Icons.child_care_outlined;
      case 'large_table':
        return Icons.table_restaurant_outlined;
      case 'no_smoking':
        return Icons.smoke_free_outlined;
      case 'reservation':
        return Icons.event_available_outlined;
      default:
        return Icons.star_outline_rounded;
    }
  }

  /// facility_type 展示名称
  static String typeLabel(String type) {
    switch (type) {
      case 'private_room':
        return 'Private Room';
      case 'parking':
        return 'Parking';
      case 'wifi':
        return 'WiFi';
      case 'baby_chair':
        return 'Baby Chair';
      case 'large_table':
        return 'Large Table';
      case 'no_smoking':
        return 'No Smoking';
      case 'reservation':
        return 'Reservation';
      default:
        return 'Other';
    }
  }

  static const allTypes = [
    'private_room',
    'parking',
    'wifi',
    'baby_chair',
    'large_table',
    'no_smoking',
    'reservation',
    'other',
  ];
}
