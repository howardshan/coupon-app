// 菜品分类数据模型
// 对应 menu_categories 表

// ============================================================
// MenuCategory — 商家自定义菜品分类
// ============================================================
class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.merchantId,
    required this.name,
    this.sortOrder = 0,
    this.createdAt,
  });

  final String id;
  final String merchantId;
  final String name;
  final int sortOrder;
  final DateTime? createdAt;

  /// 从 Supabase JSON 构造
  factory MenuCategory.fromJson(Map<String, dynamic> json) {
    return MenuCategory(
      id: json['id'] as String,
      merchantId: json['merchant_id'] as String,
      name: json['name'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  /// 转为 API 请求 JSON
  Map<String, dynamic> toJson() => {
        'merchant_id': merchantId,
        'name': name,
        'sort_order': sortOrder,
      };

  MenuCategory copyWith({
    String? id,
    String? merchantId,
    String? name,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return MenuCategory(
      id: id ?? this.id,
      merchantId: merchantId ?? this.merchantId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
