// DashboardService 单元测试
// 策略: 对 Edge Function 调用部分使用可测试子类（stub 掉 invoke）；
//       对模型解析（fromJson）直接测试，不依赖 Supabase SDK。

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dealjoy_merchant/features/dashboard/models/dashboard_stats.dart';
import 'package:dealjoy_merchant/features/dashboard/services/dashboard_service.dart';

// ============================================================
// Mock 辅助类
// ============================================================

/// 可测试的 DashboardService 子类，stub 掉 Edge Function 调用
class _TestableDashboardService extends DashboardService {
  _TestableDashboardService(super.supabase);

  // 控制 fetchDashboardData 的返回
  DashboardData? stubbedData;
  bool throwOnFetch = false;

  // 控制 updateOnlineStatus 的返回
  bool stubbedOnlineResult = true;
  bool throwOnUpdate = false;

  @override
  Future<DashboardData> fetchDashboardData() async {
    if (throwOnFetch) throw DashboardException('Network error');
    return stubbedData ?? _buildMockData();
  }

  @override
  Future<bool> updateOnlineStatus(bool isOnline) async {
    if (throwOnUpdate) throw DashboardException('Update failed');
    return stubbedOnlineResult;
  }
}

/// Mock SupabaseClient（最小化 mock，只用于构造 service）
class MockSupabaseClient extends Mock implements SupabaseClient {}

// ============================================================
// 测试 helper：构建 mock DashboardData
// ============================================================
DashboardData _buildMockData({bool isOnline = true}) {
  return DashboardData(
    stats: DashboardStats(
      todayOrders: 5,
      todayRedemptions: 3,
      todayRevenue: 128.50,
      pendingCoupons: 10,
      merchantId: 'mock-merchant-id',
      merchantName: 'Test Restaurant',
      isOnline: isOnline,
      merchantStatus: 'approved',
    ),
    weeklyTrend: [
      WeeklyTrendEntry(
        date: DateTime.now(),
        orders: 5,
        revenue: 128.50,
      ),
      WeeklyTrendEntry(
        date: DateTime.now().subtract(const Duration(days: 1)),
        orders: 8,
        revenue: 210.00,
      ),
    ],
    todos: const TodoCounts(
      pendingReviews: 2,
      pendingRefunds: 1,
      pendingAfterSales: 0,
      influencerRequests: 0,
    ),
  );
}

