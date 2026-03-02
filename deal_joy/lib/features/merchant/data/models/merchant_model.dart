class MerchantModel {
  final String id;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? address;
  final String? phone;
  final double? lat;
  final double? lng;

  MerchantModel({
    required this.id,
    required this.name,
    this.description,
    this.logoUrl,
    this.address,
    this.phone,
    this.lat,
    this.lng,
  });

  factory MerchantModel.fromJson(Map<String, dynamic> json) => MerchantModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        logoUrl: json['logo_url'] as String?,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );
}
