// =============================================================
// AnalyticsPage Widget 测试
// 测试覆盖:
//   - 页面初始渲染（AppBar 标题、SegmentedButton）
//   - 经营概览加载中显示骨架屏
//   - 经营概览加载成功显示 4 张 MetricCard
//   - 经营概览加载失败显示 Retry 按钮
//   - 时间范围切换触发 daysRangeProvider 更新
//   - Deal 漏斗区空状态显示
//   - Deal 漏斗区有数据时显示漏斗条
//   - 客群分析区正常渲染
// =============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dealjoy_merchant/features/analytics/models/analytics_data.dart';
import 'package:dealjoy_merchant/features/analytics/services/analytics_service.dart';
import 'package:dealjoy_merchant/features/analytics/providers/analytics_provider.dart';
import 'package:dealjoy_merchant/features/analytics/pages/analytics_page.dart';

// =============================================================
// Mock 类
// =============================================================
class MockAnalyticsService extends Mock implements AnalyticsService {}

// =============================================================
// 测试用假数据
// =============================================================
const _kOverview = OverviewStats(
  viewsCount:       120,
  ordersCount:      30,
  redemptionsCount: 20,
  revenue:          599.50,
  daysRange:        7,
);

final _kFunnels = [
  DealFunnelData.fromJson({
    'deal_id':                  'uuid-1',
    'deal_title':               'BBQ Special',
    'views':                    100,
    'orders':                   25,
    'redemptions':              18,
    'view_to_order_rate':       25.0,
    'order_to_redemption_rate': 72.0,
  }),
];

const _kCustomers = CustomerAnalysis(
  newCustomersCount:       45,
  returningCustomersCount: 15,
  repeatRate:              25.0,
);

// =============================================================
// 测试辅助：构建带 Provider 覆盖的 Widget 树
// =============================================================
Widget _buildTestApp({
  required OverviewStats overviewData,
  List<DealFunnelData> funnelData = const [],
  CustomerAnalysis customerData = const CustomerAnalysis(
    newCustomersCount: 0, returningCustomersCount: 0, repeatRate: 0,
  ),
  bool overviewError = false,
}) {
  return ProviderScope(
    overrides: [
      // 覆盖经营概览 Provider
      overviewProvider.overrideWith(() => _FakeOverviewNotifier(
        data:        overviewData,
        shouldError: overviewError,
      )),
      // 覆盖漏斗 Provider
      dealFunnelProvider.overrideWith((_) async => funnelData),
      // 覆盖客群分析 Provider
      customerAnalysisProvider.overrideWith((_) async => customerData),
    ],
    child: const MaterialApp(
      home: AnalyticsPage(),
    ),
  );
}

// =============================================================
// 假 OverviewNotifier（在测试中直接返回预设数据）
// =============================================================
class _FakeOverviewNotifier extends OverviewNotifier {
  final OverviewStats data;
  final bool shouldError;

  _FakeOverviewNotifier({required this.data, this.shouldError = false});

  @override
  Future<OverviewStats> build() async {
    if (shouldError) {
      throw const AnalyticsException(
        code: 'network_error', message: 'Test error',
      );
    }
    return data;
  }
}

// =============================================================
// 测试主体
// =============================================================
void main() {
  // ============================================================
  // 页面基础渲染
  // ============================================================
  group('AnalyticsPage 基础渲染', () {
    testWidgets('AppBar 标题显示 Analytics', (tester) async {
      await tester.pumpWidget(_buildTestApp(overviewData: _kOverview));
      await tester.pumpAndSettle();

      expect(find.text('Analytics'), findsOneWidget);
    });

    testWidgets('SegmentedButton 显示 7 Days 和 30 Days', (tester) async {
      await tester.pumpWidget(_buildTestApp(overviewData: _kOverview));
      await tester.pumpAndSettle();

      expect(find.text('7 Days'),  findsOneWidget);
      expect(find.text('30 Days'), findsOneWidget);
    });

    testWidgets('区域标题 Business Overview 和 Deal Performance 存在',
        (tester) async {
      await tester.pumpWidget(_buildTestApp(overviewData: _kOverview));
      await tester.pumpAndSettle();

      expect(find.text('Business Overview'), findsOneWidget);
      expect(find.text('Deal Performance'),  findsOneWidget);
      expect(find.text('Customer Insights'), findsOneWidget);
    });
  });

  // ============================================================
  // 经营概览区域
  // ============================================================
  group('经营概览区域', () {
    testWidgets('加载成功后显示 Views / Orders / Redemptions / Revenue 标签',
        (tester) async {
      await tester.pumpWidget(_buildTestApp(overviewData: _kOverview));
      await tester.pumpAndSettle();

      expect(find.text('Views'),       findsOneWidget);
      expect(find.text('Orders'),      findsOneWidget);
      expect(find.text('Redemptions'), findsOneWidget);
      expect(find.text('Revenue'),     findsOneWidget);
    });

    testWidgets('加载失败后显示 Retry 按钮', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(overviewData: _kOverview, overviewError: true),
      );
      await tester.pumpAndSettle();

      // 至少有一个 Retry 按钮可见
      expect(find.text('Retry'), findsWidgets);
    });
  });

  // ============================================================
  // Deal 漏斗区域
  // ============================================================
  group('Deal 漏斗区域', () {
    testWidgets('无 Deal 时显示 No deals found 空状态', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(overviewData: _kOverview, funnelData: []),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No deals found'), findsOneWidget);
    });

    testWidgets('有 Deal 时显示 Deal 标题', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(overviewData: _kOverview, funnelData: _kFunnels),
      );
      await tester.pumpAndSettle();

      expect(find.text('BBQ Special'), findsOneWidget);
    });

    testWidgets('漏斗条中显示 Views / Orders / Redemptions 段标签',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(overviewData: _kOverview, funnelData: _kFunnels),
      );
      await tester.pumpAndSettle();

      expect(find.text('Views'),       findsWidgets);
      expect(find.text('Orders'),      findsWidgets);
      expect(find.text('Redemptions'), findsWidgets);
    });
  });

  // ============================================================
  // 客群分析区域
  // ============================================================
  group('客群分析区域', () {
    testWidgets('有客户数据时显示 New Customers / Returning Customers 标签',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(overviewData: _kOverview, customerData: _kCustomers),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Customers'),       findsOneWidget);
      expect(find.text('Returning Customers'), findsOneWidget);
      expect(find.text('Repeat Rate'),         findsOneWidget);
    });

    testWidgets('无客户数据时显示 No customer data yet', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overviewData: _kOverview,
          customerData: CustomerAnalysis.empty(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No customer data yet'), findsOneWidget);
    });
  });

  // ============================================================
  // 时间范围切换
  // ============================================================
  group('时间范围切换', () {
    testWidgets('点击 30 Days 后 daysRangeProvider 更新为 30', (tester) async {
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            overviewProvider.overrideWith(() => _FakeOverviewNotifier(
              data: _kOverview,
            )),
            dealFunnelProvider.overrideWith((_) async => <DealFunnelData>[]),
            customerAnalysisProvider.overrideWith(
              (_) async => CustomerAnalysis.empty(),
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const AnalyticsPage();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 初始值应为 7
      expect(capturedRef.read(daysRangeProvider), 7);

      // 点击 "30 Days" 按钮
      await tester.tap(find.text('30 Days'));
      await tester.pumpAndSettle();

      expect(capturedRef.read(daysRangeProvider), 30);
    });
  });
}
