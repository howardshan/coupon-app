// 品牌佣金收益状态管理
// 使用 Riverpod AsyncNotifier 模式
// Providers:
//   brandEarningsServiceProvider       — BrandEarningsService 单例
//   brandSelectedMonthProvider         — 当前选中月份
//   brandEarningsSummaryProvider       — 品牌月度收益概览
//   brandTransactionsProvider          — 品牌交易明细
//   brandBalanceProvider               — 品牌可提现余额
//   brandStripeAccountProvider         — 品牌 Stripe 账户状态
//   brandWithdrawalHistoryProvider     — 品牌提现记录

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/brand_earnings_data.dart';
import '../services/brand_earnings_service.dart';

// =============================================================
// 基础依赖 Provider
// =============================================================

/// 全局 SupabaseClient Provider
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// BrandEarningsService Provider（单例）
final brandEarningsServiceProvider = Provider<BrandEarningsService>((ref) {
  final client = ref.watch(_supabaseProvider);
  return BrandEarningsService(client);
});

// =============================================================
// brandSelectedMonthProvider — 月份选择器状态
// =============================================================
/// 品牌收益页当前选中月份（默认为本月）
final brandSelectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

// =============================================================
// BrandEarningsSummaryNotifier — 品牌月度收益概览
// =============================================================
/// 品牌收益概览 Notifier，监听 brandSelectedMonthProvider 自动重建
class BrandEarningsSummaryNotifier
    extends AsyncNotifier<BrandEarningsSummary> {
  @override
  Future<BrandEarningsSummary> build() async {
    final selectedMonth = ref.watch(brandSelectedMonthProvider);
    final monthStr = _formatMonth(selectedMonth);

    final service = ref.read(brandEarningsServiceProvider);
    return service.fetchSummary(monthStr);
  }

  /// 手动刷新
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }

  String _formatMonth(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }
}

/// 品牌收益概览 Provider
final brandEarningsSummaryProvider =
    AsyncNotifierProvider<BrandEarningsSummaryNotifier, BrandEarningsSummary>(
  BrandEarningsSummaryNotifier.new,
);

// =============================================================
// BrandTransactionsNotifier — 品牌交易明细（前 10 条预览）
// =============================================================

/// 品牌交易明细 Notifier
class BrandTransactionsNotifier extends AsyncNotifier<
    ({List<BrandTransaction> items, int total, Map<String, double> totals})> {
  @override
  Future<
      ({
        List<BrandTransaction> items,
        int total,
        Map<String, double> totals
      })> build() async {
    final selectedMonth = ref.watch(brandSelectedMonthProvider);
    final monthStr =
        '${selectedMonth.year}-${selectedMonth.month.toString().padLeft(2, '0')}';

    final service = ref.read(brandEarningsServiceProvider);
    return service.fetchTransactions(month: monthStr, perPage: 10);
  }

  /// 手动刷新
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }
}

/// 品牌交易明细 Provider
final brandTransactionsProvider = AsyncNotifierProvider<
    BrandTransactionsNotifier,
    ({List<BrandTransaction> items, int total, Map<String, double> totals})>(
  BrandTransactionsNotifier.new,
);

// =============================================================
// brandBalanceProvider — 品牌可提现余额
// =============================================================
/// 品牌账户余额（FutureProvider）
final brandBalanceProvider = FutureProvider<BrandBalance>((ref) async {
  final service = ref.read(brandEarningsServiceProvider);
  return service.fetchBalance();
});

// =============================================================
// brandStripeAccountProvider — 品牌 Stripe 账户状态
// =============================================================
/// 品牌 Stripe 账户信息（FutureProvider）
final brandStripeAccountProvider =
    FutureProvider<BrandStripeAccount>((ref) async {
  final service = ref.read(brandEarningsServiceProvider);
  return service.fetchStripeAccount();
});

// =============================================================
// brandWithdrawalSettingsProvider — 品牌自动提现设置
// =============================================================
/// 品牌自动提现设置（FutureProvider）
final brandWithdrawalSettingsProvider =
    FutureProvider<BrandWithdrawalSettings>((ref) async {
  final service = ref.read(brandEarningsServiceProvider);
  return service.fetchWithdrawalSettings();
});

// =============================================================
// brandWithdrawalHistoryProvider — 品牌提现记录
// =============================================================
/// 品牌提现历史记录（FutureProvider）
final brandWithdrawalHistoryProvider =
    FutureProvider<List<BrandWithdrawalRecord>>((ref) async {
  final service = ref.read(brandEarningsServiceProvider);
  return service.fetchWithdrawalHistory();
});
