import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../deals/data/models/deal_model.dart';
import '../../../deals/data/models/review_model.dart';
import '../../data/models/deal_category_model.dart';
import '../../data/models/merchant_detail_model.dart';
import '../../data/models/menu_item_model.dart';
import '../../data/models/review_stats_model.dart';
import '../../data/models/store_facility_model.dart';
import '../../data/repositories/store_detail_repository.dart';

// ── Repository Provider ─────────────────────────────────────

final storeDetailRepositoryProvider = Provider<StoreDetailRepository>((ref) {
  return StoreDetailRepository(ref.watch(supabaseClientProvider));
});

// ── 商家详情（含照片+营业时间）─────────────────────────────

final merchantDetailInfoProvider =
    FutureProvider.family<MerchantDetailModel, String>((ref, merchantId) async {
  return ref.watch(storeDetailRepositoryProvider).fetchMerchantDetail(merchantId);
});

// ── 商家活跃 Deals ──────────────────────────────────────────

final merchantActiveDealsProvider =
    FutureProvider.family<List<DealModel>, String>((ref, merchantId) async {
  return ref.watch(storeDetailRepositoryProvider).fetchActiveDeals(merchantId);
});

// ── Deal 分类列表 ─────────────────────────────────────────────

final dealCategoriesProvider =
    FutureProvider.family<List<DealCategoryModel>, String>((ref, merchantId) async {
  return ref.watch(storeDetailRepositoryProvider).fetchDealCategories(merchantId);
});

// ── 当前选中的 Deal 分类（null = All）─────────────────────────

final selectedDealCategoryProvider =
    StateProvider.family<String?, String>((ref, merchantId) => null);

// ── 按分类筛选后的 Deals（分 voucher 和 regular）──────────────

final filteredDealsProvider = Provider.family<
    ({List<DealModel> vouchers, List<DealModel> regulars}), String>(
  (ref, merchantId) {
    final dealsAsync = ref.watch(merchantActiveDealsProvider(merchantId));
    final selectedCategory = ref.watch(selectedDealCategoryProvider(merchantId));

    final allDeals = dealsAsync.valueOrNull ?? [];

    final vouchers =
        allDeals.where((d) => d.dealType == 'voucher').toList();
    var regulars =
        allDeals.where((d) => d.dealType != 'voucher').toList();

    // 按选中分类过滤
    if (selectedCategory != null) {
      regulars = regulars
          .where((d) => d.dealCategoryId == selectedCategory)
          .toList();
    }

    return (vouchers: vouchers, regulars: regulars);
  },
);

// ── 菜品列表（按 category 分组）─────────────────────────────

final menuItemsProvider =
    FutureProvider.family<Map<String, List<MenuItemModel>>, String>((
  ref,
  merchantId,
) async {
  final items =
      await ref.watch(storeDetailRepositoryProvider).fetchMenuItems(merchantId);
  return {
    'signature': items.where((i) => i.category == 'signature').toList(),
    'popular': items.where((i) => i.category == 'popular').toList(),
    'regular': items.where((i) => i.category == 'regular').toList(),
  };
});

// ── 设施信息 ────────────────────────────────────────────────

final facilitiesProvider =
    FutureProvider.family<List<StoreFacilityModel>, String>((
  ref,
  merchantId,
) async {
  return ref.watch(storeDetailRepositoryProvider).fetchFacilities(merchantId);
});

// ── 评价统计 ────────────────────────────────────────────────

final reviewStatsProvider =
    FutureProvider.family<ReviewStatsModel, String>((ref, merchantId) async {
  return ref.watch(storeDetailRepositoryProvider).fetchReviewStats(merchantId);
});

// ── 评价列表（支持分页）─────────────────────────────────────

final merchantReviewsProvider = AsyncNotifierProvider.family<
    MerchantReviewsNotifier, List<ReviewModel>, String>(
  MerchantReviewsNotifier.new,
);

class MerchantReviewsNotifier
    extends FamilyAsyncNotifier<List<ReviewModel>, String> {
  int _page = 0;
  bool _hasMore = true;

  bool get hasMore => _hasMore;

  @override
  Future<List<ReviewModel>> build(String arg) async {
    _page = 0;
    _hasMore = true;
    final reviews = await ref
        .watch(storeDetailRepositoryProvider)
        .fetchMerchantReviews(arg, page: 0);
    if (reviews.length < 10) _hasMore = false;
    return reviews;
  }

  Future<void> loadMore() async {
    if (!_hasMore || state.isLoading) return;
    _page++;
    final more = await ref
        .read(storeDetailRepositoryProvider)
        .fetchMerchantReviews(arg, page: _page);
    if (more.length < 10) _hasMore = false;
    state = AsyncValue.data([...state.value ?? [], ...more]);
  }
}

// ── 附近推荐商家 ────────────────────────────────────────────

final nearbyMerchantsProvider = FutureProvider.family<
    List<Map<String, dynamic>>, ({String merchantId, double lat, double lng})>(
  (ref, params) async {
    return ref.watch(storeDetailRepositoryProvider).fetchNearbyMerchants(
          lat: params.lat,
          lng: params.lng,
          excludeId: params.merchantId,
        );
  },
);
