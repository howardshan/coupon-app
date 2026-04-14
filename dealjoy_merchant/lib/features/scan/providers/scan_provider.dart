// 扫码核销 Riverpod Providers
// ScanNotifier: 管理单次扫码/核销流程状态
// RedemptionHistoryNotifier: 管理核销历史列表分页状态

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/coupon_info.dart';
import '../services/scan_service.dart';

// =============================================================
// ScanService Provider — 单例服务
// =============================================================
final scanServiceProvider = Provider<ScanService>((ref) {
  return ScanService(Supabase.instance.client);
});

// =============================================================
// ScanNotifier — 单次扫码/核销流程状态机
// state: AsyncValue<CouponInfo?> — null 表示初始态（未扫码）
// =============================================================
final scanNotifierProvider =
    AsyncNotifierProvider<ScanNotifier, CouponInfo?>(ScanNotifier.new);

class ScanNotifier extends AsyncNotifier<CouponInfo?> {
  @override
  Future<CouponInfo?> build() async {
    // 初始状态：未扫码
    return null;
  }

  /// 验证券码（扫码或手动输入后调用）
  /// 成功后 state 更新为 AsyncData(CouponInfo)
  /// 失败则 state 更新为 AsyncError(ScanException)
  Future<void> verify(String code) async {
    state = const AsyncLoading();
    final service = ref.read(scanServiceProvider);
    state = await AsyncValue.guard(() => service.verifyCoupon(code));
  }

  /// 执行核销，返回核销时间
  /// 调用方负责在成功后导航到成功页
  Future<DateTime> redeem(String couponId) async {
    final service = ref.read(scanServiceProvider);
    // 核销期间不更新 state（保持 CouponInfo 展示），由调用方处理 loading UI
    return service.redeemCoupon(couponId);
  }

  /// 重置扫码状态（返回扫码页时调用）
  void reset() {
    state = const AsyncData(null);
  }
}

// =============================================================
// 核销历史筛选条件 Provider
// =============================================================
final redemptionHistoryFilterProvider =
    StateProvider<RedemptionHistoryFilter>((ref) {
  return const RedemptionHistoryFilter();
});

// =============================================================
// RedemptionHistoryNotifier — 核销历史分页列表
// state: AsyncValue<List<RedemptionRecord>>
// =============================================================
final redemptionHistoryProvider = AsyncNotifierProvider<
    RedemptionHistoryNotifier,
    List<RedemptionRecord>>(RedemptionHistoryNotifier.new);

class RedemptionHistoryNotifier
    extends AsyncNotifier<List<RedemptionRecord>> {
  // 分页状态
  int _currentPage = 1;
  bool _hasMore = false;
  int _total = 0;
  bool _isLoadingMore = false;

  bool get hasMore => _hasMore;
  int get total => _total;

  @override
  Future<List<RedemptionRecord>> build() async {
    // 监听筛选条件变化，自动重新加载第一页
    ref.watch(redemptionHistoryFilterProvider);
    return _fetchPage(1, replace: true);
  }

  /// 获取指定页，replace=true 时替换列表，false 时追加（加载更多）
  Future<List<RedemptionRecord>> _fetchPage(
    int page, {
    required bool replace,
  }) async {
    final filter = ref.read(redemptionHistoryFilterProvider);
    final service = ref.read(scanServiceProvider);

    final result = await service.fetchRedemptionHistory(
      from: filter.dateFrom,
      to: filter.dateTo,
      dealId: filter.dealId,
      page: page,
    );

    _currentPage = result['page'] as int;
    _hasMore = result['has_more'] as bool;
    _total = result['total'] as int;

    final newRecords = result['data'] as List<RedemptionRecord>;

    if (replace) {
      return newRecords;
    } else {
      return [...(state.value ?? []), ...newRecords];
    }
  }

  /// 下拉刷新 — 重新从第一页开始
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchPage(1, replace: true));
  }

  /// 加载更多（上滑分页）
  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    _isLoadingMore = true;
    try {
      final nextPage = _currentPage + 1;
      final updated = await _fetchPage(nextPage, replace: false);
      state = AsyncData(updated);
    } catch (e, st) {
      // 加载更多失败不清空现有列表，保留当前数据
      state = AsyncError(e, st);
    } finally {
      _isLoadingMore = false;
    }
  }

}
