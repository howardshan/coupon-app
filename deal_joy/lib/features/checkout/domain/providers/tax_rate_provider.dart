// 税率查询 Provider
// 根据 merchant 的 metro_area 查询 metro_tax_rates 表获取适用税率

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../cart/data/models/cart_item_model.dart';

/// 根据 merchantId 查询适用税率（返回小数，如 0.0825）
/// 保留以兼容旧代码，checkout 预览请用 metroTaxRatesProvider + cartTaxEstimateProvider
final taxRateByMerchantProvider =
    FutureProvider.family<double, String>((ref, merchantId) async {
  final client = ref.watch(supabaseClientProvider);

  // 查 merchant 的 metro_area
  final merchantData = await client
      .from('merchants')
      .select('metro_area')
      .eq('id', merchantId)
      .maybeSingle();

  final metroArea = merchantData?['metro_area'] as String?;
  if (metroArea == null || metroArea.isEmpty) return 0;

  // 查 metro_tax_rates
  final taxData = await client
      .from('metro_tax_rates')
      .select('tax_rate')
      .eq('metro_area', metroArea)
      .eq('is_active', true)
      .maybeSingle();

  return (taxData?['tax_rate'] as num?)?.toDouble() ?? 0;
});

/// 一次性把所有活跃 metro 税率拉回来缓存，供 checkout 本地计算税费使用
/// 返回 `{ metroArea → rate }`，如 Dallas → 0.0825
/// 保留以兼容旧代码，优先使用 cityTaxRatesProvider
final metroTaxRatesProvider = FutureProvider<Map<String, double>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('metro_tax_rates')
      .select('metro_area, tax_rate')
      .eq('is_active', true);

  final map = <String, double>{};
  for (final row in (rows as List)) {
    final metro = (row as Map<String, dynamic>)['metro_area'] as String?;
    final rate = (row['tax_rate'] as num?)?.toDouble();
    if (metro != null && rate != null) {
      map[metro] = rate;
    }
  }
  return map;
});

/// City → tax rate 映射（通过 city_metro_map 映射到 metro 再查税率）
/// 返回 `{ city (lower-case) → rate }`，如 Frisco → 0.0825（Frisco 属于 Dallas metro）
/// key 一律 lower-case，查询时也要 toLowerCase() 避免大小写不一致
final cityTaxRatesProvider = FutureProvider<Map<String, double>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  // 用嵌套 select 一次拿到所有 city + 对应 metro 的 tax_rate
  final rows = await client
      .from('city_metro_map')
      .select('city, metro_area, metro_tax_rates!inner(tax_rate, is_active)');

  final map = <String, double>{};
  for (final row in (rows as List)) {
    final city = (row as Map<String, dynamic>)['city'] as String?;
    final metroRates = row['metro_tax_rates'];
    double? rate;
    if (metroRates is Map<String, dynamic>) {
      final active = metroRates['is_active'] as bool? ?? false;
      if (active) rate = (metroRates['tax_rate'] as num?)?.toDouble();
    } else if (metroRates is List && metroRates.isNotEmpty) {
      final first = metroRates.first as Map<String, dynamic>;
      final active = first['is_active'] as bool? ?? false;
      if (active) rate = (first['tax_rate'] as num?)?.toDouble();
    }
    if (city != null && city.isNotEmpty && rate != null) {
      map[city.toLowerCase()] = rate;
    }
  }
  return map;
});

/// Checkout 本地税费预估结果
class TaxEstimate {
  /// 总税费
  final double totalTax;

  /// 按 metroArea 分组的税费明细（可选，供 UI 分组展示）
  final Map<String, double> breakdown;

  /// 是否有任何 item 未知税率（metroArea 为 null 或 metro_tax_rates 缺失）
  /// 为 true 时 UI 可显示 "Tax (est.)" 避免给用户精确承诺
  final bool hasUnknownRate;

  const TaxEstimate({
    required this.totalTax,
    this.breakdown = const {},
    this.hasUnknownRate = false,
  });

  static const TaxEstimate zero = TaxEstimate(totalTax: 0);
}

/// cartTaxEstimateProvider 的参数包装
/// 支持可选的 [serviceFeePerItem]，按每张券分摊后与 unitPrice 一起计入税基
class CartTaxInput {
  final List<CartItemModel> items;
  final double serviceFeePerItem;

