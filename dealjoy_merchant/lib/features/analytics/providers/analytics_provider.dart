// =============================================================
// 数据分析状态管理
// 使用 Riverpod AsyncNotifier 模式
//
// Providers:
//   analyticsServiceProvider   — AnalyticsService 单例
//   _merchantIdProvider        — 当前登录商家 ID（内部用）
//   daysRangeProvider          — 时间范围选择（StateProvider<int>）
//   OverviewNotifier           — 经营概览异步 Notifier
//   overviewProvider           — 经营概览 Provider
//   dealFunnelProvider         — Deal 漏斗 FutureProvider
//   customerAnalysisProvider   — 客群分析 FutureProvider
// =============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/analytics_data.dart';
import '../services/analytics_service.dart';

// =============================================================
// 基础依赖 Provider
// =============================================================

/// 全局 SupabaseClient Provider
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// AnalyticsService Provider（单例）
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  final client = ref.watch(_supabaseProvider);
  return AnalyticsService(client);
});

// =============================================================
// _merchantIdProvider — 当前登录商家 ID（内部共享）
// =============================================================
/// 查询当前登录用户对应的 merchant_id
/// 若未登录或无对应商家账号，返回空字符串
final _merchantIdProvider = FutureProvider<String>((ref) async {
  final supabase = ref.watch(_supabaseProvider);
  final user = supabase.auth.currentUser;
  if (user == null) return '';

  try {
    final result = await supabase
        .from('merchants')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle();
    return result?['id'] as String? ?? '';
  } catch (_) {
    return '';
  }
});

// =============================================================
// daysRangeProvider — 时间范围选择 (7 或 30)
// =============================================================
/// 用户当前选择的时间范围（天），默认 7 天
/// 切换时会触发 overviewProvider 自动重建
final daysRangeProvider = StateProvider<int>((ref) => 7);

// =============================================================
// OverviewNotifier — 经营概览异步 Notifier
// =============================================================
/// 监听 daysRangeProvider，时间范围变化时自动重新拉取数据
class OverviewNotifier extends AsyncNotifier<OverviewStats> {
  @override
  Future<OverviewStats> build() async {
    // 监听时间范围：变化时触发重建
    final daysRange  = ref.watch(daysRangeProvider);
    final merchantId = await ref.watch(_merchantIdProvider.future);

    if (merchantId.isEmpty) {
      return OverviewStats.empty(daysRange: daysRange);
    }

    final service = ref.read(analyticsServiceProvider);
    return service.fetchOverview(merchantId, daysRange: daysRange);
  }

  // ---------------------------------------------------------
  // refresh — 手动刷新（下拉刷新 / retry 按钮用）
  // ---------------------------------------------------------
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }
}

/// 经营概览 Provider
final overviewProvider = AsyncNotifierProvider<OverviewNotifier, OverviewStats>(
  OverviewNotifier.new,
);

// =============================================================
// dealFunnelProvider — Deal 转化漏斗 FutureProvider
// =============================================================
/// 加载所有 Deal 的转化漏斗数据
/// 刷新方式：调用 ref.invalidate(dealFunnelProvider)
final dealFunnelProvider = FutureProvider<List<DealFunnelData>>((ref) async {
  final merchantId = await ref.watch(_merchantIdProvider.future);

  if (merchantId.isEmpty) {
    return [];
  }

  final service = ref.read(analyticsServiceProvider);
  return service.fetchDealFunnel(merchantId);
});

// =============================================================
// customerAnalysisProvider — 客群分析 FutureProvider
// =============================================================
/// 加载客群新老分析数据
/// 刷新方式：调用 ref.invalidate(customerAnalysisProvider)
final customerAnalysisProvider = FutureProvider<CustomerAnalysis>((ref) async {
  final merchantId = await ref.watch(_merchantIdProvider.future);

  if (merchantId.isEmpty) {
    return CustomerAnalysis.empty();
  }

  final service = ref.read(analyticsServiceProvider);
  return service.fetchCustomerAnalysis(merchantId);
});
