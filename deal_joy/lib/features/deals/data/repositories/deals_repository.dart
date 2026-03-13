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
          .select('*, merchants(id, name, logo_url, phone, homepage_cover_url, brand_id, brands(name, logo_url))')
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

      var results = (data as List).map((e) => DealModel.fromJson(e)).toList();

      // 过滤 brand_multi_store deal：必须至少有一个 active 门店才展示
      results = await _filterBrandDealsWithActiveStores(results);

      // 搜索品牌名/商家名：补充匹配品牌名或商家名的 deals
      if (search != null && search.isNotEmpty && page == 0) {
        try {
          // 查询商家名或品牌名匹配的商家 ID
          final merchantData = await _client
              .from('merchants')
              .select('id, brand_id, brands(name)')
              .or('name.ilike.%$search%')
              .eq('status', 'approved')
              .limit(20);

          // 也查品牌名匹配的商家
          final brandData = await _client
              .from('brands')
              .select('id, name')
              .ilike('name', '%$search%')
              .limit(10);
          final brandIds = (brandData as List).map((b) => b['id'] as String).toSet();

          // 商家名匹配 + 品牌名匹配的门店
          final merchantIds = <String>{};
          for (final m in (merchantData as List)) {
            merchantIds.add(m['id'] as String);
          }
          if (brandIds.isNotEmpty) {
            final brandMerchants = await _client
                .from('merchants')
                .select('id')
                .inFilter('brand_id', brandIds.toList())
                .limit(20);
            for (final m in (brandMerchants as List)) {
              merchantIds.add(m['id'] as String);
            }
          }

          if (merchantIds.isNotEmpty) {
            final existingIds = results.map((d) => d.id).toSet();
            final extraData = await _client
                .from('deals')
                .select('*, merchants(id, name, logo_url, phone, homepage_cover_url, brand_id, brands(name, logo_url))')
                .eq('is_active', true)
                .gt('expires_at', DateTime.now().toIso8601String())
                .inFilter('merchant_id', merchantIds.toList())
                .order('is_featured', ascending: false)
                .limit(AppConstants.pageSize);
            for (final e in (extraData as List)) {
              final deal = DealModel.fromJson(e);
              if (!existingIds.contains(deal.id)) {
                results.add(deal);
              }
            }
          }
        } catch (_) {
          // 品牌搜索失败不影响主结果
        }

        // 额外添加的 deal 也需要过滤 brand deal
        results = await _filterBrandDealsWithActiveStores(results);
      }

      return results;
    } on PostgrestException catch (e) {
      throw AppException('Failed to load deals: ${e.message}', code: e.code);
    }
  }

  // 获取首页展示券：sort_order 不为空的 active deal，按 sort_order 升序
  Future<List<DealModel>> fetchFeaturedDeals() async {
    try {
      final data = await _client
          .from('deals')
          .select('*, merchants(id, name, logo_url, phone, homepage_cover_url, brand_id, brands(name, logo_url))')
          .eq('is_active', true)
          .not('sort_order', 'is', null)
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('sort_order', ascending: true)
          .limit(20);
      final results = (data as List).map((e) => DealModel.fromJson(e)).toList();
      return _filterBrandDealsWithActiveStores(results);
    } on PostgrestException catch (e) {
      throw AppException('Failed to load featured deals: ${e.message}',
          code: e.code);
    }
  }

  /// 过滤 brand_multi_store deal：只保留在 deal_applicable_stores 中
  /// 至少有一条 status='active' 记录的 deal。store_only deal 不受影响。
  Future<List<DealModel>> _filterBrandDealsWithActiveStores(
      List<DealModel> deals) async {
    // 筛出 brand deal（applicableMerchantIds 非空）
    final brandDealIds = deals
        .where((d) =>
            d.applicableMerchantIds != null &&
            d.applicableMerchantIds!.isNotEmpty)
        .map((d) => d.id)
        .toList();

    if (brandDealIds.isEmpty) return deals;

    // 批量查询这些 brand deal 中有 active 门店的 deal_id
    final activeRows = await _client
        .from('deal_applicable_stores')
        .select('deal_id')
        .inFilter('deal_id', brandDealIds)
        .eq('status', 'active');

    final activeDealIds =
        (activeRows as List).map((r) => r['deal_id'] as String).toSet();

    // 保留 store_only deal + 有 active 门店的 brand deal
    return deals.where((d) {
      if (d.applicableMerchantIds == null ||
          d.applicableMerchantIds!.isEmpty) {
        return true; // store_only deal，不过滤
      }
      return activeDealIds.contains(d.id);
    }).toList();
  }

  Future<DealModel> fetchDealById(String dealId) async {
    try {
      final data = await _client
          .from('deals')
          .select('*, merchants(id, name, logo_url, phone, homepage_cover_url, brand_id, brands(name, logo_url))')
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
          .select('*, merchants(id, name, logo_url, phone, homepage_cover_url, brand_id, brands(name, logo_url))')
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
          .select('*, merchants(id, name, logo_url, phone, homepage_cover_url, brand_id, brands(name, logo_url))')
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
          .select('deals(*, merchants(id, name, logo_url, phone, homepage_cover_url, brand_id, brands(name, logo_url)))')
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