  const CartTaxInput({
    required this.items,
    this.serviceFeePerItem = 0,
  });

  @override
  bool operator ==(Object other) {
    if (other is! CartTaxInput) return false;
    if (other.items.length != items.length) return false;
    if (other.serviceFeePerItem != serviceFeePerItem) return false;
    for (var i = 0; i < items.length; i++) {
      // 按 dealId + unitPrice + city 近似判等，避免 List 引用相等问题
      if (other.items[i].dealId != items[i].dealId) return false;
      if (other.items[i].unitPrice != items[i].unitPrice) return false;
      if (other.items[i].merchantCity != items[i].merchantCity) return false;
      if (other.items[i].merchantMetroArea != items[i].merchantMetroArea) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var h = serviceFeePerItem.hashCode;
    for (final it in items) {
      h = Object.hash(h, it.dealId, it.unitPrice, it.merchantCity, it.merchantMetroArea);
    }
    return h;
  }
}

/// 根据购物车 items 本地计算税费（不调 Edge Function）
/// 查税逻辑：item.merchantCity → city_metro_map → metro_tax_rates → rate
/// merchant.metro_area 不再直接用，city 是真正的 source of truth
/// 每张券的税基 = unitPrice + serviceFeePerItem（service fee 也要交税）
final cartTaxEstimateProvider =
    FutureProvider.family<TaxEstimate, CartTaxInput>((ref, input) async {
  if (input.items.isEmpty) return TaxEstimate.zero;

  final cityRates = await ref.watch(cityTaxRatesProvider.future);

  double total = 0;
  final breakdown = <String, double>{};
  var hasUnknown = false;

  for (final item in input.items) {
    // 优先用 merchantCity 查；没有则回落到 merchantMetroArea（向后兼容旧 cart item）
    final city = item.merchantCity?.trim();
    double? rate;
    String bucketKey = '';
    if (city != null && city.isNotEmpty) {
      rate = cityRates[city.toLowerCase()];
      bucketKey = city;
    }
    if (rate == null) {
      final metro = item.merchantMetroArea?.trim();
      if (metro != null && metro.isNotEmpty) {
        // fallback：metro 自身也当作一个 city key 查一遍
        rate = cityRates[metro.toLowerCase()];
        bucketKey = metro;
      }
    }
    if (rate == null) {
      hasUnknown = true;
      continue;
    }
    if (rate == 0) continue;
    // 每张券的可税金额 = 券价 + 分摊的 service fee
    final taxableAmount = item.unitPrice + input.serviceFeePerItem;
    final itemTax = (taxableAmount * rate * 100).round() / 100;
    total += itemTax;
    breakdown[bucketKey] = (breakdown[bucketKey] ?? 0) + itemTax;
  }

  return TaxEstimate(
    totalTax: (total * 100).round() / 100,
    breakdown: breakdown,
    hasUnknownRate: hasUnknown,
  );
});

/// 单个 deal 的税费预估（Buy Now 路径）
/// 入参: [metroArea] = 购买商家的 metro 区域；[unitPrice] = 单价；[quantity] = 购买张数
class SingleDealTaxInput {
  final String? metroArea;
  final double unitPrice;
  final int quantity;

  const SingleDealTaxInput({
    required this.metroArea,
    required this.unitPrice,
    this.quantity = 1,
  });

  @override
  bool operator ==(Object other) =>
      other is SingleDealTaxInput &&
      other.metroArea == metroArea &&
      other.unitPrice == unitPrice &&
      other.quantity == quantity;

  @override
  int get hashCode => Object.hash(metroArea, unitPrice, quantity);
}

final singleDealTaxEstimateProvider =
    FutureProvider.family<TaxEstimate, SingleDealTaxInput>((ref, input) async {
  final metro = input.metroArea;
  if (metro == null || metro.isEmpty) {
    return const TaxEstimate(totalTax: 0, hasUnknownRate: true);
  }
  final rateMap = await ref.watch(metroTaxRatesProvider.future);
  final rate = rateMap[metro];
  if (rate == null || rate == 0) return TaxEstimate.zero;

  final itemTax = (input.unitPrice * rate * 100).round() / 100;
  final total = (itemTax * input.quantity * 100).round() / 100;
  return TaxEstimate(
    totalTax: total,
    breakdown: {metro: total},
  );
});
