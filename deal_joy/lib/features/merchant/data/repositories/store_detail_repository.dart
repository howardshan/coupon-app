import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../deals/data/models/deal_model.dart';
import '../../../deals/data/models/review_model.dart';
import '../models/deal_category_model.dart';
import '../models/merchant_detail_model.dart';
import '../models/menu_item_model.dart';
import '../models/review_stats_model.dart';
import '../models/store_facility_model.dart';

/// 用户端商家详情页专用 Repository
class StoreDetailRepository {
  final SupabaseClient _client;

  StoreDetailRepository(this._client);

  /// 获取商家详情（含照片+营业时间，一次查询）
  Future<MerchantDetailModel> fetchMerchantDetail(String merchantId) async {
    try {
      final data = await _client
          .from('merchants')
          .select('*, merchant_photos(*), merchant_hours(*), brands(id, name, logo_url)')
          .eq('id', merchantId)
          .single();
      return MerchantDetailModel.fromJson(data);
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to load store details: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 获取商家 Deal 分类列表
  Future<List<DealCategoryModel>> fetchDealCategories(
      String merchantId) async {
    try {
      final data = await _client
          .from('deal_categories')
          .select()
          .eq('merchant_id', merchantId)
          .order('sort_order');
      return (data as List)
          .map((d) => DealCategoryModel.fromJson(d as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to load deal categories: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 获取商家活跃 deals（仅未过期的）
  /// 同时包含：1) merchant_id = 当前门店的 deal  2) 通过 deal_applicable_stores 关联到当前门店的 brand deal
  Future<List<DealModel>> fetchActiveDeals(String merchantId) async {
    try {
      // 1. 查询 merchant_id = 当前门店的 deal
      final ownData = await _client
          .from('deals')
          .select('*, merchants(id, name, logo_url, phone, brand_id, brands(name, logo_url))')
          .eq('merchant_id', merchantId)
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toIso8601String())
          // sort_order 优先（null 排最后），再按 is_featured、total_sold 降序
          .order('sort_order', ascending: true, nullsFirst: false)
          .order('is_featured', ascending: false)
          .order('total_sold', ascending: false);
      final ownDeals = (ownData as List)
          .map((d) => DealModel.fromJson(d as Map<String, dynamic>))
          .toList();
      // 2. 查询通过 deal_applicable_stores 关联到当前门店的 brand deal（仅 active）
      final dasData = await _client
          .from('deal_applicable_stores')
          .select('deal_id, status')
          .eq('store_id', merchantId);
      final activeDealIds = <String>{};
      final declinedDealIds = <String>{};
      for (final r in (dasData as List)) {
        final dealId = r['deal_id'] as String;
        final status = r['status'] as String? ?? '';
        if (status == 'active') {
          activeDealIds.add(dealId);
        } else if (status == 'declined') {
          declinedDealIds.add(dealId);
        }
      }

      // 过滤掉门店已 declined 的 ownDeals（门店创建者但已 withdraw 的情况）
      ownDeals.removeWhere((d) => declinedDealIds.contains(d.id));
      final remainingOwnIds = ownDeals.map((d) => d.id).toSet();

      // 加载关联的 active brand deal（排除已在 ownDeals 中的）
      final linkedDealIds = activeDealIds
          .where((id) => !remainingOwnIds.contains(id))
          .toList();

      if (linkedDealIds.isNotEmpty) {
        final linkedData = await _client
            .from('deals')
            .select('*, merchants(id, name, logo_url, phone, brand_id, brands(name, logo_url))')
            .inFilter('id', linkedDealIds)
            .eq('is_active', true)
            .gt('expires_at', DateTime.now().toIso8601String());
        for (final d in (linkedData as List)) {
          ownDeals.add(DealModel.fromJson(d as Map<String, dynamic>));
        }
      }

      return ownDeals;
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to load store deals: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 获取菜品列表
  Future<List<MenuItemModel>> fetchMenuItems(String merchantId) async {
    try {
      final data = await _client
          .from('menu_items')
          .select()
          .eq('merchant_id', merchantId)
          .order('sort_order');
      return (data as List)
          .map((d) => MenuItemModel.fromJson(d as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to load menu items: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 获取设施信息
  Future<List<StoreFacilityModel>> fetchFacilities(String merchantId) async {
    try {
      final data = await _client
          .from('store_facilities')
          .select()
          .eq('merchant_id', merchantId)
          .order('sort_order');
      return (data as List)
          .map((d) => StoreFacilityModel.fromJson(d as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to load facilities: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 获取商家所有评价（分页，含 review_photos + 用户信息）
  Future<List<ReviewModel>> fetchMerchantReviews(
    String merchantId, {
    int page = 0,
    int pageSize = 10,
  }) async {
    try {
      // 先获取该商家的所有 deal IDs
      final dealData = await _client
          .from('deals')
          .select('id')
          .eq('merchant_id', merchantId);
      final dealIds =
          (dealData as List).map((d) => d['id'] as String).toList();
      if (dealIds.isEmpty) return [];

      final data = await _client
          .from('reviews')
          .select('*, users!reviews_user_id_fkey(full_name, avatar_url), review_photos(image_url, sort_order)')
          .inFilter('deal_id', dealIds)
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1);

      return (data as List)
          .map((d) => ReviewModel.fromJson(d as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to load reviews: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 获取评价统计（RPC 调用）
  Future<ReviewStatsModel> fetchReviewStats(String merchantId) async {
    try {
      final data = await _client.rpc(
        'get_merchant_review_summary',
        params: {'p_merchant_id': merchantId},
      );
      if (data == null) return ReviewStatsModel.empty;
      return ReviewStatsModel.fromJson(data as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to load review stats: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 获取同品牌其他门店
  Future<List<Map<String, dynamic>>> fetchSameBrandStores({
    required String brandId,
    required String excludeMerchantId,
  }) async {
    try {
      final data = await _client
          .from('merchants')
          .select('id, name, address, logo_url, lat, lng')
          .eq('brand_id', brandId)
          .neq('id', excludeMerchantId)
          .eq('status', 'approved')
          .order('name');
      return (data as List).cast<Map<String, dynamic>>();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to load brand stores: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 获取附近推荐商家（RPC 调用）
  Future<List<Map<String, dynamic>>> fetchNearbyMerchants({
    required double lat,
    required double lng,
    required String excludeId,
    int limit = 5,
  }) async {
    try {
      final data = await _client.rpc(
        'get_nearby_merchants',
        params: {
          'p_lat': lat,
          'p_lng': lng,
          'p_exclude_id': excludeId,
          'p_limit': limit,
        },
      );
      if (data == null) return [];
      return (data as List).cast<Map<String, dynamic>>();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to load nearby stores: ${e.message}',
        code: e.code,
      );
    }
  }
}
