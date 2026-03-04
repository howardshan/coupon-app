import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
import '../models/merchant_model.dart';

class MerchantRepository {
  final SupabaseClient _client;

  MerchantRepository(this._client);

  /// 获取商家列表（按城市筛选，含 deals 聚合数据）
  Future<List<MerchantModel>> fetchMerchants({String? city}) async {
    try {
      var query = _client
          .from('merchants')
          .select('*, deals(rating, review_count, discount_price, is_active)')
          .eq('status', 'approved');

      if (city != null && city.isNotEmpty) {
        query = query.ilike('address', '%$city%');
      }

      final data = await query.order('name').limit(30);
      return (data as List).map((e) => MerchantModel.fromJson(e)).toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to fetch merchants: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 获取用户已收藏的商家 ID 集合（用于快速判断是否已收藏）
  Future<Set<String>> fetchSavedMerchantIds(String userId) async {
    try {
      final data = await _client
          .from('saved_merchants')
          .select('merchant_id')
          .eq('user_id', userId);
      return (data as List).map((e) => e['merchant_id'] as String).toSet();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to load saved store ids: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 收藏商家
  Future<void> saveMerchant(String userId, String merchantId) async {
    try {
      await _client.from('saved_merchants').upsert({
        'user_id': userId,
        'merchant_id': merchantId,
      });
    } on PostgrestException catch (e) {
      throw AppException('Failed to save store: ${e.message}', code: e.code);
    }
  }

  /// 取消收藏商家
  Future<void> unsaveMerchant(String userId, String merchantId) async {
    try {
      await _client
          .from('saved_merchants')
          .delete()
          .eq('user_id', userId)
          .eq('merchant_id', merchantId);
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to unsave store: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 获取用户已收藏的商家列表
  Future<List<MerchantModel>> fetchSavedMerchants(String userId) async {
    try {
      final data = await _client
          .from('saved_merchants')
          .select(
            'merchants(*, deals(rating, review_count, discount_price, is_active))',
          )
          .eq('user_id', userId);
      return (data as List)
          .map(
            (e) => MerchantModel.fromJson(
              e['merchants'] as Map<String, dynamic>,
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to load saved stores: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 按 ID 列表批量获取 merchant（保持原顺序）
  Future<List<MerchantModel>> fetchMerchantsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      final data = await _client
          .from('merchants')
          .select(
            '*, deals(rating, review_count, discount_price, is_active)',
          )
          .inFilter('id', ids);
      final map = <String, MerchantModel>{};
      for (final raw in data as List) {
        final d = raw as Map<String, dynamic>;
        map[d['id'] as String] = MerchantModel.fromJson(d);
      }
      return ids.map((id) => map[id]).whereType<MerchantModel>().toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to load stores: ${e.message}',
        code: e.code,
      );
    }
  }

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

      final merchants = (merchantData as List)
          .map((e) => MerchantModel.fromJson(e))
          .toList();
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
        merchants.addAll(
          (extraData as List).map((e) => MerchantModel.fromJson(e)),
        );
      }

      return merchants;
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to search merchants: ${e.message}',
        code: e.code,
      );
    }
  }
}
