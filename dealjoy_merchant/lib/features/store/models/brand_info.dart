// 品牌信息数据模型
// 对应 brands 表，用于连锁店品牌管理

class BrandInfo {
  const BrandInfo({
    required this.id,
    required this.name,
    this.logoUrl,
    this.description,
    this.category,
    this.website,
    this.companyName,
    this.ein,
    this.storeCount = 0,
  });

  /// 品牌 ID
  final String id;

  /// 品牌名称
  final String name;

  /// 品牌 Logo URL
  final String? logoUrl;

  /// 品牌描述
  final String? description;

  /// 品牌类别
  final String? category;

  /// 品牌官网
  final String? website;

  /// 公司名称
  final String? companyName;

  /// EIN 税号
  final String? ein;

  /// 旗下门店数量（由查询动态返回）
  final int storeCount;

  /// 从 Edge Function 返回的 JSON 构造
  factory BrandInfo.fromJson(Map<String, dynamic> json) {
    return BrandInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      logoUrl: json['logo_url'] as String?,
      description: json['description'] as String?,
      category: json['category'] as String?,
      website: json['website'] as String?,
      companyName: json['company_name'] as String?,
      ein: json['ein'] as String?,
      storeCount: json['store_count'] as int? ?? 0,
    );
  }

  /// 转为 API 请求 JSON（更新品牌信息用）
  Map<String, dynamic> toJson() => {
        'name': name,
        'logo_url': logoUrl,
        'description': description,
        'category': category,
        'website': website,
        'company_name': companyName,
        'ein': ein,
      };

  /// 复制并修改部分字段
  BrandInfo copyWith({
    String? id,
    String? name,
    String? logoUrl,
    String? description,
    String? category,
    String? website,
    String? companyName,
    String? ein,
    int? storeCount,
  }) {
    return BrandInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      logoUrl: logoUrl ?? this.logoUrl,
      description: description ?? this.description,
      category: category ?? this.category,
      website: website ?? this.website,
      companyName: companyName ?? this.companyName,
      ein: ein ?? this.ein,
      storeCount: storeCount ?? this.storeCount,
    );
  }
}
