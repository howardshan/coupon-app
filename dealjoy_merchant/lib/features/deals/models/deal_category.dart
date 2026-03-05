// Deal 分类模型
// 对应 deal_categories 表

class DealCategory {
  final String id;
  final String merchantId;
  final String name;
  final int sortOrder;

  const DealCategory({
    required this.id,
    required this.merchantId,
    required this.name,
    this.sortOrder = 0,
  });

  factory DealCategory.fromJson(Map<String, dynamic> json) {
    return DealCategory(
      id: json['id'] as String? ?? '',
      merchantId: json['merchant_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'merchant_id': merchantId,
        'name': name,
        'sort_order': sortOrder,
      };
}
