/// Deal 分类模型（商家自定义的 Deal 分组）
class DealCategoryModel {
  final String id;
  final String merchantId;
  final String name;
  final int sortOrder;

  const DealCategoryModel({
    required this.id,
    required this.merchantId,
    required this.name,
    this.sortOrder = 0,
  });

  factory DealCategoryModel.fromJson(Map<String, dynamic> json) =>
      DealCategoryModel(
        id: json['id'] as String,
        merchantId: json['merchant_id'] as String,
        name: json['name'] as String? ?? '',
        sortOrder: json['sort_order'] as int? ?? 0,
      );
}
