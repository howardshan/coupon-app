// 购物车单项模型 — V3 DB 持久化版本
// 每行 = 一张券，无 quantity 字段

class CartItemModel {
  // DB 主键
  final String id;
  final String userId;
  final String dealId;
  // 加入时快照单价
  final double unitPrice;
  // 购买时指定的门店（多店 deal 时由用户选择）
  final String? purchasedMerchantId;
  // 适用门店 ID 列表（快照）
  final List<String> applicableStoreIds;
  // 用户选择的 deal option groups 快照
  final Map<String, dynamic>? selectedOptions;
  final DateTime createdAt;

  // ── join 字段（从 deals + merchants 表）──
  final String dealTitle;
  final String dealImageUrl;
  final double? originalPrice;
  final String merchantName;
  final String? merchantId;
  // 商家所在 metro 区域（用于 checkout 本地税费预览）
  final String? merchantMetroArea;
  // 每账号限购数量快照，-1 表示无限制
  final int maxPerAccount;
  // 该 deal 总库存上限，-1 或 0 表示无限制
  final int stockLimit;
  // 该 deal 全局已售出数量（由触发器维护，不受 RLS 限制）
  final int totalSold;

  const CartItemModel({
    required this.id,
    required this.userId,
    required this.dealId,
    required this.unitPrice,
    this.purchasedMerchantId,
    this.applicableStoreIds = const [],
    this.selectedOptions,
    required this.createdAt,
    required this.dealTitle,
    required this.dealImageUrl,
    this.originalPrice,
    required this.merchantName,
    this.merchantId,
    this.merchantMetroArea,
    this.maxPerAccount = -1,
    this.stockLimit = -1,
    this.totalSold = 0,
  });

  /// 从 Supabase 查询结果解析（含 deals join merchants 嵌套）
  factory CartItemModel.fromJson(Map<String, dynamic> json) {
    // deals join 子对象
    final deal = json['deals'] as Map<String, dynamic>? ?? {};
    // merchants join 子对象（在 deals 内）
    final merchant = deal['merchants'] as Map<String, dynamic>? ?? {};

    // image_urls 取第一张作为封面
    final imageUrls = deal['image_urls'] as List? ?? [];
    final imageUrl = imageUrls.isNotEmpty
        ? (imageUrls.first as String? ?? '')
        : '';

    // applicable_store_ids 数组
    final storeIds = json['applicable_store_ids'] as List? ?? [];

    return CartItemModel(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      dealId: json['deal_id'] as String? ?? '',
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      purchasedMerchantId: json['purchased_merchant_id'] as String?,
      applicableStoreIds:
          storeIds.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList(),
      selectedOptions: json['selected_options'] as Map<String, dynamic>?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      dealTitle: deal['title'] as String? ?? '',
      dealImageUrl: imageUrl,
      originalPrice: (deal['original_price'] as num?)?.toDouble(),
      merchantName: merchant['name'] as String? ?? '',
      merchantId: merchant['id'] as String?,
      merchantMetroArea: merchant['metro_area'] as String?,
      maxPerAccount: deal['max_per_account'] as int? ?? -1,
      stockLimit: deal['stock_limit'] as int? ?? -1,
      totalSold: deal['total_sold'] as int? ?? 0,
    );
  }
}
