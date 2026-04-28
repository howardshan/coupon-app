// 团购券数据模型 — 对应 Supabase coupons 表，携带关联的 deal/merchant 信息

import 'dart:convert';

class CouponModel {
  final String id;
  final String orderId;
  final String userId;
  final String dealId;
  final String merchantId;
  final String qrCode;
  final String status; // unused | used | expired | refunded | voided
  final String? voidReason;
  final DateTime? voidedAt;
  final DateTime expiresAt;
  final DateTime? usedAt;
  final DateTime createdAt;
  final String? giftedFrom;
  final String? verifiedBy;

  // 好友赠送相关
  /// 赠送者 user ID（好友赠送时由 send-gift 写入）
  final String? giftedFromUserId;
  /// 当前持有者 user ID（赠送后 = 受赠人）
  final String? currentHolderUserId;
  /// 赠送者姓名（join users 表获取）
  final String? giftedFromUserName;

  // V3 新增字段 — 关联 order_items
  /// 关联的 order_item ID（V3 系统新增）
  final String? orderItemId;

  /// 16位原始券码（V3 order_items.coupon_code 字段）
  final String? couponCode;

  // Join 字段 — 来自 deals 表
  final String? dealTitle;
  final String? dealDescription;
  final String? dealImageUrl;
  final String? refundPolicy;
  /// 使用规则（来自 deals.usage_rules，text[]）
  final List<String> usageRules;
  /// 购买须知长文案（来自 deals.usage_notes；部分商家只填此项未填 usage_rules）
  final String? usageNotes;

  // Join 字段 — 来自 deals.merchants 表
  final String? merchantName;
  final String? merchantLogoUrl;
  final String? merchantAddress;
  final String? merchantPhone;

  // 多店通用：适用门店 ID 列表（旧字段，来自 deals.applicable_merchant_ids）
  final List<String>? applicableMerchantIds;

  // 购买时门店快照（来自 orders.applicable_store_ids）
  final List<String>? applicableStoreIds;

  // 订单编号（来自 orders join）
  final String? orderNumber;

  // 退款信息（来自 order_items join）
  final double? unitPrice;
  /// 税额快照（来自 order_items.tax_amount）
  final double taxAmount;
  /// 税率快照（来自 order_items.tax_rate，如 0.0825）
  final double? taxRate;
  final DateTime? refundedAt;
  final double? refundAmount;
  final String? refundMethod; // 'original_payment' | 'store_credit'

  // order_items 级别的客户状态（V3 新增，用于精确过滤）
  final String? customerStatus;

  /// 套餐包含内容原始文本（来自 deals.package_contents）
  final String? packageContents;
  /// 用户下单时选择的选项快照（来自 order_items.selected_options JSONB；目前多为 NULL）
  final Map<String, dynamic>? selectedOptions;

  const CouponModel({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.dealId,
    required this.merchantId,
    required this.qrCode,
    required this.status,
    this.voidReason,
    this.voidedAt,
    required this.expiresAt,
    this.usedAt,
    required this.createdAt,
    this.giftedFrom,
    this.verifiedBy,
    this.giftedFromUserId,
    this.currentHolderUserId,
    this.giftedFromUserName,
    this.orderItemId,
    this.couponCode,
    this.dealTitle,
    this.dealDescription,
    this.dealImageUrl,
    this.refundPolicy,
    this.usageRules = const [],
    this.usageNotes,
    this.merchantName,
    this.merchantLogoUrl,
    this.merchantAddress,
    this.merchantPhone,
    this.applicableMerchantIds,
    this.applicableStoreIds,
    this.orderNumber,
    this.unitPrice,
    this.taxAmount = 0.0,
    this.taxRate,
    this.refundedAt,
    this.refundAmount,
    this.refundMethod,
    this.customerStatus,
    this.packageContents,
    this.selectedOptions,
  });

  /// 解析 deals.usage_rules（text[] / JSON 数组 / 异常字符串）
  static List<String> parseUsageRulesDynamic(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .map((e) => e?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return [];
      if (s.startsWith('[')) {
        try {
          final decoded = jsonDecode(s);
          return parseUsageRulesDynamic(decoded);
        } catch (_) {}
      }
    }
    return [];
  }

