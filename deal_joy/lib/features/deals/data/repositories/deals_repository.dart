import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../models/deal_model.dart';
import '../models/review_model.dart';

class DealsRepository {
  final SupabaseClient _client;

  DealsRepository(this._client);

  Future<List<DealModel>> fetchDeals({
    String? city,
    String? category,
    String? search,
    int page = 0,
  }) async {
    try {
      var query = _client
          .from('deals')
          .select('*, merchants(id, name, logo_url, phone)')
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toIso8601String());

      if (city != null && city.isNotEmpty) {
        query = query.ilike('address', '%$city%');
      }

      if (category != null && category != 'All') {
        query = query.eq('category', category);
      }

      if (search != null && search.isNotEmpty) {
        final pattern = '%$search%';
        query = query.or(
          'title.ilike.$pattern,'
          'description.ilike.$pattern,'
          'category.ilike.$pattern,'
          'address.ilike.$pattern',
        );
      }

      final data = await query
          .order('is_featured', ascending: false)
          .order('created_at', ascending: false)
          .range(
            page * AppConstants.pageSize,
            (page + 1) * AppConstants.pageSize - 1,
          );

      return (data as List).map((e) => DealModel.fromJson(e)).toList();
    } on PostgrestException catch (e) {
      throw AppException('Failed to load deals: ${e.message}', code: e.code);
    }
  }

  Future<List<DealModel>> fetchFeaturedDeals({String? city}) async {
    try {
      var query = _client
          .from('deals')
          .select('*, merchants(id, name, logo_url, phone)')
          .eq('is_active', true)
          .eq('is_featured', true)
          .gt('expires_at', DateTime.now().toIso8601String());

      if (city != null && city.isNotEmpty) {
        query = query.ilike('address', '%$city%');
      }

      final data = await query
          .order('created_at', ascending: false)
          .limit(10);
      return (data as List).map((e) => DealModel.fromJson(e)).toList();
    } on PostgrestException catch (e) {
      throw AppException('Failed to load featured deals: ${e.message}',
          code: e.code);
    }
  }

  Future<DealModel> fetchDealById(String dealId) async {
    try {
      final data = await _client
          .from('deals')
          .select('*, merchants(id, name, logo_url, phone)')
          .eq('id', dealId)
          .single();
      return DealModel.fromJson(data);
    } on PostgrestException catch (e) {
      throw AppException('Deal not found: ${e.message}', code: e.code);
    }
  }

  Future<void> saveDeal(String userId, String dealId) async {
    try {
      await _client.from('saved_deals').upsert({
        'user_id': userId,
        'deal_id': dealId,
      });
    } on PostgrestException catch (e) {
      throw AppException('Failed to save deal: ${e.message}', code: e.code);
    }
  }

  Future<void> unsaveDeal(String userId, String dealId) async {
    try {
      await _client
          .from('saved_deals')
          .delete()
          .eq('user_id', userId)
          .eq('deal_id', dealId);
    } on PostgrestException catch (e) {
      throw AppException('Failed to unsave deal: ${e.message}', code: e.code);
    }
  }

  Future<List<DealModel>> fetchDealsByMerchant(
    String merchantId, {
    String? excludeDealId,
  }) async {
    try {
      var query = _client
          .from('deals')
          .select('*, merchants(id, name, logo_url, phone)')
          .eq('merchant_id', merchantId)
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toIso8601String());

      if (excludeDealId != null) {
        query = query.neq('id', excludeDealId);
      }

      final data =
          await query.order('total_sold', ascending: false).limit(5);
      return (data as List).map((e) => DealModel.fromJson(e)).toList();
    } on PostgrestException catch (e) {
      throw AppException('Failed to load merchant deals: ${e.message}',
          code: e.code);
    }
  }

  Future<List<ReviewModel>> fetchReviewsByDeal(String dealId) async {
    try {
      final data = await _client
          .from('reviews')
          .select('*, users(full_name, avatar_url)')
          .eq('deal_id', dealId)
          .order('created_at', ascending: false)
          .limit(20);
      return (data as List).map((e) => ReviewModel.fromJson(e)).toList();
    } on PostgrestException catch (e) {
      throw AppException('Failed to load reviews: ${e.message}',
          code: e.code);
    }
  }

  /// 按 ID 列表批量获取 deal（保持原顺序）
  Future<List<DealModel>> fetchDealsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      final data = await _client
          .from('deals')
          .select('*, merchants(id, name, logo_url, phone)')
          .inFilter('id', ids);
      final map = {
        for (final d in data as List)
          (d as Map<String, dynamic>)['id'] as String: DealModel.fromJson(d),
      };
      return ids.map((id) => map[id]).whereType<DealModel>().toList();
    } on PostgrestException catch (e) {
      throw AppException('Failed to load deals: ${e.message}', code: e.code);
    }
  }

  Future<List<DealModel>> fetchSavedDeals(String userId) async {
    try {
      final data = await _client
          .from('saved_deals')
          .select('deals(*, merchants(id, name, logo_url, phone))')
          .eq('user_id', userId);
      return (data as List)
          .map(
              (e) => DealModel.fromJson(e['deals'] as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw AppException('Failed to load saved deals: ${e.message}',
          code: e.code);
    }
  }

  // Near Me 模式：按 GPS 坐标 + 半径搜索
  Future<List<DealModel>> searchDealsNearby({
    required double lat,
    required double lng,
    double radiusMeters = 24140,
    String? category,
    int page = 0,
  }) async {
    try {
      final data = await _client.rpc('search_deals_nearby', params: {
        'p_lat': lat,
        'p_lng': lng,
        'p_radius_m': radiusMeters,
        'p_category': (category == null || category == 'All') ? null : category,
        'p_limit': AppConstants.pageSize,
        'p_offset': page * AppConstants.pageSize,
      });
      return (data as List)
          .map((e) => DealModel.fromSearchJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw AppException('Failed to search nearby deals: ${e.message}',
          code: e.code);
    }
  }

  // 城市模式：按 merchants.city 精确匹配
  Future<List<DealModel>> searchDealsByCity({
    required String city,
    double? userLat,
    double? userLng,
    String? category,
    int page = 0,
  }) async {
    try {
      final data = await _client.rpc('search_deals_by_city', params: {
        'p_city': city,
        'p_user_lat': userLat,
        'p_user_lng': userLng,
        'p_category': (category == null || category == 'All') ? null : category,
        'p_limit': AppConstants.pageSize,
        'p_offset': page * AppConstants.pageSize,
      });
      return (data as List)
          .map((e) => DealModel.fromSearchJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw AppException('Failed to search deals by city: ${e.message}',
          code: e.code);
    }
  }
}
