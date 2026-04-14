// 独立文件避免 coupons_provider 与 coupon_tab_list_provider 循环引用

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/supabase_provider.dart';
import '../../data/repositories/coupons_repository.dart';

final couponsRepositoryProvider = Provider<CouponsRepository>((ref) {
  return CouponsRepository(ref.watch(supabaseClientProvider));
});
