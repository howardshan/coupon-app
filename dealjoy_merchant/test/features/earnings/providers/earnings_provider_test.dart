// EarningsNotifier / TransactionsNotifier Provider 单元测试
// 策略: 使用 ProviderContainer + override 注入 mock service，
//       验证 Notifier 状态流转与 filter 操作行为。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dealjoy_merchant/features/earnings/models/earnings_data.dart';
import 'package:dealjoy_merchant/features/earnings/providers/earnings_provider.dart';
import 'package:dealjoy_merchant/features/earnings/services/earnings_service.dart';

// =============================================================
// Mock EarningsService
// =============================================================
class _MockEarningsService extends EarningsService {
  _MockEarningsService() : super(null as dynamic);

  EarningsSummary? stubbedSummary;
  bool throwOnSummary = false;
  int summaryCallCount = 0;

  PagedTransactions? stubbedTransactions;
  bool throwOnTransactions = false;

  SettlementSchedule? stubbedSchedule;
  StripeAccountInfo? stubbedAccount;

  @override
  Future<EarningsSummary> fetchEarningsSummary(
    String merchantId,
    DateTime month,
  ) async {
    summaryCallCount++;
    if (throwOnSummary) {
      throw const EarningsException(
        code: 'db_error',
        message: 'Fetch failed',
      );
    }
    return stubbedSummary ??
        EarningsSummary(
          month:             '2026-03',
          totalRevenue:      1000.0,
          pendingSettlement: 300.0,
          settledAmount:     600.0,
          refundedAmount:    100.0,
        );
  }

  @override
  Future<PagedTransactions> fetchTransactions(
    String merchantId, {
    DateTime? from,
    DateTime? to,
    int page = 1,
    int perPage = 20,
  }) async {
    if (throwOnTransactions) {
      throw const EarningsException(
        code: 'network_error',
        message: 'Network error',
      );
    }
    return stubbedTransactions ?? PagedTransactions.empty();
  }

  @override
  Future<SettlementSchedule> fetchSettlementSchedule(
      String merchantId) async {
    return stubbedSchedule ?? SettlementSchedule.defaultSchedule();
  }

  @override
  Future<StripeAccountInfo> fetchStripeAccountInfo(
      String merchantId) async {
    return stubbedAccount ?? StripeAccountInfo.notConnected();
  }

  @override
  Future<ReportData> fetchReportData(
    String merchantId, {
    required ReportPeriodType periodType,
    required int year,
    int? month,
    int? week,
  }) async {
    return ReportData.empty(periodType);
  }
}

// =============================================================
// 辅助: 构建带 mock 的 ProviderContainer
// =============================================================
ProviderContainer _buildContainer({
  _MockEarningsService? mockService,
  String? mockMerchantId,
}) {
  final service = mockService ?? _MockEarningsService();
  return ProviderContainer(
    overrides: [
      earningsServiceProvider.overrideWithValue(service),
      // 覆盖 merchantIdProvider 返回固定 ID，避免实际 Supabase 调用
      merchantIdProvider.overrideWith((ref) async => mockMerchantId ?? 'mock-merchant-id'),
    ],
  );
}

