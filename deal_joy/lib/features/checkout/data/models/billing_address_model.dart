/// 账单地址模型
class BillingAddressModel {
  final String id;
  final String userId;
  final String label;
  final String addressLine1;
  final String addressLine2;
  final String city;
  final String state;
  final String postalCode;
  final String country;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BillingAddressModel({
    required this.id,
    required this.userId,
    this.label = '',
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.city = '',
    this.state = '',
    this.postalCode = '',
    this.country = 'US',
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BillingAddressModel.fromJson(Map<String, dynamic> json) {
    return BillingAddressModel(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      addressLine1: json['address_line1'] as String? ?? '',
      addressLine2: json['address_line2'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      postalCode: json['postal_code'] as String? ?? '',
      country: json['country'] as String? ?? 'US',
      isDefault: json['is_default'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'user_id': userId,
    'label': label,
    'address_line1': addressLine1,
    'address_line2': addressLine2,
    'city': city,
    'state': state,
    'postal_code': postalCode,
    'country': country,
    'is_default': isDefault,
  };

  /// 一行摘要，用于 UI 展示
  String get summary {
    final parts = <String>[addressLine1];
    if (addressLine2.isNotEmpty) parts.add(addressLine2);
    parts.addAll([city, state, postalCode]);
    return parts.where((s) => s.isNotEmpty).join(', ');
  }
}
