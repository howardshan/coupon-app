// 门店摘要数据模型
// 用于品牌管理员的门店列表（轻量版，不含照片/营业时间）

class StoreSummary {
  const StoreSummary({
    required this.id,
    required this.name,
    this.address,
    this.city,
    this.status,
    this.logoUrl,
    this.phone,
  });

  /// 门店 ID
  final String id;

  /// 门店名称
  final String name;

  /// 地址
  final String? address;

  /// 城市
  final String? city;

  /// 审核状态 (pending/approved/rejected)
  final String? status;

  /// 门店 Logo URL
  final String? logoUrl;

  /// 联系电话
  final String? phone;

  /// 从 Edge Function 返回的 JSON 构造
  factory StoreSummary.fromJson(Map<String, dynamic> json) {
    return StoreSummary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      address: json['address'] as String?,
      city: json['city'] as String?,
      status: json['status'] as String?,
      logoUrl: json['logo_url'] as String?,
      phone: json['phone'] as String?,
    );
  }

  /// 复制并修改部分字段
  StoreSummary copyWith({
    String? id,
    String? name,
    String? address,
    String? city,
    String? status,
    String? logoUrl,
    String? phone,
  }) {
    return StoreSummary(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      city: city ?? this.city,
      status: status ?? this.status,
      logoUrl: logoUrl ?? this.logoUrl,
      phone: phone ?? this.phone,
    );
  }
}
