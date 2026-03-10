// 商家工作台状态管理
// 使用 Riverpod AsyncNotifier 模式
// 提供: dashboardProvider（完整数据）+ storeOnlineProvider（乐观 UI 更新）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dashboard_stats.dart';
import '../services/dashboard_service.dart';

// ============================================================
// 基础依赖 Provider（若已有全局定义可替换为 import）
// ============================================================

/// 全局 SupabaseClient（与 merchant_auth_provider 保持一致）
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// DashboardService Provider
final dashboardServiceProvider = Provider<DashboardService>((ref) {
  final client = ref.watch(_supabaseProvider);
  return DashboardService(client);
});

// ============================================================
// DashboardNotifier — 工作台数据核心 Notifier
//
// state: AsyncData<DashboardData>
//   - AsyncLoading: 首次加载 / 刷新中
//   - AsyncData: 正常数据
//   - AsyncError: 加载失败（展示 Retry 按钮）
// ============================================================
class DashboardNotifier extends AsyncNotifier<DashboardData> {
  @override
  Future<DashboardData> build() async {
    // 页面初始化时自动拉取数据
    return _fetchData();
  }

  // 获取 service 实例
  DashboardService get _service => ref.read(dashboardServiceProvider);

  // ----------------------------------------------------------
  // 私有: 实际调用 service 拉取数据
  // ----------------------------------------------------------
  Future<DashboardData> _fetchData() async {
    final data = await _service.fetchDashboardData();
    // 同步 storeOnlineProvider 初始值
    ref.read(storeOnlineProvider.notifier).state = data.stats.isOnline;
    return data;
  }

  // ----------------------------------------------------------
  // 公开: pull-to-refresh 刷新
  // ----------------------------------------------------------
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchData());
  }

  // ----------------------------------------------------------
  // 公开: 切换门店在线状态（乐观更新 + 网络请求）
  //
  // 流程:
  //   1. 立即更新 storeOnlineProvider（UI 快速响应）
  //   2. 调用 Edge Function PATCH
  //   3. 成功 → 更新 dashboardProvider 中的 isOnline
  //   4. 失败 → 回滚 storeOnlineProvider，抛出异常供 UI 显示
  // ----------------------------------------------------------
  Future<void> toggleOnlineStatus(bool newValue) async {
    // 步骤 1: 乐观更新（立即反映在 UI）
    ref.read(storeOnlineProvider.notifier).state = newValue;

    try {
      // 步骤 2: 调用 API
      final confirmedValue = await _service.updateOnlineStatus(newValue);

      // 步骤 3: 更新主数据中的 isOnline（不触发全量 loading）
      final current = state.value;
      if (current != null) {
        state = AsyncData(current.copyWithOnlineStatus(confirmedValue));
      }
      // 确保 storeOnlineProvider 与确认值一致
      ref.read(storeOnlineProvider.notifier).state = confirmedValue;
    } catch (e) {
      // 步骤 4: 回滚乐观更新
      ref.read(storeOnlineProvider.notifier).state = !newValue;
      // 重新抛出，由 UI 层显示 SnackBar 错误提示
      rethrow;
    }
  }
}

// ============================================================
// 对外暴露的主 Provider
// ============================================================
final dashboardProvider =
    AsyncNotifierProvider<DashboardNotifier, DashboardData>(
  DashboardNotifier.new,
);

// ============================================================
// storeOnlineProvider — 门店在线状态的独立 StateProvider
//
// 用途: 乐观 UI 更新时，Switch 控件立即响应，
//       不等待 dashboardProvider 整体 rebuild
// ============================================================
final storeOnlineProvider = StateProvider<bool>((ref) {
  // 初始值从 dashboardProvider 同步（如果已加载）
  // 使用 valueOrNull 避免在 AsyncError 状态下 rethrow 错误导致红屏
  final dashData = ref.watch(dashboardProvider).valueOrNull;
  return dashData?.stats.isOnline ?? true;
});

// ============================================================
// V2.1 品牌总览 Provider
// ============================================================

/// 品牌总览视图模式：单店 vs 品牌
final brandViewModeProvider = StateProvider<bool>((ref) => false);

/// 品牌总览数据
class BrandOverviewNotifier extends AsyncNotifier<BrandOverviewData> {
  @override
  Future<BrandOverviewData> build() async {
    return ref.read(dashboardServiceProvider).fetchBrandOverview();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dashboardServiceProvider).fetchBrandOverview(),
    );
  }
}

final brandOverviewProvider =
    AsyncNotifierProvider<BrandOverviewNotifier, BrandOverviewData>(
  BrandOverviewNotifier.new,
);

/// 门店排行排序方式
final rankingSortByProvider = StateProvider<String>((ref) => 'revenue');

/// 门店排行天数
final rankingDaysProvider = StateProvider<int>((ref) => 30);

/// 门店排行数据
final brandRankingsProvider = FutureProvider<List<StoreRanking>>((ref) async {
  final sortBy = ref.watch(rankingSortByProvider);
  final days = ref.watch(rankingDaysProvider);
  return ref
      .read(dashboardServiceProvider)
      .fetchBrandRankings(sortBy: sortBy, days: days);
});

/// 门店健康度数据
final brandHealthProvider = FutureProvider<List<StoreHealthAlert>>((ref) async {
  return ref.read(dashboardServiceProvider).fetchBrandHealth();
});
