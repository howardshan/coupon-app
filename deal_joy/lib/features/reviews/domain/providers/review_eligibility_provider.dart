// 评价资格校验 Provider
// 用于判断当前登录用户是否可以对指定 deal 写评价：
// 必须持有该 deal 的 status='used'（已核销）coupon

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';

/// 当前用户是否可以对某个 deal 写评价
/// true = 有已核销 coupon；false = 未登录 / 未购买 / 未核销
///
/// autoDispose：用户核销后回到 deal 详情页会自动 refetch，及时解锁按钮
final canReviewDealProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, dealId) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return false;

  // 查是否存在 status='used' 的 coupon（limit 1 节省带宽）
  final row = await client
      .from('coupons')
      .select('id')
      .eq('user_id', user.id)
      .eq('deal_id', dealId)
      .eq('status', 'used')
      .limit(1)
      .maybeSingle();

  return row != null;
});
