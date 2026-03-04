import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../deals/data/models/deal_model.dart';
import '../../../deals/data/models/review_model.dart';
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
          .select('*, merchant_photos(*), merchant_hours(*)')
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

  /// 获取商家活跃 deals
  Future<List<DealModel>> fetchActiveDeals(String merchantId) async {
    try {
      final data = await _client
          .from('deals')
          .select('*, merchants(id, name, logo_url, phone)')
          .eq('merchant_id', merchantId)
          .eq('is_active', true)
          .order('is_featured', ascending: false)
          .order('total_sold', ascending: false);
      return (data as List)
          .map((d) => DealModel.fromJson(d as Map<String, dynamic>))
          .toList();
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
          .select('*, users(full_name, avatar_url), review_photos(image_url, sort_order)')
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
