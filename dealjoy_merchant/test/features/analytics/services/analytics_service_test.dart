// =============================================================
// AnalyticsService 单元测试
// 测试覆盖:
//   - fetchOverview: 正常响应、空数据、错误响应、网络异常
//   - fetchDealFunnel: 正常列表、空列表、异常
//   - fetchCustomerAnalysis: 正常响应、异常
//   - _parseResponse / _checkError: 边界条件
// =============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dealjoy_merchant/features/analytics/services/analytics_service.dart';

// =============================================================
// Mock 类定义
// =============================================================
class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockFunctionsClient extends Mock implements FunctionsClient {}

// =============================================================
// 测试用假数据工厂
// =============================================================

/// 创建经营概览 Mock 响应数据
Map<String, dynamic> _overviewJson({
  int days = 7,
  int views = 120,
  int orders = 30,
  int redemptions = 20,
  double revenue = 599.50,
}) =>
    {
      'days_range':        days,
      'views_count':       views,
      'orders_count':      orders,
      'redemptions_count': redemptions,
      'revenue':           revenue,
    };

/// 创建 Deal 漏斗 Mock 响应数据
Map<String, dynamic> _dealFunnelItemJson({
  String dealId    = 'deal-uuid-1',
  String dealTitle = 'BBQ Special',
  int views        = 100,
  int orders       = 25,
  int redemptions  = 18,
}) =>
    {
      'deal_id':                  dealId,
      'deal_title':               dealTitle,
      'views':                    views,
      'orders':                   orders,
      'redemptions':              redemptions,
      'view_to_order_rate':       25.0,
      'order_to_redemption_rate': 72.0,
    };

/// 创建客群分析 Mock 响应数据
Map<String, dynamic> _customerJson({
  int newCount       = 45,
  int returningCount = 15,
  double repeatRate  = 25.0,
}) =>
    {
      'new_customers_count':       newCount,
      'returning_customers_count': returningCount,
      'repeat_rate':               repeatRate,
    };

