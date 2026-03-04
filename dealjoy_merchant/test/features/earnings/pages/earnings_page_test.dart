// EarningsPage Widget 测试
// 策略: 使用 ProviderScope + overrides 注入 mock providers，
//       验证各 UI 区块的渲染逻辑（加载/数据/错误状态）

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dealjoy_merchant/features/earnings/models/earnings_data.dart';
import 'package:dealjoy_merchant/features/earnings/pages/earnings_page.dart';
import 'package:dealjoy_merchant/features/earnings/providers/earnings_provider.dart';

// =============================================================
// 测试辅助：包装 EarningsPage 的最小 App
// =============================================================
Widget _buildTestApp({
  required List<Override> overrides,
}) {
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(
      home: EarningsPage(),
    ),
  );
}

// =============================================================
// Mock 数据工厂
// =============================================================
EarningsSummary _mockSummary() {
  return const EarningsSummary(
    month:             '2026-03',
    totalRevenue:      1234.56,
    pendingSettlement: 400.00,
    settledAmount:     700.00,
    refundedAmount:    134.56,
  );
}

SettlementSchedule _mockSchedule() {
  return SettlementSchedule(
    settlementRule:    'Redeemed orders are settled T+7 days after redemption',
    settlementDays:    7,
    nextPayoutDate:    DateTime(2026, 3, 10),
    pendingAmount:     400.00,
    pendingOrderCount: 4,
  );
}

StripeAccountInfo _mockStripeConnected() {
  return const StripeAccountInfo(
    isConnected:   true,
    accountId:     'acct_1A2B3C',
    accountEmail:  'store@example.com',
    accountStatus: 'connected',
  );
}

StripeAccountInfo _mockStripeNotConnected() {
  return StripeAccountInfo.notConnected();
}

PagedTransactions _mockTransactions() {
  return PagedTransactions(
    data: [
      EarningsTransaction(
        orderId:     'abc12345-0000-0000-0000-000000000001',
        amount:      50.00,
        platformFee: 7.50,
        netAmount:   42.50,
        status:      'used',
        createdAt:   DateTime(2026, 3, 1, 12),
      ),
      EarningsTransaction(
        orderId:     'def67890-0000-0000-0000-000000000002',
        amount:      80.00,
        platformFee: 12.00,
        netAmount:   68.00,
        status:      'unused',
        createdAt:   DateTime(2026, 3, 2, 14),
      ),
    ],
    page:    1,
    perPage: 20,
    total:   2,
    hasMore: false,
    totals:  const TransactionTotals(
      amount:      130.00,
      platformFee: 19.50,
      netAmount:   110.50,
    ),
  );
}

// =============================================================
// Provider overrides 辅助函数
// =============================================================
List<Override> _buildOverrides({
  AsyncValue<EarningsSummary>? summary,
  AsyncValue<SettlementSchedule>? settlement,
  AsyncValue<StripeAccountInfo>? stripe,
  AsyncValue<PagedTransactions>? transactions,
}) {
  return [
    earningsSummaryProvider.overrideWith(() => _StubEarningsNotifier(
          summaryState: summary ?? AsyncData(_mockSummary()),
        )),
    settlementScheduleProvider.overrideWith(
      (ref) async => settlement?.value ?? _mockSchedule(),
    ),
    stripeAccountProvider.overrideWith(
      (ref) async => stripe?.value ?? _mockStripeNotConnected(),
    ),
    transactionsProvider.overrideWith(() => _StubTransactionsNotifier(
          transactionsState: transactions ?? AsyncData(_mockTransactions()),
        )),
    // merchantId 不需要实际查询
    merchantIdProvider.overrideWith((ref) async => 'mock-merchant-id'),
  ];
}

// Stub EarningsNotifier
class _StubEarningsNotifier extends EarningsNotifier {
  final AsyncValue<EarningsSummary> summaryState;

  _StubEarningsNotifier({required this.summaryState});

  @override
  Future<EarningsSummary> build() async {
    state = summaryState;
    return summaryState.value ?? EarningsSummary.empty('2026-03');
  }
}

// Stub TransactionsNotifier
class _StubTransactionsNotifier extends TransactionsNotifier {
  final AsyncValue<PagedTransactions> transactionsState;

  _StubTransactionsNotifier({required this.transactionsState});

  @override
  Future<PagedTransactions> build() async {
    state = transactionsState;
    return transactionsState.value ?? PagedTransactions.empty();
  }
}

