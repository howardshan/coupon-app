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

/// 根据购物车 items 本地计算税费（不调 Edge Function）
/// items 由 CartItemModel 提供，每项已 join 到 merchant.metro_area
final cartTaxEstimateProvider =
    FutureProvider.family<TaxEstimate, List<CartItemModel>>((ref, items) async {
  if (items.isEmpty) return TaxEstimate.zero;

  final rateMap = await ref.watch(metroTaxRatesProvider.future);

  double total = 0;
  final breakdown = <String, double>{};
  var hasUnknown = false;

  for (final item in items) {
    final metro = item.merchantMetroArea;
    if (metro == null || metro.isEmpty) {
      hasUnknown = true;
      continue;
    }
    final rate = rateMap[metro];
    if (rate == null || rate == 0) {
      // 税率为 0 的城市也视为已知（不触发 unknown 标记）
      continue;
    }
    final itemTax = (item.unitPrice * rate * 100).round() / 100;
    total += itemTax;
    breakdown[metro] = (breakdown[metro] ?? 0) + itemTax;
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