// =============================================================
// 测试主体
// =============================================================
void main() {
  late MockSupabaseClient mockSupabase;
  late MockFunctionsClient mockFunctions;
  late AnalyticsService service;

  setUp(() {
    mockSupabase  = MockSupabaseClient();
    mockFunctions = MockFunctionsClient();

    // 让 supabase.functions 返回 mock
    when(() => mockSupabase.functions).thenReturn(mockFunctions);

    service = AnalyticsService(mockSupabase);
  });

  // ============================================================
  // fetchOverview 测试组
  // ============================================================
  group('fetchOverview', () {
    test('正常响应 days=7 → 返回 OverviewStats', () async {
      // Arrange: mock Edge Function 成功响应
      when(() => mockFunctions.invoke(
        any(),
        method: any(named: 'method'),
      )).thenAnswer((_) async => FunctionResponse(
        data: _overviewJson(days: 7, views: 120, orders: 30),
        status: 200,
      ));

      // Act
      final result = await service.fetchOverview('merchant-id', daysRange: 7);

      // Assert
      expect(result.viewsCount,  120);
      expect(result.ordersCount, 30);
      expect(result.daysRange,   7);
    });

    test('正常响应 days=30 → daysRange 正确', () async {
      when(() => mockFunctions.invoke(
        any(),
        method: any(named: 'method'),
      )).thenAnswer((_) async => FunctionResponse(
        data: _overviewJson(days: 30, views: 500),
        status: 200,
      ));

      final result = await service.fetchOverview('merchant-id', daysRange: 30);

      expect(result.daysRange,   30);
      expect(result.viewsCount,  500);
    });

    test('非法 daysRange 回退为 7', () async {
      // 监听调用路径包含 days=7（非法的 99 应被修正为 7）
      when(() => mockFunctions.invoke(
        any(that: contains('days=7')),
        method: any(named: 'method'),
      )).thenAnswer((_) async => FunctionResponse(
        data: _overviewJson(days: 7),
        status: 200,
      ));

      // 传入非法值 99，期望服务自动回退为 7
      final result = await service.fetchOverview('merchant-id', daysRange: 99);

      expect(result.daysRange, 7);
    });

    test('响应含 error 字段 → 抛出 AnalyticsException', () async {
      when(() => mockFunctions.invoke(
        any(),
        method: any(named: 'method'),
      )).thenAnswer((_) async => FunctionResponse(
        data: {'error': 'unauthorized', 'message': 'Not authorized'},
        status: 200,
      ));

      expect(
        () => service.fetchOverview('merchant-id'),
        throwsA(isA<AnalyticsException>()
            .having((e) => e.code, 'code', 'unauthorized')),
      );
    });

    test('FunctionException → 抛出 AnalyticsException(network_error)', () async {
      when(() => mockFunctions.invoke(
        any(),
        method: any(named: 'method'),
      )).thenThrow(const FunctionException(status: 500, details: 'timeout'));

      expect(
        () => service.fetchOverview('merchant-id'),
        throwsA(isA<AnalyticsException>()
            .having((e) => e.code, 'code', 'network_error')),
      );
    });
  });

  // ============================================================
  // fetchDealFunnel 测试组
  // ============================================================
  group('fetchDealFunnel', () {
    test('正常响应 → 返回 List<DealFunnelData>', () async {
      when(() => mockFunctions.invoke(
        any(),
        method: any(named: 'method'),
      )).thenAnswer((_) async => FunctionResponse(
        data: {
          'data': [
            _dealFunnelItemJson(dealTitle: 'Deal A', views: 100, orders: 25),
            _dealFunnelItemJson(dealId: 'deal-2', dealTitle: 'Deal B', views: 50, orders: 10),
          ],
        },
        status: 200,
      ));

      final result = await service.fetchDealFunnel('merchant-id');

      expect(result.length,         2);
      expect(result[0].dealTitle,   'Deal A');
      expect(result[0].views,       100);
      expect(result[0].orders,      25);
      expect(result[1].dealTitle,   'Deal B');
    });

    test('空列表 → 返回空 List', () async {
      when(() => mockFunctions.invoke(
        any(),
        method: any(named: 'method'),
      )).thenAnswer((_) async => FunctionResponse(
        data: {'data': []},
        status: 200,
      ));

      final result = await service.fetchDealFunnel('merchant-id');
      expect(result, isEmpty);
    });

    test('FunctionException → 抛出 AnalyticsException', () async {
      when(() => mockFunctions.invoke(
        any(),
        method: any(named: 'method'),
      )).thenThrow(const FunctionException(status: 500, details: 'server error'));

      expect(
        () => service.fetchDealFunnel('merchant-id'),
        throwsA(isA<AnalyticsException>()),
      );
    });
  });

  // ============================================================
  // fetchCustomerAnalysis 测试组
  // ============================================================
  group('fetchCustomerAnalysis', () {
    test('正常响应 → 返回 CustomerAnalysis', () async {
      when(() => mockFunctions.invoke(
        any(),
        method: any(named: 'method'),
      )).thenAnswer((_) async => FunctionResponse(
        data: _customerJson(newCount: 45, returningCount: 15, repeatRate: 25.0),
        status: 200,
      ));

      final result = await service.fetchCustomerAnalysis('merchant-id');

      expect(result.newCustomersCount,       45);
      expect(result.returningCustomersCount, 15);
      expect(result.repeatRate,              25.0);
      expect(result.totalCustomers,          60);
    });

    test('全零响应 → totalCustomers = 0', () async {
      when(() => mockFunctions.invoke(
        any(),
        method: any(named: 'method'),
      )).thenAnswer((_) async => FunctionResponse(
        data: _customerJson(newCount: 0, returningCount: 0, repeatRate: 0),
        status: 200,
      ));

      final result = await service.fetchCustomerAnalysis('merchant-id');

      expect(result.totalCustomers, 0);
      expect(result.repeatRate,     0.0);
    });

    test('FunctionException → 抛出 AnalyticsException', () async {
      when(() => mockFunctions.invoke(
        any(),
        method: any(named: 'method'),
      )).thenThrow(const FunctionException(status: 500, details: null));

      expect(
        () => service.fetchCustomerAnalysis('merchant-id'),
        throwsA(isA<AnalyticsException>()),
      );
    });
  });
}
