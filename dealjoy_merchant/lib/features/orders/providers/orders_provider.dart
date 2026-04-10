// 订单管理 Riverpod Providers
// OrdersNotifier: 订单列表分页状态
// orderFilterProvider: 筛选条件 StateProvider
// orderDetailProvider: 单个订单详情（autoDispose：离开详情即释放，再进入重新拉取）
// merchantDealsForFilterProvider: 商家 deals 列表（供筛选下拉使用）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/merchant_order.dart';
import '../services/orders_service.dart';

// =============================================================
// ordersServiceProvider — 单例服务 Provider
// =============================================================
final ordersServiceProvider = Provider<OrdersService>((ref) {
  return OrdersService(Supabase.instance.client);
});

// =============================================================
// orderFilterProvider — 筛选条件 StateProvider
// 变更时自动触发 OrdersNotifier 重建
// =============================================================
final orderFilterProvider = StateProvider<OrderFilter>((ref) {
  return const OrderFilter();
});

// =============================================================
// OrdersNotifier — 订单列表（分页 + 下拉刷新 + 加载更多）
// =============================================================
final ordersNotifierProvider =
    AsyncNotifierProvider<OrdersNotifier, List<MerchantOrder>>(
        OrdersNotifier.new);

class OrdersNotifier extends AsyncNotifier<List<MerchantOrder>> {
  // 分页状态
  int _currentPage = 1;
  bool _hasMore = false;
  int _total = 0;
  bool _isLoadingMore = false;

  bool get hasMore => _hasMore;
  int get total => _total;
  bool get isLoadingMore => _isLoadingMore;

  @override
  Future<List<MerchantOrder>> build() async {
    // 监听筛选条件变化，自动从第一页重新加载
    ref.watch(orderFilterProvider);
    return _fetchPage(1, replace: true);
  }

  /// 内部分页获取方法
  Future<List<MerchantOrder>> _fetchPage(
    int page, {
    required bool replace,
  }) async {
    final filter = ref.read(orderFilterProvider);
    final service = ref.read(ordersServiceProvider);

    final result = await service.fetchOrders(
      filter: filter,
      page: page,
      perPage: 20,
    );

    _currentPage = result.page;
    _hasMore = result.hasMore;
    _total = result.total;

    if (replace) {
      return result.data;
    } else {
      return [...(state.value ?? []), ...result.data];
    }
  }

  /// 下拉刷新 — 重置到第一页
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchPage(1, replace: true));
  }

  /// 加载更多（上拉分页）
  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    _isLoadingMore = true;
    try {
      final nextPage = _currentPage + 1;
      final updated = await _fetchPage(nextPage, replace: false);
      state = AsyncData(updated);
    } catch (e, st) {
      // 加载更多失败时保留现有列表，不清空
      // ignore: unused_local_variable
      final _ = st;
    } finally {
      _isLoadingMore = false;
    }
  }
}

// =============================================================
// orderDetailProvider — 单个订单详情
// autoDispose：无监听时释放，避免退回列表后仍展示陈旧缓存
// =============================================================
final orderDetailProvider = AsyncNotifierProvider
    .autoDispose
    .family<OrderDetailNotifier, MerchantOrderDetail, String>(
  OrderDetailNotifier.new,
);

class OrderDetailNotifier
    extends AutoDisposeFamilyAsyncNotifier<MerchantOrderDetail, String> {
  @override
  Future<MerchantOrderDetail> build(String arg) async {
    final service = ref.read(ordersServiceProvider);
    return service.fetchOrderDetail(arg);
  }

  /// 手动刷新详情
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final service = ref.read(ordersServiceProvider);
      return service.fetchOrderDetail(arg);
    });
  }
}

// =============================================================
// merchantDealsForFilterProvider — 商家 deals 列表（供筛选使用）
// 获取当前商家所有 deals 的 {id, title} 列表
// =============================================================
final merchantDealsForFilterProvider =
    FutureProvider<List<Map<String, String>>>((ref) async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  // 先获取 merchant id
  final merchantResp = await supabase
      .from('merchants')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle();

  if (merchantResp == null) return [];
  final merchantId = merchantResp['id'] as String;

  final service = ref.read(ordersServiceProvider);
  return service.fetchMerchantDeals(merchantId);
});

// =============================================================
// orderExportProvider — CSV 导出状态
// AsyncNotifier，触发导出操作并返回 CSV 字符串
// =============================================================
final orderExportProvider =
    AsyncNotifierProvider<OrderExportNotifier, String?>(
        OrderExportNotifier.new);

class OrderExportNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    // 初始状态：未导出
    return null;
  }

  /// 执行导出，返回 CSV 字符串
  Future<String?> export() async {
    state = const AsyncLoading();
    final filter = ref.read(orderFilterProvider);
    final service = ref.read(ordersServiceProvider);

    state = await AsyncValue.guard(
        () => service.exportOrdersCsv(filter: filter));
    return state.value;
  }

  /// 重置导出状态
  void reset() {
    state = const AsyncData(null);
  }
}
