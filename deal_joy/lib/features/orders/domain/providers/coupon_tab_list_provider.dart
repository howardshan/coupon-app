// My Coupons 各 Tab 游标分页 + 懒加载（进入 Tab 后首次 refresh）

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/coupon_model.dart';
import '../../data/models/coupon_page_cursor.dart';
import 'coupons_repository_provider.dart';

/// 可参与分页的 Tab（与 [fetch_my_coupon_ids_page] 的 p_tab 一致）
const kPaginatedCouponTabs = {'unused', 'used', 'expired', 'refunded', 'gifted'};

/// 单 Tab 列表状态
class CouponTabListState {
  final List<CouponModel> items;
  final bool loadingInitial;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;

  const CouponTabListState({
    this.items = const [],
    this.loadingInitial = false,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
  });

  CouponTabListState copyWith({
    List<CouponModel>? items,
    bool? loadingInitial,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
  }) {
    return CouponTabListState(
      items: items ?? this.items,
      loadingInitial: loadingInitial ?? this.loadingInitial,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }

  bool get canLoadMore => hasMore && !loadingMore && !loadingInitial && error == null;
}

final couponTabListProvider =
    NotifierProvider.family<CouponTabListNotifier, CouponTabListState, String>(
  CouponTabListNotifier.new,
);

class CouponTabListNotifier extends FamilyNotifier<CouponTabListState, String> {
  CouponKeysetCursor? _cursor;

  @override
  CouponTabListState build(String tab) {
    // 首次 build 在父组件 prime refresh 前显示加载中
    return const CouponTabListState(loadingInitial: true, hasMore: true);
  }

  /// 首次进入 Tab 时调用：拉第一页
  Future<void> refresh() async {
    final tab = arg;
    if (!kPaginatedCouponTabs.contains(tab)) return;

    _cursor = null;
    state = state.copyWith(
      loadingInitial: true,
      loadingMore: false,
      error: null,
      items: const [],
    );

    try {
      final repo = ref.read(couponsRepositoryProvider);
      final page = await repo.fetchMyCouponsPage(tab: tab, cursor: null);
      _cursor = page.hasMore ? page.nextCursor : null;
      state = CouponTabListState(
        items: page.items,
        loadingInitial: false,
        loadingMore: false,
        hasMore: page.hasMore,
        error: null,
      );
    } catch (e) {
      state = CouponTabListState(
        items: const [],
        loadingInitial: false,
        loadingMore: false,
        hasMore: false,
        error: e,
      );
    }
  }

  Future<void> loadMore() async {
    final tab = arg;
    if (!state.canLoadMore || _cursor == null) return;

    state = state.copyWith(loadingMore: true);
    try {
      final repo = ref.read(couponsRepositoryProvider);
      final page = await repo.fetchMyCouponsPage(tab: tab, cursor: _cursor);
      _cursor = page.hasMore ? page.nextCursor : null;
      state = CouponTabListState(
        items: [...state.items, ...page.items],
        loadingInitial: false,
        loadingMore: false,
        hasMore: page.hasMore,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e);
    }
  }
}

/// 失效所有分页 Tab（退款/赠送等操作后调用）
/// 入参为 [Ref.invalidate] / [WidgetRef.invalidate] 的 tear-off，二者无共同静态父类型
void invalidateAllCouponTabLists(void Function(ProviderOrFamily) invalidate) {
  for (final t in kPaginatedCouponTabs) {
    invalidate(couponTabListProvider(t));
  }
}
