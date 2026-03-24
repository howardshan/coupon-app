import 'package:flutter/material.dart';

/// 卡片账单地址模型
/// 对应 Stripe PaymentMethod billing_details.address 结构
class CardBillingAddress {
  final String line1;       // 街道地址第一行
  final String line2;       // 街道地址第二行（可选）
  final String city;        // 城市
  final String state;       // 州/省
  final String postalCode;  // 邮政编码
  final String country;     // 国家代码（如 US）

  const CardBillingAddress({
    required this.line1,
    required this.line2,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
  });

  /// 从 JSON 解析，所有字段 null-safe
  factory CardBillingAddress.fromJson(Map<String, dynamic> json) {
    return CardBillingAddress(
      line1: json['line1'] as String? ?? '',
      line2: json['line2'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      postalCode: json['postalCode'] as String? ?? '',
      country: json['country'] as String? ?? '',
    );
  }

  /// 单行地址摘要，跳过空字段，格式："{line1}, {city}, {state} {postalCode}"
  String get summary {
    final parts = <String>[];
    if (line1.isNotEmpty) parts.add(line1);
    if (city.isNotEmpty) parts.add(city);
    // 州和邮编放在一起，中间用空格
    final stateZip = [state, postalCode].where((s) => s.isNotEmpty).join(' ');
    if (stateZip.isNotEmpty) parts.add(stateZip);
    return parts.join(', ');
  }
}

/// 已保存的 Stripe 支付卡片模型
/// 对应 manage-payment-methods Edge Function 返回的数据结构
class SavedCard {
  final String id;        // Stripe PaymentMethod ID
  final String brand;     // visa, mastercard, amex, discover 等
  final String last4;     // 最后四位数字
  final int expMonth;     // 过期月份（1-12）
  final int expYear;      // 过期年份（四位数）
  final bool isDefault;                       // 是否为默认卡片
  final CardBillingAddress? billingAddress;   // 账单地址（可选）

  const SavedCard({
    required this.id,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    required this.isDefault,
    this.billingAddress,
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
      billingAddress: json['billingAddress'] != null
          ? CardBillingAddress.fromJson(
              json['billingAddress'] as Map<String, dynamic>)
          : null,
    );
  }
}