// =============================================================
// 测试套件
// =============================================================
void main() {
  // -----------------------------------------------------------
  // EarningsNotifier 测试
  // -----------------------------------------------------------
  group('EarningsNotifier', () {
    test('初始 build 返回 AsyncData<EarningsSummary>', () async {
      final container = _buildContainer();
      addTearDown(container.dispose);

      // 等待异步加载完成
      final result = await container.read(earningsSummaryProvider.future);

      expect(result.totalRevenue,      1000.0);
      expect(result.pendingSettlement, 300.0);
      expect(result.settledAmount,     600.0);
      expect(result.refundedAmount,    100.0);
    });

    test('merchantId 为空时返回 EarningsSummary.empty()', () async {
      final container = _buildContainer(mockMerchantId: '');
      addTearDown(container.dispose);

      final result = await container.read(earningsSummaryProvider.future);

      // empty() 时所有金额为 0
      expect(result.totalRevenue, 0.0);
    });

    test('service 抛出异常时 state 变为 AsyncError', () async {
      final mockService = _MockEarningsService()..throwOnSummary = true;
      final container   = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);

      // 等待 provider 完成（会是 error 状态）
      Object? caughtError;
      try {
        await container.read(earningsSummaryProvider.future);
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isA<EarningsException>());
      expect(
        container.read(earningsSummaryProvider),
        isA<AsyncError>(),
      );
    });

    test('切换月份时 state 重新加载', () async {
      final mockService = _MockEarningsService();
      final container   = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);

      // 初始加载
      await container.read(earningsSummaryProvider.future);
      final firstCallCount = mockService.summaryCallCount;

      // 切换到上月
      final current = container.read(selectedMonthProvider);
      container.read(selectedMonthProvider.notifier).state =
          DateTime(current.year, current.month - 1, 1);

      // 重新加载
      await container.read(earningsSummaryProvider.future);
      expect(mockService.summaryCallCount, greaterThan(firstCallCount));
    });

    test('refresh() 重新拉取数据', () async {
      final mockService = _MockEarningsService();
      final container   = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);

      await container.read(earningsSummaryProvider.future);
      final countBefore = mockService.summaryCallCount;

      await container.read(earningsSummaryProvider.notifier).refresh();

      expect(mockService.summaryCallCount, greaterThan(countBefore));
    });
  });

  // -----------------------------------------------------------
  // TransactionsNotifier 测试
  // -----------------------------------------------------------
  group('TransactionsNotifier', () {
    test('初始 build 返回空 PagedTransactions', () async {
      final container = _buildContainer();
      addTearDown(container.dispose);

      final result = await container.read(transactionsProvider.future);

      expect(result.data.isEmpty, true);
      expect(result.total,        0);
    });

    test('applyFilter 更新 transactionsFilterProvider', () async {
      final container = _buildContainer();
      addTearDown(container.dispose);

      await container.read(transactionsProvider.future);

      final from = DateTime(2026, 3, 1);
      final to   = DateTime(2026, 3, 31);
      container.read(transactionsProvider.notifier).applyFilter(from: from, to: to);

      final filter = container.read(transactionsFilterProvider);
      expect(filter.dateFrom, from);
      expect(filter.dateTo,   to);
      expect(filter.page,     1); // 重置到第 1 页
    });

    test('clearFilter 清除所有筛选条件', () async {
      final container = _buildContainer();
      addTearDown(container.dispose);

      // 先设置筛选
      container.read(transactionsFilterProvider.notifier).state = TransactionsFilter(
        dateFrom: DateTime(2026, 3, 1),
        page:     2,
      );

      // 清除
      container.read(transactionsProvider.notifier).clearFilter();

      final filter = container.read(transactionsFilterProvider);
      expect(filter.hasFilter, false);
      expect(filter.page,      1);
    });

    test('nextPage 增加页码', () {
      final container = _buildContainer();
      addTearDown(container.dispose);

      expect(container.read(transactionsFilterProvider).page, 1);

      container.read(transactionsProvider.notifier).nextPage();

      expect(container.read(transactionsFilterProvider).page, 2);
    });

    test('service 异常时 state 变为 AsyncError', () async {
      final mockService = _MockEarningsService()..throwOnTransactions = true;
      final container   = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);

      Object? caughtError;
      try {
        await container.read(transactionsProvider.future);
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isA<EarningsException>());
    });
  });

  // -----------------------------------------------------------
  // settlementScheduleProvider 测试
  // -----------------------------------------------------------
  group('settlementScheduleProvider', () {
    test('返回默认结算规则（service 降级）', () async {
      final container = _buildContainer();
      addTearDown(container.dispose);

      final result = await container.read(settlementScheduleProvider.future);

      expect(result.settlementDays, 7);
    });

    test('merchant 为空时返回 defaultSchedule', () async {
      final container = _buildContainer(mockMerchantId: '');
      addTearDown(container.dispose);

      final result = await container.read(settlementScheduleProvider.future);

      expect(result.hasPendingSettlement, false);
    });
  });

  // -----------------------------------------------------------
  // stripeAccountProvider 测试
  // -----------------------------------------------------------
  group('stripeAccountProvider', () {
    test('未连接时 isConnected 为 false', () async {
      final container = _buildContainer();
      addTearDown(container.dispose);

      final result = await container.read(stripeAccountProvider.future);

      expect(result.isConnected, false);
    });

    test('merchant 为空时返回 notConnected', () async {
      final container = _buildContainer(mockMerchantId: '');
      addTearDown(container.dispose);

      final result = await container.read(stripeAccountProvider.future);

      expect(result.isConnected,   false);
      expect(result.accountStatus, 'not_connected');
    });
  });

  // -----------------------------------------------------------
  // selectedMonthProvider 初始值测试
  // -----------------------------------------------------------
  group('selectedMonthProvider', () {
    test('初始值为本月 1 日', () {
      final container = _buildContainer();
      addTearDown(container.dispose);

      final month = container.read(selectedMonthProvider);
      final now   = DateTime.now();

      expect(month.year,  now.year);
      expect(month.month, now.month);
      expect(month.day,   1);
    });
  });

  // -----------------------------------------------------------
  // reportPeriodTypeProvider 测试
  // -----------------------------------------------------------
  group('reportPeriodTypeProvider', () {
    test('初始值为 monthly', () {
      final container = _buildContainer();
      addTearDown(container.dispose);

      expect(container.read(reportPeriodTypeProvider), ReportPeriodType.monthly);
    });

    test('切换为 weekly 后状态更新', () {
      final container = _buildContainer();
      addTearDown(container.dispose);

      container.read(reportPeriodTypeProvider.notifier).state =
          ReportPeriodType.weekly;

      expect(container.read(reportPeriodTypeProvider), ReportPeriodType.weekly);
    });
  });
}
