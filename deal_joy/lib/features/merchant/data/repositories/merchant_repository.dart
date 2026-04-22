import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
import '../models/brand_detail_model.dart';
import '../models/merchant_model.dart';

class MerchantRepository {
  final SupabaseClient _client;

  MerchantRepository(this._client);

  /// 获取商家列表（按城市 + 分类筛选，含 deals 聚合数据）
  /// 分类匹配逻辑：deals.category 直接匹配 OR merchant_categories 关联匹配
  Future<List<MerchantModel>> fetchMerchants({String? city, String? category}) async {
    try {
      final hasCategory = category != null && category.isNotEmpty && category != 'All';

      // Step 1：如果有分类筛选，先获取 merchant_categories 里该分类对应的商家 ID
      Set<String> catMerchantIds = {};
      if (hasCategory) {
        final catRows = await _client
            .from('merchant_categories')
            .select('merchant_id, categories!inner(name)')
            .eq('categories.name', category!);
        catMerchantIds = (catRows as List)
            .map((e) => e['merchant_id'] as String?)
            .whereType<String>()
            .toSet();
      }

      // Step 2：查询商家（不再用 deals!inner 做分类过滤，改在应用层过滤）
      var query = _client
          .from('merchants')
          .select('*, deals(rating, review_count, discount_price, is_active, category)')
          .eq('status', 'approved');

      if (city != null && city.isNotEmpty) {
        query = query.ilike('city', '%$city%');
      }

      // 分类过滤：merchant_categories 匹配的商家 OR deals.category 匹配
      if (hasCategory && catMerchantIds.isNotEmpty) {
        // 优先用 id.in 范围，保证包含 merchant_categories 关联的商家
        query = query.inFilter('id', catMerchantIds.toList());
      } else if (hasCategory) {
        // 无 merchant_categories 数据时，回退到 deals.category 过滤
        query = query.eq('deals.category', category!);
      }

      final data = await query.order('name').limit(30);
      var results = (data as List).map((e) => MerchantModel.fromJson(e)).toList();

      // 应用层补充：如果有分类，过滤掉没有任何 active deal 的商家
      // （纯靠 merchant_categories 不能保证有 active deal）
      if (hasCategory) {
        results = results.where((m) {
          // activeDealCount > 0 说明 fromJson 时计算出了有效 deal
          return (m.activeDealCount ?? 0) > 0 || catMerchantIds.contains(m.id);
        }).toList();
      }

      return results;
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to fetch merchants: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 获取 GPS 附近的商家列表（通过 RPC，基于 deal_applicable_stores 搜索，和 deals 搜索逻辑一致）
  Future<List<MerchantModel>> fetchMerchantsNearby({
    required double lat,
    required double lng,
    String? category,
  }) async {
    try {
      final data = await _client.rpc('search_merchants_nearby', params: {
        'p_lat': lat,
        'p_lng': lng,
        'p_radius_m': 32187, // ~20 英里
        'p_category': (category == null || category == 'All') ? null : category,
        'p_limit': 30,
        'p_offset': 0,
      });
      final results = (data as List).map((e) {
        final json = e as Map<String, dynamic>;
        return MerchantModel(
          id: json['id'] as String,
          name: json['name'] as String? ?? '',
          description: json['description'] as String?,
          logoUrl: json['logo_url'] as String?,
          homepageCoverUrl: json['homepage_cover_url'] as String?,
          address: json['address'] as String?,
          phone: json['phone'] as String?,
          lat: (json['lat'] as num?)?.toDouble(),
          lng: (json['lng'] as num?)?.toDouble(),
          avgRating: (json['avg_rating'] as num?)?.toDouble(),
          totalReviewCount: (json['total_review_count'] as num?)?.toInt(),
          activeDealCount: (json['active_deal_count'] as num?)?.toInt(),
          bestDiscount: (json['best_discount'] as num?)?.toDouble(),
          distanceMiles: (json['distance_meters'] as num?) != null
              ? (json['distance_meters'] as num).toDouble() / 1609.34
              : null,
        );
      }).toList();

      // 批量查各商家的主分类（取第一个 active deal 的 category）
      if (results.isNotEmpty) {
        final ids = results.map((m) => m.id).toList();
        final catData = await _client
            .from('deals')
            .select('merchant_id, category')
            .eq('is_active', true)
            .inFilter('merchant_id', ids)
            .limit(ids.length * 5);
        final catMap = <String, String>{};
        for (final row in catData as List) {
          final mid = row['merchant_id'] as String;
          if (!catMap.containsKey(mid)) {
            catMap[mid] = row['category'] as String? ?? '';
          }
        }
        return results
            .map((m) => m.copyWith(primaryCategory: catMap[m.id]))
            .toList();
      }
      return results;
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to fetch nearby merchants: ${e.message}',
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

  // ----------------------------------------------------------
  // V2.4 品牌聚合查询
  // ----------------------------------------------------------

  /// 获取品牌详情（含旗下所有门店 + deals 聚合数据）
  Future<BrandDetailModel> fetchBrandDetail(String brandId) async {
    try {
      final data = await _client
          .from('brands')
          .select(
            '*, merchants(id, name, address, city, phone, logo_url, homepage_cover_url, lat, lng, '
            'deals(rating, review_count, discount_price, is_active))',
          )
          .eq('id', brandId)
          .eq('merchants.status', 'approved')
          .single();
      return BrandDetailModel.fromJson(data);
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to load brand: ${e.message}',
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

      // 2. 搜 deals 的标题/描述，找到对应的 merchant_id
      final dealData = await _client
          .from('deals')
          .select('merchant_id')
          .eq('is_active', true)
          .or('title.ilike.$pattern,description.ilike.$pattern');

      final extraIds = (dealData as List)
          .map((e) => e['merchant_id'] as String)
          .toSet()
          .difference(foundIds);

      // 3. 搜 menu_items 的菜品名，找到对应的 merchant_id
      final menuData = await _client
          .from('menu_items')
          .select('merchant_id')
          .ilike('name', pattern)
          .eq('status', 'active')
          .not('price', 'is', null)
          .limit(30);

      final menuMerchantIds = (menuData as List)
          .map((e) => e['merchant_id'] as String)
          .toSet()
          .difference(foundIds)
          .difference(extraIds);
      extraIds.addAll(menuMerchantIds);

      // 4. 拉取额外的商家信息
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

  /// 获取相似/推荐商家（搜索无结果时展示）
  /// 逻辑：返回有 active deal 的热门商家，按评分排序
  Future<List<MerchantModel>> fetchSimilarMerchants({String? city}) async {
    try {
      var query = _client
          .from('merchants')
          .select('*, deals(rating, review_count, discount_price, is_active)')
          .eq('status', 'approved');

      if (city != null && city.isNotEmpty) {
        query = query.ilike('city', '%$city%');
      }

      final data = await query.order('name').limit(10);
      final merchants = (data as List)
          .map((e) => MerchantModel.fromJson(e))
          .where((m) => (m.activeDealCount ?? 0) > 0)
          .toList();
      // 按评分降序
      merchants.sort((a, b) =>
          (b.avgRating ?? 0).compareTo(a.avgRating ?? 0));
      return merchants;
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to fetch similar merchants: ${e.message}',
        code: e.code,
      );
    }
  }
}
