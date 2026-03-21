import 'package:flutter/material.dart';

/// 已保存的 Stripe 支付卡片模型
/// 对应 manage-payment-methods Edge Function 返回的数据结构
class SavedCard {
  final String id;        // Stripe PaymentMethod ID
  final String brand;     // visa, mastercard, amex, discover 等
  final String last4;     // 最后四位数字
  final int expMonth;     // 过期月份（1-12）
  final int expYear;      // 过期年份（四位数）
  final bool isDefault;   // 是否为默认卡片

  const SavedCard({
    required this.id,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    required this.isDefault,
  });

  /// 卡片品牌图标（暂时统一用 credit_card，后续可替换为品牌 SVG）
  IconData get brandIcon => Icons.credit_card;

  /// 卡号展示文字，例如 "•••• 4242"
  String get displayText => '•••• $last4';

  /// 过期日期展示文字，例如 "12/28"
  String get expiryText =>
      '${expMonth.toString().padLeft(2, '0')}/${expYear.toString().substring(2)}';

  /// 品牌名称首字母大写，例如 "Visa"、"Mastercard"
  String get brandDisplayName {
    if (brand.isEmpty) return 'Card';
    return brand[0].toUpperCase() + brand.substring(1);
  }

  /// 从 Edge Function 返回的 JSON 解析，所有字段 null-safe
  factory SavedCard.fromJson(Map<String, dynamic> json) {
    return SavedCard(
      id: json['id'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      last4: json['last4'] as String? ?? '••••',
      expMonth: (json['expMonth'] as num?)?.toInt() ?? 0,
      expYear: (json['expYear'] as num?)?.toInt() ?? 0,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}
