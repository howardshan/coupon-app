import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
import '../models/merchant_model.dart';

class MerchantRepository {
  final SupabaseClient _client;

  MerchantRepository(this._client);

  /// 搜索商家：直接匹配商家名/描述/地址 + 通过 deal 标题/描述匹配菜名
  Future<List<MerchantModel>> searchMerchants(String query) async {
    try {
      final pattern = '%$query%';

      // 1. 直接搜商家
      final merchantData = await _client
          .from('merchants')
          .select()
          .eq('status', 'approved')
          .or(
            'name.ilike.$pattern,'
            'description.ilike.$pattern,'
            'address.ilike.$pattern',
          )
          .order('name')
          .limit(20);

      final merchants =
          (merchantData as List).map((e) => MerchantModel.fromJson(e)).toList();
      final foundIds = merchants.map((m) => m.id).toSet();

      // 2. 搜 deals 的标题/描述（覆盖菜名场景），找到对应的 merchant_id
      final dealData = await _client
          .from('deals')
          .select('merchant_id')
          .eq('is_active', true)
          .or('title.ilike.$pattern,description.ilike.$pattern');

      final extraIds = (dealData as List)
          .map((e) => e['merchant_id'] as String)
          .toSet()
          .difference(foundIds);

      // 3. 拉取额外的商家信息
      if (extraIds.isNotEmpty) {
        final extraData = await _client
            .from('merchants')
            .select()
            .eq('status', 'approved')
            .inFilter('id', extraIds.toList());
        merchants
            .addAll((extraData as List).map((e) => MerchantModel.fromJson(e)));
      }

      return merchants;
    } on PostgrestException catch (e) {
      throw AppException('Failed to search merchants: ${e.message}',
          code: e.code);
    }
  }
}