// =============================================================
// 测试套件
// =============================================================
void main() {
  // -----------------------------------------------------------
  // 正常数据状态测试
  // -----------------------------------------------------------
  group('EarningsPage — 正常数据状态', () {
    testWidgets('显示 AppBar 标题 Earnings', (tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: _buildOverrides()));
      await tester.pumpAndSettle();

      expect(find.text('Earnings'), findsOneWidget);
    });

    testWidgets('显示 4 张收入概览卡片标题', (tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: _buildOverrides()));
      await tester.pumpAndSettle();

      expect(find.text('This Month'),  findsOneWidget);
      expect(find.text('Pending'),     findsOneWidget);
      expect(find.text('Settled'),     findsOneWidget);
      expect(find.text('Refunded'),    findsOneWidget);
    });

    testWidgets('显示 totalRevenue 金额', (tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: _buildOverrides()));
      await tester.pumpAndSettle();

      expect(find.text('\$1234.56'), findsOneWidget);
    });

    testWidgets('显示结算区块标题 Settlement Info', (tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: _buildOverrides()));
      await tester.pumpAndSettle();

      expect(find.text('Settlement Info'), findsOneWidget);
    });

    testWidgets('显示 Recent Transactions 区块标题', (tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: _buildOverrides()));
      await tester.pumpAndSettle();

      expect(find.text('Recent Transactions'), findsOneWidget);
    });

    testWidgets('View All 按钮存在', (tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: _buildOverrides()));
      await tester.pumpAndSettle();

      expect(find.text('View All'), findsOneWidget);
    });

    testWidgets('显示 Payment Account 区块标题', (tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: _buildOverrides()));
      await tester.pumpAndSettle();

      expect(find.text('Payment Account'), findsOneWidget);
    });
  });

  // -----------------------------------------------------------
  // 加载状态测试
  // -----------------------------------------------------------
  group('EarningsPage — 加载状态', () {
    testWidgets('summary 加载中时不显示金额数字', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        overrides: _buildOverrides(
          summary: const AsyncLoading(),
        ),
      ));
      await tester.pump(); // 不 pumpAndSettle，保持 loading

      // 加载中时 amount 为空，不应出现具体金额
      expect(find.text('\$1234.56'), findsNothing);
    });
  });

  // -----------------------------------------------------------
  // Stripe 状态测试
  // -----------------------------------------------------------
  group('EarningsPage — Stripe 连接状态', () {
    testWidgets('未连接时显示 Not Connected 警告', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        overrides: _buildOverrides(
          stripe: AsyncData(_mockStripeNotConnected()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Payment Account Not Connected'), findsOneWidget);
    });

    testWidgets('已连接时显示 Stripe Connected', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        overrides: _buildOverrides(
          stripe: AsyncData(_mockStripeConnected()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Stripe Connected'), findsOneWidget);
    });
  });

  // -----------------------------------------------------------
  // 月份选择器测试
  // -----------------------------------------------------------
  group('EarningsPage — 月份选择器', () {
    testWidgets('月份选择器包含当前月份文字', (tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: _buildOverrides()));
      await tester.pumpAndSettle();

      // 当前月应该出现（格式如 "March 2026"）
      final now = DateTime.now();
      final months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      final monthName = months[now.month - 1];
      expect(find.textContaining(monthName), findsAtLeastNWidgets(1));
    });

    testWidgets('Earnings Overview 区块标题存在', (tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: _buildOverrides()));
      await tester.pumpAndSettle();

      expect(find.text('Earnings Overview'), findsOneWidget);
    });
  });

  // -----------------------------------------------------------
  // 交易列表测试
  // -----------------------------------------------------------
  group('EarningsPage — 交易列表预览', () {
    testWidgets('近期交易显示订单短码', (tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: _buildOverrides()));
      await tester.pumpAndSettle();

      // 订单号 abc12345... 截断为 #ABC12345
      expect(find.text('#ABC12345'), findsOneWidget);
    });

    testWidgets('交易列表显示 Net 金额', (tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: _buildOverrides()));
      await tester.pumpAndSettle();

      // 第一条交易 netAmount = 42.50
      expect(find.textContaining('42.50'), findsAtLeastNWidgets(1));
    });

    testWidgets('无交易时显示空状态文字', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        overrides: _buildOverrides(
          transactions: AsyncData(PagedTransactions.empty()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No transactions yet'), findsOneWidget);
    });
  });
}
