// 菜品数据模型
// 对应 menu_items 表

// ============================================================
// MenuItem — 单个菜品
// ============================================================
class MenuItem {
  const MenuItem({
    required this.id,
    required this.merchantId,
    required this.name,
    this.imageUrl,
    this.price,
    this.category = 'regular',
    this.categoryId,
    this.categoryName,
    this.recommendationCount = 0,
    this.isSignature = false,
    this.sortOrder = 0,
    this.status = 'active',
    this.createdAt,
  });

  final String id;
  final String merchantId;
  final String name;
  final String? imageUrl;
  final double? price;

  /// 旧分类字段（兼容）: 'signature' | 'popular' | 'regular'
  final String category;

  /// 新分类外键（关联 menu_categories 表）
  final String? categoryId;

  /// 分类名称（join 查询时填充）
  final String? categoryName;

  final int recommendationCount;
  final bool isSignature;
  final int sortOrder;

  /// 状态: 'active' | 'inactive'
  final String status;
  final DateTime? createdAt;

  /// 是否在售
  bool get isActive => status == 'active';

  /// 分类显示标签：优先使用 categoryName，回退到旧 category 字段
  String get categoryLabel {
    if (categoryName != null && categoryName!.isNotEmpty) {
      return categoryName!;
    }
    switch (category) {
      case 'signature':
        return 'Signature';
      case 'popular':
        return 'Popular';
      default:
        return 'Uncategorized';
    }
  }

  /// 从 Supabase JSON 构造
  factory MenuItem.fromJson(Map<String, dynamic> json) {
    // 支持 join 查询：menu_categories { name }
    String? catName;
    if (json['menu_categories'] != null && json['menu_categories'] is Map) {
      catName = (json['menu_categories'] as Map)['name'] as String?;
    }

    return MenuItem(
      id: json['id'] as String,
      merchantId: json['merchant_id'] as String,
      name: json['name'] as String,
      imageUrl: json['image_url'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      category: json['category'] as String? ?? 'regular',
      categoryId: json['category_id'] as String?,
      categoryName: catName,
      recommendationCount: json['recommendation_count'] as int? ?? 0,
      isSignature: json['is_signature'] as bool? ?? false,
      sortOrder: json['sort_order'] as int? ?? 0,
      status: json['status'] as String? ?? 'active',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  /// 转为 API 请求 JSON（创建/更新用）
  Map<String, dynamic> toJson() => {
        'merchant_id': merchantId,
        'name': name,
        'image_url': imageUrl,
        'price': price,
        'category': category,
        'category_id': categoryId,
        'is_signature': isSignature,
        'sort_order': sortOrder,
        'status': status,
      };

  MenuItem copyWith({
    String? id,
    String? merchantId,
    String? name,
    String? imageUrl,
    double? price,
    String? category,
    String? categoryId,
    String? categoryName,
    int? recommendationCount,
    bool? isSignature,
    int? sortOrder,
    String? status,
    DateTime? createdAt,
    bool clearCategoryId = false,
  }) {
    return MenuItem(
      id: id ?? this.id,
      merchantId: merchantId ?? this.merchantId,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      price: price ?? this.price,
      category: category ?? this.category,
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      categoryName: categoryName ?? this.categoryName,
      recommendationCount: recommendationCount ?? this.recommendationCount,
      isSignature: isSignature ?? this.isSignature,
      sortOrder: sortOrder ?? this.sortOrder,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

// ============================================================
// SelectedMenuItem — Deal 创建时选中的菜品（含数量）
// ============================================================
class SelectedMenuItem {
  const SelectedMenuItem({
    required this.menuItem,
    this.quantity = 1,
  });

  final MenuItem menuItem;
  final int quantity;

  /// 小计金额
  double get subtotal => (menuItem.price ?? 0) * quantity;

  SelectedMenuItem copyWith({
    MenuItem? menuItem,
    int? quantity,
  }) {
    return SelectedMenuItem(
      menuItem: menuItem ?? this.menuItem,
      quantity: quantity ?? this.quantity,
    );
  }
}
