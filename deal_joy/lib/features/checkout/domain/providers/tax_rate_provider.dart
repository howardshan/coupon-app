// 税率查询 Provider
// 根据 merchant 的 metro_area 查询 metro_tax_rates 表获取适用税率

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';

/// 根据 merchantId 查询适用税率（返回小数，如 0.0825）
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