  factory CouponModel.fromJson(Map<String, dynamic> json) {
    // V3：从 order_items join 获取 applicable_store_ids（新字段）
    // 注意：order_items 是反向 FK join，返回 List 而非 Map，取第一个元素
    final orderItemsList = json['order_items'] as List?;
    final orderItems = (orderItemsList != null && orderItemsList.isNotEmpty)
        ? orderItemsList.first as Map<String, dynamic>?
        : null;
    // 向后兼容旧版：从 orders join 获取（也可能是 List）
    final ordersRaw = json['orders'];
    final orders = ordersRaw is Map<String, dynamic>
        ? ordersRaw
        : (ordersRaw is List && ordersRaw.isNotEmpty ? ordersRaw.first as Map<String, dynamic>? : null);

    // 解析嵌套的 deals：PostgREST 在部分 embed 下可能返回 Map 或单元素 List
    final rawDeals = json['deals'];
    Map<String, dynamic>? deals;
    if (rawDeals is Map<String, dynamic>) {
      deals = rawDeals;
    } else if (rawDeals is List && rawDeals.isNotEmpty) {
      final first = rawDeals.first;
      if (first is Map<String, dynamic>) deals = first;
    }

    // 解析嵌套的 deals.merchants 对象
    final merchants = deals?['merchants'] as Map<String, dynamic>?;

    // deal 图片取第一张
    String? dealImageUrl;
    if (deals != null) {
      final imageUrls = deals['image_urls'] as List?;
      if (imageUrls != null && imageUrls.isNotEmpty) {
        dealImageUrl = imageUrls.first as String?;
      }
    }

    final usageRules = parseUsageRulesDynamic(deals?['usage_rules']);

    return CouponModel(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      userId: json['user_id'] as String,
      dealId: json['deal_id'] as String,
      merchantId: json['merchant_id'] as String,
      qrCode: json['qr_code'] as String,
      status: json['status'] as String? ?? 'unused',
      voidReason: json['void_reason'] as String?,
      voidedAt: json['voided_at'] != null
          ? DateTime.parse(json['voided_at'] as String)
          : null,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      usedAt: json['used_at'] != null
          ? DateTime.parse(json['used_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      giftedFrom: json['gifted_from'] as String?,
      verifiedBy: json['verified_by'] as String?,
      giftedFromUserId: json['gifted_from_user_id'] as String?,
      currentHolderUserId: json['current_holder_user_id'] as String?,
      giftedFromUserName: (json['gifter_user'] as Map<String, dynamic>?)?['full_name'] as String?,
      orderItemId: json['order_item_id'] as String?,
      couponCode: json['coupon_code'] as String?,
      dealTitle: deals?['title'] as String?,
      dealDescription: deals?['description'] as String?,
      dealImageUrl: dealImageUrl,
      refundPolicy: deals?['refund_policy'] as String?,
      usageRules: usageRules,
      usageNotes: deals?['usage_notes'] as String?,
      merchantName: merchants?['name'] as String?,
      merchantLogoUrl: merchants?['logo_url'] as String?,
      merchantAddress: merchants?['address'] as String?,
      merchantPhone: merchants?['phone'] as String?,
      applicableMerchantIds: (deals?['applicable_merchant_ids'] as List?)
          ?.map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
      // 订单编号（从 orders join 获取）
      orderNumber: orders?['order_number'] as String?,
      // V3：优先从 order_items join 获取，向后兼容旧版从 orders join 获取
      applicableStoreIds: ((orderItems?['applicable_store_ids'] ??
                  orders?['applicable_store_ids']) as List?)
          ?.map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
      // 退款信息（从 order_items join 获取）
      unitPrice: (orderItems?['unit_price'] as num?)?.toDouble(),
      taxAmount: (orderItems?['tax_amount'] as num?)?.toDouble() ?? 0.0,
      taxRate: (orderItems?['tax_rate'] as num?)?.toDouble(),
      refundedAt: orderItems?['refunded_at'] != null
          ? DateTime.parse(orderItems!['refunded_at'] as String)
          : null,
      refundAmount: (orderItems?['refund_amount'] as num?)?.toDouble(),
      refundMethod: orderItems?['refund_method'] as String?,
      customerStatus: orderItems?['customer_status'] as String?,
      packageContents: deals?['package_contents'] as String?,
      selectedOptions: orderItems?['selected_options'] as Map<String, dynamic>?,
    );
  }

  // 状态便捷 getter（过期同时考虑 status 与过期时间，便于展示「已过期」提示）
  bool get isUnused => status == 'unused';
  bool get isUsed => status == 'used';
  /// 按商家时区（Dallas CST/CDT）判断是否过期
  /// expires_at 存的是 UTC 午夜（如 Apr 19 00:00 UTC），代表"Apr 19 当天可用"
  /// 商家时区 CST = UTC-6，Apr 19 23:59:59 CST = UTC Apr 20 05:59:59
  /// 所以 expires_at + 30h = Apr 20 06:00 UTC 之后才算过期
  /// 这确保 CST 当天 23:59 不过期、CDT 当天 23:59 也不过期
  bool get isExpired =>
      status == 'expired' ||
      DateTime.now().toUtc().isAfter(
          expiresAt.toUtc().add(const Duration(hours: 30)));
  bool get isRefunded => status == 'refunded';
  bool get isVoided => status == 'voided';

  /// 详情页「Usage Rules」展示行：优先 usage_rules 数组，否则拆 usage_notes
  List<String> get usageDisplayLines {
    if (usageRules.isNotEmpty) return usageRules;
    final notes = usageNotes?.trim() ?? '';
    if (notes.isEmpty) return [];
    return notes
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 当前可持券核销的用户（好友赠送后为受赠人，否则为购买人）
  String get effectiveHolderUserId =>
      currentHolderUserId ?? userId;

  /// 指定用户是否为当前持券人（用于详情页 QR / 文案分流）
  bool isHeldByUser(String uid) => effectiveHolderUserId == uid;

  /// 是否仍为订单购买人且持有该券（可退款、转赠；已赠出给好友后应为 false）
  bool viewerCanManagePurchaseActions(String? viewerUserId) {
    if (viewerUserId == null || viewerUserId.isEmpty) return false;
    if (userId != viewerUserId) return false;
    return currentHolderUserId == null ||
        currentHolderUserId == viewerUserId;
  }

  /// 套餐内容行列表（去除前缀符号、过滤空行），用于详情页和卡片展示
  List<String> get packageLines {
    final pc = packageContents?.trim() ?? '';
    if (pc.isEmpty) return [];
    return pc
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'^[•\-\*]\s*'), '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 合并 deals 兜底查询（如 usage_rules / refund_policy）
  CouponModel copyWith({
    List<String>? usageRules,
    String? refundPolicy,
    String? usageNotes,
  }) {
    return CouponModel(
      id: id,
      orderId: orderId,
      userId: userId,
      dealId: dealId,
      merchantId: merchantId,
      qrCode: qrCode,
      status: status,
      voidReason: voidReason,
      voidedAt: voidedAt,
      expiresAt: expiresAt,
      usedAt: usedAt,
      createdAt: createdAt,
      giftedFrom: giftedFrom,
      verifiedBy: verifiedBy,
      giftedFromUserId: giftedFromUserId,
      currentHolderUserId: currentHolderUserId,
      giftedFromUserName: giftedFromUserName,
      orderItemId: orderItemId,
      couponCode: couponCode,
      dealTitle: dealTitle,
      dealDescription: dealDescription,
      dealImageUrl: dealImageUrl,
      refundPolicy: refundPolicy ?? this.refundPolicy,
      usageRules: usageRules ?? this.usageRules,
      usageNotes: usageNotes ?? this.usageNotes,
      merchantName: merchantName,
      merchantLogoUrl: merchantLogoUrl,
      merchantAddress: merchantAddress,
      merchantPhone: merchantPhone,
      applicableMerchantIds: applicableMerchantIds,
      applicableStoreIds: applicableStoreIds,
      orderNumber: orderNumber,
      unitPrice: unitPrice,
      taxAmount: taxAmount,
      taxRate: taxRate,
      refundedAt: refundedAt,
      refundAmount: refundAmount,
      refundMethod: refundMethod,
      customerStatus: customerStatus,
      packageContents: packageContents,
      selectedOptions: selectedOptions,
    );
  }
}
