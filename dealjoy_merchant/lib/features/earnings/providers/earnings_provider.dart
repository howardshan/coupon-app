// 财务与结算状态管理
// 使用 Riverpod AsyncNotifier 模式
// Providers:
//   earningsServiceProvider       — EarningsService 单例
//   selectedMonthProvider         — 当前选中月份（月份选择器用）
//   earningsSummaryProvider       — 收入概览数据
//   transactionsFilterProvider    — 交易明细筛选条件
//   transactionsProvider          — 交易明细分页数据
//   settlementScheduleProvider    — 结算规则与下次打款信息
//   stripeAccountProvider         — Stripe 账户状态
//   reportPeriodTypeProvider      — 对账报表周期类型
//   reportSelectedMonthProvider   — 对账报表选中月份
//   reportDataProvider            — 对账报表数据

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/earnings_data.dart';
import '../services/earnings_service.dart';

// =============================================================
// 基础依赖 Provider
// =============================================================

/// 全局 SupabaseClient Provider
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// EarningsService Provider（单例）
final earningsServiceProvider = Provider<EarningsService>((ref) {
  final client = ref.watch(_supabaseProvider);
  return EarningsService(client);
});

// =============================================================
// merchantIdProvider — 获取当前登录商家 ID
// =============================================================
/// 当前登录用户对应的 merchant_id（从 merchants 表查询）
/// 若未登录或无对应商家，返回空字符串
final merchantIdProvider = FutureProvider<String>((ref) async {
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
// selectedMonthProvider — 月份选择器状态
// =============================================================
/// 收入概览页当前选中的月份（默认为本月）
final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  // 月份只取年月，日固定为 1
  return DateTime(now.year, now.month, 1);
});

// =============================================================
// EarningsNotifier — 收入概览数据
// =============================================================
/// 收入概览 Notifier，监听 selectedMonthProvider 自动重新加载
class EarningsNotifier extends AsyncNotifier<EarningsSummary> {
  @override
  Future<EarningsSummary> build() async {
    // 监听月份选择器：月份变化时自动触发重建
    final selectedMonth = ref.watch(selectedMonthProvider);
    final merchantIdAsync = await ref.watch(merchantIdProvider.future);

    if (merchantIdAsync.isEmpty) {
      return EarningsSummary.empty(_formatMonth(selectedMonth));
    }

    final service = ref.read(earningsServiceProvider);
    return service.fetchEarningsSummary(merchantIdAsync, selectedMonth);
  }

  /// 手动刷新（pull-to-refresh 用）
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }

  String _formatMonth(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }
}

/// 收入概览 Provider
final earningsSummaryProvider =
    AsyncNotifierProvider<EarningsNotifier, EarningsSummary>(
  EarningsNotifier.new,
);

// =============================================================
// transactionsFilterProvider — 交易明细筛选条件
// =============================================================
/// 交易明细页面的筛选条件（日期范围 + 页码）
final transactionsFilterProvider = StateProvider<TransactionsFilter>((ref) {
  return const TransactionsFilter(page: 1);
});

// =============================================================
// TransactionsNotifier — 交易明细分页数据
// =============================================================
/// 交易明细 Notifier，监听 transactionsFilterProvider 自动重建
class TransactionsNotifier extends AsyncNotifier<PagedTransactions> {
  @override
  Future<PagedTransactions> build() async {
    final filter        = ref.watch(transactionsFilterProvider);
    final merchantIdAsync = await ref.watch(merchantIdProvider.future);

    if (merchantIdAsync.isEmpty) {
      return PagedTransactions.empty();
    }

    final service = ref.read(earningsServiceProvider);
    return service.fetchTransactions(
      merchantIdAsync,
      from:    filter.dateFrom,
      to:      filter.dateTo,
      page:    filter.page,
      perPage: 20,
    );
  }

  /// 应用日期筛选（重置页码到第 1 页）
  void applyFilter({DateTime? from, DateTime? to}) {
    ref.read(transactionsFilterProvider.notifier).state =
        TransactionsFilter(dateFrom: from, dateTo: to, page: 1);
  }

