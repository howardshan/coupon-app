// 广告位配置数据模型
// 对应后端 ad_placement_configs 表，描述各个投放位置的参数与计费规则

/// 广告位配置
class AdPlacementConfig {
  final String placement;     // 位置标识符，如 home_deal_top
  final double minBid;        // 最低出价（美元）
  final int maxSlots;         // 该位置最大同时在投数量
  final String billingType;   // 计费方式: cpm（千次曝光计费）| cpc（点击计费）

  const AdPlacementConfig({
    required this.placement,
    required this.minBid,
    required this.maxSlots,
    required this.billingType,
  });

  /// 从 Edge Function 返回的 JSON 构造，所有字段 null-safe
  factory AdPlacementConfig.fromJson(Map<String, dynamic> json) {
    return AdPlacementConfig(
      placement:   json['placement'] as String? ?? '',
      minBid:      (json['min_bid'] as num?)?.toDouble() ?? 0.0,
      maxSlots:    (json['max_slots'] as num?)?.toInt() ?? 1,
      billingType: json['billing_type'] as String? ?? 'cpc',
    );
  }

  /// 投放位置的用户友好显示名称
  String get displayName {
    switch (placement) {
      case 'home_deal_top':
        return 'Home Page Featured';
      case 'home_deal_feed':
        return 'Home Page Feed';
      case 'category_top':
        return 'Category Page Top';
      case 'search_top':
        return 'Search Results Top';
      case 'merchant_nearby':
        return 'Nearby Merchants';
      default:
        return placement
            .split('_')
            .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
            .join(' ');
    }
  }

  /// 建议价格范围文本，如 "\$0.50 – \$3.00"
  String get suggestedPriceRange {
    // 建议范围：最低出价 ~ 最低出价 × 6（仅作显示参考）
    final low = minBid;
    final high = (minBid * 6).clamp(minBid + 0.1, 9.99);
    return '\$${low.toStringAsFixed(2)} – \$${high.toStringAsFixed(2)}';
  }

  /// 计费方式显示名称
  String get billingTypeDisplayName {
    switch (billingType) {
      case 'cpm':
        return 'Per 1,000 Impressions (CPM)';
      case 'cpc':
        return 'Per Click (CPC)';
      default:
        return billingType.toUpperCase();
    }
  }
}