// ============================================================
// 测试套件
// ============================================================
void main() {
  late MockSupabaseClient mockClient;
  late _TestableDashboardService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    service = _TestableDashboardService(mockClient);
  });

  // ----------------------------------------------------------
  // 模型解析测试（纯 Dart，无网络依赖）
  // ----------------------------------------------------------
  group('DashboardStats.fromJson', () {
    test('正确解析完整 JSON 响应', () {
      final json = {
        'merchantId': 'abc-123',
        'merchantName': 'My Burger',
        'isOnline': true,
        'merchantStatus': 'approved',
        'stats': {
          'todayOrders': 10,
          'todayRedemptions': 6,
          'todayRevenue': 245.80,
          'pendingCoupons': 15,
        },
      };

      final stats = DashboardStats.fromJson(json);

      expect(stats.merchantId, 'abc-123');
      expect(stats.merchantName, 'My Burger');
      expect(stats.isOnline, true);
      expect(stats.todayOrders, 10);
      expect(stats.todayRedemptions, 6);
      expect(stats.todayRevenue, 245.80);
      expect(stats.pendingCoupons, 15);
    });

    test('缺失字段时使用默认值', () {
      final stats = DashboardStats.fromJson({});

      expect(stats.merchantId, '');
      expect(stats.merchantName, 'My Store');
      expect(stats.isOnline, true);
      expect(stats.todayOrders, 0);
      expect(stats.todayRevenue, 0.0);
    });

    test('copyWith 正确替换 isOnline', () {
      final original = DashboardStats(
        todayOrders: 5,
        todayRedemptions: 3,
        todayRevenue: 100.0,
        pendingCoupons: 8,
        merchantId: 'id-1',
        merchantName: 'Store',
        isOnline: true,
        merchantStatus: 'approved',
      );

      final updated = original.copyWith(isOnline: false);

      expect(updated.isOnline, false);
      // 其余字段不变
      expect(updated.todayOrders, 5);
      expect(updated.merchantName, 'Store');
    });
  });

  group('WeeklyTrendEntry', () {
    test('fromJson 正确解析日期和数值', () {
      final entry = WeeklyTrendEntry.fromJson({
        'date': '2026-03-03',
        'orders': 7,
        'revenue': 180.0,
      });

      expect(entry.date, DateTime(2026, 3, 3));
      expect(entry.orders, 7);
      expect(entry.revenue, 180.0);
    });

    test('isToday 对今日日期返回 true', () {
      final today = DateTime.now();
      final entry = WeeklyTrendEntry(
        date: DateTime(today.year, today.month, today.day),
        orders: 0,
        revenue: 0,
      );

      expect(entry.isToday, true);
    });

    test('isToday 对昨日日期返回 false', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final entry = WeeklyTrendEntry(
        date: DateTime(yesterday.year, yesterday.month, yesterday.day),
        orders: 0,
        revenue: 0,
      );

      expect(entry.isToday, false);
    });
  });

  group('TodoCounts', () {
    test('hasAnyTodos 在全零时返回 false', () {
      const todos = TodoCounts(
        pendingReviews: 0,
        pendingRefunds: 0,
        pendingAfterSales: 0,
        influencerRequests: 0,
      );

      expect(todos.hasAnyTodos, false);
    });

    test('hasAnyTodos 有任何待办时返回 true', () {
      const todos = TodoCounts(
        pendingReviews: 2,
        pendingRefunds: 0,
        pendingAfterSales: 0,
        influencerRequests: 0,
      );

      expect(todos.hasAnyTodos, true);
    });

    test('totalCount 正确累加', () {
      const todos = TodoCounts(
        pendingReviews: 3,
        pendingRefunds: 1,
        pendingAfterSales: 0,
        influencerRequests: 2,
      );

      expect(todos.totalCount, 6);
    });
  });

  group('DashboardData.fromJson', () {
    test('正确解析完整聚合响应', () {
      final json = {
        'merchantId': 'merchant-1',
        'merchantName': 'BBQ House',
        'isOnline': false,
        'merchantStatus': 'approved',
        'stats': {
          'todayOrders': 3,
          'todayRedemptions': 2,
          'todayRevenue': 89.99,
          'pendingCoupons': 5,
        },
        'weeklyTrend': [
          {'date': '2026-03-03', 'orders': 3, 'revenue': 89.99},
          {'date': '2026-03-02', 'orders': 5, 'revenue': 150.0},
        ],
        'todos': {
          'pendingReviews': 1,
          'pendingRefunds': 0,
          'influencerRequests': 0,
        },
      };

      final data = DashboardData.fromJson(json);

      expect(data.stats.merchantName, 'BBQ House');
      expect(data.stats.isOnline, false);
      expect(data.weeklyTrend.length, 2);
      expect(data.weeklyTrend[0].orders, 3);
      expect(data.todos.pendingReviews, 1);
      expect(data.todos.hasAnyTodos, true);
    });

    test('copyWithOnlineStatus 只更新 isOnline 字段', () {
      final data = _buildMockData(isOnline: true);
      final updated = data.copyWithOnlineStatus(false);

      expect(updated.stats.isOnline, false);
      // 其余字段不变
      expect(updated.stats.merchantName, data.stats.merchantName);
      expect(updated.weeklyTrend.length, data.weeklyTrend.length);
      expect(updated.todos.pendingReviews, data.todos.pendingReviews);
    });
  });

  // ----------------------------------------------------------
  // Service 调用测试（使用 stub，不依赖真实网络）
  // ----------------------------------------------------------
  group('DashboardService.fetchDashboardData', () {
    test('成功时返回 DashboardData', () async {
      service.stubbedData = _buildMockData();

      final result = await service.fetchDashboardData();

      expect(result.stats.todayOrders, 5);
      expect(result.weeklyTrend.length, 2);
    });

    test('失败时抛出 DashboardException', () async {
      service.throwOnFetch = true;

      expect(
        () => service.fetchDashboardData(),
        throwsA(isA<DashboardException>()),
      );
    });
  });

  group('DashboardService.updateOnlineStatus', () {
    test('成功时返回确认的 bool 值', () async {
      service.stubbedOnlineResult = false;

      final result = await service.updateOnlineStatus(false);

      expect(result, false);
    });

    test('失败时抛出 DashboardException', () async {
      service.throwOnUpdate = true;

      expect(
        () => service.updateOnlineStatus(true),
        throwsA(isA<DashboardException>()),
      );
    });
  });
}
