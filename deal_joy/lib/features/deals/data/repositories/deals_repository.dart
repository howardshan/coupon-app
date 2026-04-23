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
      // 用 merchants!inner 做 join 过滤（city 字段权威来源于 merchants.city，
      // 不再依赖 deals.address 文本匹配，避免 address 为空或格式不一致漏掉 deal）
      // 注意：lat/lng 也从 merchants 读取，用于客户端 Haversine 距离计算
      final merchantSelect = (city != null && city.isNotEmpty)
          ? 'merchants!inner(id, name, logo_url, phone, homepage_cover_url, brand_id, metro_area, brands(name, logo_url), city, lat, lng)'
          : 'merchants(id, name, logo_url, phone, homepage_cover_url, brand_id, city, metro_area, brands(name, logo_url), lat, lng)';

      var query = _client
          .from('deals')
          .select('*, $merchantSelect')
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toIso8601String());

      if (city != null && city.isNotEmpty) {
        query = query.eq('merchants.city', city);
      }

      // 分类筛选：优先用 deals.category 直接匹配（每个 deal 自带 category 字段），
      // 退回到 merchant_categories 关联表查询，取并集。
      // 之前仅靠 merchant_categories 的老逻辑会遗漏未被维护进该表的商家。
      if (category != null && category != 'All') {
        final catData = await _client
            .from('merchant_categories')
            .select('merchant_id, categories!inner(name)')
            .eq('categories.name', category);
        final merchantIds = (catData as List)
            .map((e) => e['merchant_id'] as String)
            .toSet()
            .toList();
        if (merchantIds.isEmpty) {
          // 没有关联的商家时，只按 deals.category 过滤
          query = query.ilike('category', category);
        } else {
          // OR：要么 deal 自身 category 匹配，要么 merchant 在该分类下
          final idsCsv = merchantIds.map((id) => '"$id"').join(',');
          query = query.or(
            'category.ilike.$category,merchant_id.in.($idsCsv)',
          );
        }
      }

      if (search != null && search.isNotEmpty) {
        // PostgREST 用 * 作为 ILIKE 通配符（避免 % 被 URL 编码为 %25 导致匹配失败）
        final pattern = '*$search*';
        query = query.or(
          'title.ilike.$pattern,'
          'description.ilike.$pattern,'
          'short_name.ilike.$pattern,'
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

      // 搜索品牌名/商家名/菜品名：补充匹配的 deals
      if (search != null && search.isNotEmpty && page == 0) {
        try {
          // 查询商家名或品牌名匹配的商家 ID
          final merchantData = await _client
              .from('merchants')
              .select('id, brand_id, brands(name)')
              .or('name.ilike.*$search*')
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

          // 通过 menu_items 菜品名匹配商家
          final menuData = await _client
              .from('menu_items')
              .select('merchant_id')
              .ilike('name', '%$search%')
              .eq('status', 'active')
              .not('price', 'is', null)
              .limit(30);
          for (final m in (menuData as List)) {
            merchantIds.add(m['merchant_id'] as String);
          }

          if (merchantIds.isNotEmpty) {
            final existingIds = results.map((d) => d.id).toSet();
            final extraData = await _client
                .from('deals')
                .select('*, merchants(id, name, logo_url, phone, homepage_cover_url, brand_id, city, metro_area, brands(name, logo_url), lat, lng)')
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
          // 品牌/菜品搜索失败不影响主结果
        }

        // 额外添加的 deal 也需要过滤 brand deal
        results = await _filterBrandDealsWithActiveStores(results);
      }

      return results;
    } on PostgrestException catch (e) {
      throw AppException('Failed to load deals: ${e.message}', code: e.code);
    }
  }

  /// 获取广告竞价赢家（home_deal_top placement），用于 Hot Deal 区顶部插入
  /// 返回已标记 isSponsored=true 的 DealModel 列表（最多 3 条）
  Future<List<DealModel>> fetchSponsoredDeals() async {
    try {
      final data = await _client.rpc('get_active_ads', params: {
        'p_placement': 'home_deal_top',
        'p_limit': 20,
      });
      final rows = data as List<dynamic>;
      final entries = rows
          .where((r) => (r as Map<String, dynamic>)['target_type'] == 'deal')
          .toList();
      if (entries.isEmpty) return [];

      final ids = entries
          .map((r) => (r as Map<String, dynamic>)['target_id'] as String)
          .toList();
      final campaignMap = {
        for (final r in entries)
          (r as Map<String, dynamic>)['target_id'] as String:
              r['campaign_id'] as String?,
      };

      // 仅上架中的 deal 可作赞助展示（DealModel 无 is_active 字段，在查询层过滤）
      final deals = await fetchDealsByIds(ids, activeOnly: true);
      final now = DateTime.now().toUtc();
      return deals
          .where((d) => !d.expiresAt.isBefore(now))
          .map((d) => d.copyWithSponsored(
                isSponsored: true,
                campaignId: campaignMap[d.id],
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // 获取首页展示券：sort_order 不为空的 active deal，按 sort_order 升序
  Future<List<DealModel>> fetchFeaturedDeals({String? city, String? category}) async {
    try {
      // 有城市过滤时用 !inner join，确保只返回 merchant.city 匹配的 deal
      final merchantSelect = (city != null && city.isNotEmpty)
          ? 'merchants!inner(id, name, logo_url, phone, homepage_cover_url, brand_id, metro_area, brands(name, logo_url), city)'
          : 'merchants(id, name, logo_url, phone, homepage_cover_url, brand_id, city, metro_area, brands(name, logo_url))';
      var query = _client
          .from('deals')
          .select('*, $merchantSelect')
          .eq('is_active', true)
          .not('sort_order', 'is', null)
          .gt('expires_at', DateTime.now().toIso8601String());
      // 通过 merchant 的 city 字段过滤
      if (city != null && city.isNotEmpty) {
        query = query.eq('merchants.city', city);
      }
      // 分类筛选
      if (category != null && category.isNotEmpty && category != 'All') {
        query = query.eq('category', category);
      }
      final data = await query
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
          .select('*, merchants(id, name, logo_url, phone, homepage_cover_url, brand_id, city, metro_area, brands(name, logo_url)), deal_option_groups(*, deal_option_items(*))')
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
          .select('*, merchants(id, name, logo_url, phone, homepage_cover_url, brand_id, city, metro_area, brands(name, logo_url))')
          .eq('merchant_id', merchantId)
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toIso8601String());

      if (excludeDealId != null && excludeDealId.isNotEmpty) {
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

  /// 获取 deal 的评价
  /// 同一产品（同 merchant + 同 title）可能有多个 deal 记录（新旧上下架），
  /// 为了避免旧 deal 的评价在新 deal 下丢失，按 merchant_id + title 聚合所有同名 deal 的评价
  Future<List<ReviewModel>> fetchReviewsByDeal(String dealId) async {
    try {
      // 先查当前 deal 的 merchant_id 和 title
      final dealData = await _client
          .from('deals')
          .select('merchant_id, title')
          .eq('id', dealId)
          .maybeSingle();

      if (dealData == null) return [];

      final merchantId = dealData['merchant_id'] as String?;
      final title = dealData['title'] as String?;

      // 找同 merchant + 同 title 的所有 deal IDs（包括旧版已下架的）
      List<String> allDealIds = [dealId];
      if (merchantId != null && title != null) {
        final siblingDeals = await _client
            .from('deals')
            .select('id')
            .eq('merchant_id', merchantId)
            .eq('title', title);
        allDealIds = (siblingDeals as List)
            .map((d) => d['id'] as String)
            .toSet()
            .toList();
      }

      final data = await _client
          .from('reviews')
          .select('*, users!reviews_user_id_fkey(full_name, avatar_url)')
          .inFilter('deal_id', allDealIds)
          .order('created_at', ascending: false)
          .limit(20);
      return (data as List).map((e) => ReviewModel.fromJson(e)).toList();
    } on PostgrestException catch (e) {
      throw AppException('Failed to load reviews: ${e.message}',
          code: e.code);
    }
  }

  /// 按 ID 列表批量获取 deal（保持原顺序）
  /// [activeOnly] 为 true 时仅返回 `is_active = true` 的行（赞助位等场景）
  Future<List<DealModel>> fetchDealsByIds(
    List<String> ids, {
    bool activeOnly = false,
  }) async {
    if (ids.isEmpty) return [];
    try {
      var query = _client
          .from('deals')
          .select(
            '*, merchants(id, name, logo_url, phone, homepage_cover_url, brand_id, city, metro_area, brands(name, logo_url))',
          )
          .inFilter('id', ids);
      if (activeOnly) {
        query = query.eq('is_active', true);
      }
      final data = await query;
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
          .select('deals(*, merchants(id, name, logo_url, phone, homepage_cover_url, brand_id, city, metro_area, brands(name, logo_url)))')
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

  /// 查询当前城市下有 active deal 的分类名集合（用于首页隐藏空分类图标）
  /// 同时覆盖两条路径：
  ///   ① deals.category 文字字段（旧逻辑兼容）
  ///   ② merchant_categories → categories.name（商家在后台重新分类后自动生效）
  Future<Set<String>> fetchAvailableCategories({String? city}) async {
    try {
      // Step 1: 获取有 active deal 的商家 ID + deals.category 旧值
      final merchantSelect = (city != null && city.isNotEmpty)
          ? 'merchant_id, category, merchants!inner(city)'
          : 'merchant_id, category';
      var dealQuery = _client
          .from('deals')
          .select(merchantSelect)
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toIso8601String());
      if (city != null && city.isNotEmpty) {
        dealQuery = dealQuery.ilike('merchants.city', '%$city%');
      }
      final deals = await dealQuery;

      final dealCategories = <String>{};
      final merchantIds = <String>{};
      for (final d in deals as List) {
        final cat = d['category'] as String?;
        if (cat != null && cat.isNotEmpty) dealCategories.add(cat);
        final mid = d['merchant_id'] as String?;
        if (mid != null) merchantIds.add(mid);
      }

      if (merchantIds.isEmpty) return dealCategories;

      // Step 2: 通过 merchant_categories 获取这些商家所属的分类名
      final catRows = await _client
          .from('merchant_categories')
          .select('categories!inner(name)')
          .inFilter('merchant_id', merchantIds.toList());

      final merchantCategories = (catRows as List)
          .map((row) =>
              (row['categories'] as Map<String, dynamic>?)?['name'] as String?)
          .whereType<String>()
          .toSet();

      return dealCategories.union(merchantCategories);
    } on PostgrestException catch (e) {
      throw AppException(
          'Failed to fetch categories: ${e.message}', code: e.code);
    }
  }

  /// 从 categories 表获取全部分类（顺序、图标）供客户端动态渲染
  Future<List<Map<String, dynamic>>> fetchCategoriesFromDB() async {
    try {
      final data = await _client
          .from('categories')
          .select('id, name, icon, order')
          .order('order');
      return (data as List).cast<Map<String, dynamic>>();
    } on PostgrestException catch (e) {
      throw AppException(
          'Failed to fetch DB categories: ${e.message}', code: e.code);
    }
  }

  /// 获取相似/推荐 deal（搜索无结果时展示）
  /// 逻辑：返回当前城市下热门的 active deal，按销量+评分排序
  Future<List<DealModel>> fetchSimilarDeals({String? city}) async {
    try {
      var query = _client
          .from('deals')
          .select('*, merchants(id, name, logo_url, phone, homepage_cover_url, brand_id, city, metro_area, brands(name, logo_url))')
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toIso8601String());

      if (city != null && city.isNotEmpty) {
        query = query.ilike('address', '%$city%');
      }

      final data = await query
          .order('total_sold', ascending: false)
          .order('rating', ascending: false)
          .limit(10);

      var results = (data as List).map((e) => DealModel.fromJson(e)).toList();
      results = await _filterBrandDealsWithActiveStores(results);
      return results;
    } on PostgrestException catch (e) {
      throw AppException('Failed to fetch similar deals: ${e.message}',
          code: e.code);
    }
  }
}