  /// 清除筛选条件
  void clearFilter() {
    ref.read(transactionsFilterProvider.notifier).state =
        const TransactionsFilter(page: 1);
  }

  /// 翻页（加载下一页）
  void nextPage() {
    final current = ref.read(transactionsFilterProvider);
    ref.read(transactionsFilterProvider.notifier).state =
        current.copyWith(page: current.page + 1);
  }

  /// 刷新（重置到第 1 页）
  Future<void> refresh() async {
    final current = ref.read(transactionsFilterProvider);
    ref.read(transactionsFilterProvider.notifier).state =
        current.copyWith(page: 1);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }
}

/// 交易明细 Provider
final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, PagedTransactions>(
  TransactionsNotifier.new,
);

// =============================================================
// settlementScheduleProvider — 结算规则与下次打款信息
// =============================================================
/// 结算规则数据（FutureProvider，页面初始化时加载一次）
final settlementScheduleProvider = FutureProvider<SettlementSchedule>((ref) async {
  final merchantIdAsync = await ref.watch(merchantIdProvider.future);

  if (merchantIdAsync.isEmpty) {
    return SettlementSchedule.defaultSchedule();
  }

  final service = ref.read(earningsServiceProvider);
  return service.fetchSettlementSchedule(merchantIdAsync);
});

// =============================================================
// stripeAccountProvider — Stripe Connect 账户状态
// =============================================================
/// Stripe 账户信息（FutureProvider，页面初始化时加载一次）
final stripeAccountProvider = FutureProvider<StripeAccountInfo>((ref) async {
  final merchantIdAsync = await ref.watch(merchantIdProvider.future);

  if (merchantIdAsync.isEmpty) {
    return StripeAccountInfo.notConnected();
  }

  final service = ref.read(earningsServiceProvider);
  return service.fetchStripeAccountInfo(merchantIdAsync);
});

// =============================================================
// 对账报表 Providers（P2）
// =============================================================

/// 报表周期类型（Monthly / Weekly）
final reportPeriodTypeProvider = StateProvider<ReportPeriodType>((ref) {
  return ReportPeriodType.monthly;
});

/// 报表当前选中月份（默认本月）
final reportSelectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

/// 对账报表数据（根据 reportPeriodTypeProvider + reportSelectedMonthProvider 动态加载）
final reportDataProvider = FutureProvider<ReportData>((ref) async {
  final periodType    = ref.watch(reportPeriodTypeProvider);
  final selectedMonth = ref.watch(reportSelectedMonthProvider);
  final merchantIdAsync = await ref.watch(merchantIdProvider.future);

  if (merchantIdAsync.isEmpty) {
    return ReportData.empty(periodType);
  }

  final service = ref.read(earningsServiceProvider);

  // 计算当前选中月份是本年第几周（仅 weekly 模式用）
  final weekOfYear = _weekOfYear(selectedMonth);

  return service.fetchReportData(
    merchantIdAsync,
    periodType: periodType,
    year:       selectedMonth.year,
    month:      selectedMonth.month,
    week:       weekOfYear,
  );
});

/// 计算指定日期在当年的周次（ISO 周）
int _weekOfYear(DateTime date) {
  final firstDayOfYear  = DateTime(date.year, 1, 1);
  final dayOfYear       = date.difference(firstDayOfYear).inDays;
  return (dayOfYear / 7).ceil() + 1;
}

// =============================================================
// 提现相关 Providers
// =============================================================

/// 可提现余额
final withdrawalBalanceProvider = FutureProvider<WithdrawalBalance>((ref) async {
  final service = ref.read(earningsServiceProvider);
  return service.fetchWithdrawalBalance();
});

/// 提现记录
final withdrawalHistoryProvider = FutureProvider<List<WithdrawalRecord>>((ref) async {
  final service = ref.read(earningsServiceProvider);
  return service.fetchWithdrawalHistory();
});

/// 提现设置
final withdrawalSettingsProvider = FutureProvider<WithdrawalSettings>((ref) async {
  final service = ref.read(earningsServiceProvider);
  return service.fetchWithdrawalSettings();
});
