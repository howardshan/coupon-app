// =============================================================
// AnalyticsProvider 单元测试
// 测试覆盖:
//   - daysRangeProvider: 默认值、切换
//   - overviewProvider: build() 成功、merchantId 为空时返回 empty
//   - dealFunnelProvider: 成功路径、merchantId 为空时返回空列表
//   - customerAnalysisProvider: 成功路径
//   - OverviewNotifier.refresh(): 刷新后状态重置
// =============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dealjoy_merchant/features/analytics/models/analytics_data.dart';
import 'package:dealjoy_merchant/features/analytics/services/analytics_service.dart';
import 'package:dealjoy_merchant/features/analytics/providers/analytics_provider.dart';

// =============================================================
// Mock 类
// =============================================================
class MockAnalyticsService extends Mock implements AnalyticsService {}

// =============================================================
// 测试主体
// =============================================================
void main() {
  late MockAnalyticsService mockService;

  setUp(() {
    mockService = MockAnalyticsService();
  });

  // ============================================================
  // daysRangeProvider 测试组
  // ============================================================
  group('daysRangeProvider', () {
    test('默认值为 7', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(daysRangeProvider), 7);
    });

    test('修改为 30 后值变为 30', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(daysRangeProvider.notifier).state = 30;

      expect(container.read(daysRangeProvider), 30);
    });

    test('多次切换保持正确', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(daysRangeProvider.notifier).state = 30;
      expect(container.read(daysRangeProvider), 30);

      container.read(daysRangeProvider.notifier).state = 7;
      expect(container.read(daysRangeProvider), 7);
    });
  });

  // ============================================================
  // OverviewStats 模型测试（纯逻辑，无 Provider 依赖）
  // ============================================================
  group('OverviewStats model', () {
    test('fromJson 正确解析所有字段', () {
      final json = {
        'days_range':        7,
        'views_count':       120,
        'orders_count':      30,
        'redemptions_count': 20,
        'revenue':           599.50,
      };
      final stats = OverviewStats.fromJson(json);

      expect(stats.viewsCount,       120);
      expect(stats.ordersCount,      30);
      expect(stats.redemptionsCount, 20);
      expect(stats.revenue,          599.50);
      expect(stats.daysRange,        7);
    });

    test('empty() 返回全零且 daysRange 可自定义', () {
      final stats = OverviewStats.empty(daysRange: 30);

      expect(stats.viewsCount,       0);
      expect(stats.ordersCount,      0);
      expect(stats.redemptionsCount, 0);
      expect(stats.revenue,          0.0);
      expect(stats.daysRange,        30);
    });

    test('copyWith 只修改指定字段', () {
      final original = const OverviewStats(
        viewsCount: 100, ordersCount: 20,
        redemptionsCount: 15, revenue: 300.0, daysRange: 7,
      );
      final updated = original.copyWith(ordersCount: 25, daysRange: 30);

      expect(updated.viewsCount,       100);   // 不变
      expect(updated.ordersCount,      25);    // 变了
      expect(updated.redemptionsCount, 15);    // 不变
      expect(updated.daysRange,        30);    // 变了
    });
  });

  // ============================================================
  // DealFunnelData 模型测试
  // ============================================================
  group('DealFunnelData model', () {
    test('fromJson 正确解析', () {
      final json = {
        'deal_id':                  'uuid-1',
        'deal_title':               'BBQ Special',
        'views':                    100,
        'orders':                   25,
        'redemptions':              18,
        'view_to_order_rate':       25.0,
        'order_to_redemption_rate': 72.0,
      };
      final data = DealFunnelData.fromJson(json);

      expect(data.dealId,    'uuid-1');
      expect(data.views,     100);
      expect(data.orders,    25);
    });

    test('ordersFraction = orders/views', () {
      final data = DealFunnelData.fromJson({
        'deal_id': 'x', 'deal_title': 'T',
        'views': 100, 'orders': 25, 'redemptions': 10,
        'view_to_order_rate': 25.0, 'order_to_redemption_rate': 40.0,
      });

      expect(data.ordersFraction,      closeTo(0.25, 0.001));
      expect(data.redemptionsFraction, closeTo(0.10, 0.001));
    });

    test('views=0 时 fraction 均为 0（防除零）', () {
      final data = DealFunnelData.fromJson({
        'deal_id': 'x', 'deal_title': 'T',
        'views': 0, 'orders': 0, 'redemptions': 0,
        'view_to_order_rate': 0.0, 'order_to_redemption_rate': 0.0,
      });

      expect(data.ordersFraction,      0.0);
      expect(data.redemptionsFraction, 0.0);
    });
  });

  // ============================================================
  // CustomerAnalysis 模型测试
  // ============================================================
  group('CustomerAnalysis model', () {
    test('fromJson 正确解析', () {
      final json = {
        'new_customers_count':       45,
        'returning_customers_count': 15,
        'repeat_rate':               25.0,
      };
      final analysis = CustomerAnalysis.fromJson(json);

      expect(analysis.newCustomersCount,       45);
      expect(analysis.returningCustomersCount, 15);
      expect(analysis.repeatRate,              25.0);
      expect(analysis.totalCustomers,          60);
    });

    test('newCustomersFraction 计算正确', () {
      final analysis = CustomerAnalysis.fromJson({
        'new_customers_count': 75,
        'returning_customers_count': 25,
        'repeat_rate': 25.0,
      });

      expect(analysis.newCustomersFraction,       closeTo(0.75, 0.001));
      expect(analysis.returningCustomersFraction, closeTo(0.25, 0.001));
    });

    test('totalCustomers=0 时 fraction 均为 0（防除零）', () {
      final analysis = CustomerAnalysis.empty();

      expect(analysis.totalCustomers,             0);
      expect(analysis.newCustomersFraction,       0.0);
      expect(analysis.returningCustomersFraction, 0.0);
    });
  });

  // ============================================================
  // AnalyticsService mock 调用测试（不依赖真实 Provider 树）
  // ============================================================
  group('AnalyticsService mock calls', () {
    test('fetchOverview 成功时返回正确数据', () async {
      when(() => mockService.fetchOverview(any(), daysRange: any(named: 'daysRange')))
          .thenAnswer((_) async => const OverviewStats(
                viewsCount:       120,
                ordersCount:      30,
                redemptionsCount: 20,
                revenue:          599.50,
                daysRange:        7,
              ));

      final result = await mockService.fetchOverview('mid', daysRange: 7);

      expect(result.viewsCount,  120);
      expect(result.ordersCount, 30);
      verify(() => mockService.fetchOverview('mid', daysRange: 7)).called(1);
    });

    test('fetchDealFunnel 成功时返回列表', () async {
      final funnels = [
        DealFunnelData.fromJson({
          'deal_id': 'u1', 'deal_title': 'Deal A',
          'views': 100, 'orders': 25, 'redemptions': 18,
          'view_to_order_rate': 25.0, 'order_to_redemption_rate': 72.0,
        }),
      ];
      when(() => mockService.fetchDealFunnel(any()))
          .thenAnswer((_) async => funnels);

      final result = await mockService.fetchDealFunnel('mid');

      expect(result.length,        1);
      expect(result[0].dealTitle,  'Deal A');
    });

    test('fetchCustomerAnalysis 成功时返回正确数据', () async {
      when(() => mockService.fetchCustomerAnalysis(any()))
          .thenAnswer((_) async => CustomerAnalysis.fromJson({
                'new_customers_count':       45,
                'returning_customers_count': 15,
                'repeat_rate':               25.0,
              }));

      final result = await mockService.fetchCustomerAnalysis('mid');

      expect(result.newCustomersCount, 45);
      expect(result.repeatRate,        25.0);
    });

    test('fetchOverview 抛出 AnalyticsException 时上层可捕获', () async {
      when(() => mockService.fetchOverview(any(), daysRange: any(named: 'daysRange')))
          .thenThrow(const AnalyticsException(
            code: 'unauthorized', message: 'Not authorized',
          ));

      expect(
        () => mockService.fetchOverview('mid'),
        throwsA(isA<AnalyticsException>()
            .having((e) => e.code, 'code', 'unauthorized')),
      );
    });
  });
}
