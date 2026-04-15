// DashboardNotifier Provider 单元测试
// 策略: 使用 ProviderContainer 覆盖 dashboardServiceProvider，
//       注入 mock service，测试 Notifier 状态流转。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dealjoy_merchant/features/dashboard/models/dashboard_stats.dart';
import 'package:dealjoy_merchant/features/dashboard/providers/dashboard_provider.dart';
import 'package:dealjoy_merchant/features/dashboard/services/dashboard_service.dart';

// ============================================================
// Mock DashboardService
// ============================================================
class _MockDashboardService extends DashboardService {
  _MockDashboardService() : super(_noOpClient());

  // 模拟 fetchDashboardData 的行为
  DashboardData? stubbedData;
  bool throwOnFetch = false;
  int fetchCallCount = 0;

  // 模拟 updateOnlineStatus 的行为
  bool stubbedOnlineResult = true;
  bool throwOnUpdate = false;

  @override
  Future<DashboardData> fetchDashboardData() async {
    fetchCallCount++;
    if (throwOnFetch) throw DashboardException('Fetch failed');
    return stubbedData ?? _buildData();
  }

  @override
  Future<bool> updateOnlineStatus(bool isOnline) async {
    if (throwOnUpdate) throw DashboardException('Update failed');
    stubbedOnlineResult = isOnline;
    return isOnline;
  }

  // 无操作 Supabase client（占位，不实际调用）
  static dynamic _noOpClient() => null as dynamic;
}

// ============================================================
// 测试 helper
// ============================================================
DashboardData _buildData({bool isOnline = true, int todayOrders = 5}) {
  return DashboardData(
    stats: DashboardStats(
      todayOrders: todayOrders,
      todayRedemptions: 3,
      todayRevenue: 128.50,
      pendingCoupons: 10,
      merchantId: 'merchant-test-id',
      merchantName: 'Test Store',
      isOnline: isOnline,
      merchantStatus: 'approved',
    ),
    weeklyTrend: List.generate(
      7,
      (i) => WeeklyTrendEntry(
        date: DateTime.now().subtract(Duration(days: i)),
        orders: i + 1,
        revenue: (i + 1) * 20.0,
      ),
    ),
    todos: const TodoCounts(
      pendingReviews: 2,
      pendingRefunds: 0,
      pendingAfterSales: 0,
      influencerRequests: 0,
    ),
  );
}

// ============================================================
// 测试套件
// ============================================================
void main() {
  // ----------------------------------------------------------
  // 工具函数：创建测试用 ProviderContainer，注入 mock service
  // ----------------------------------------------------------
  ProviderContainer makeContainer(_MockDashboardService mockService) {
    return ProviderContainer(
      overrides: [
        dashboardServiceProvider.overrideWithValue(mockService),
      ],
    );
  }

  group('DashboardNotifier — 初始加载', () {
    test('build() 成功时 state 转为 AsyncData', () async {
      final mockService = _MockDashboardService()
        ..stubbedData = _buildData();
      final container = makeContainer(mockService);
      addTearDown(container.dispose);

      // 等待 AsyncNotifier 完成 build
      final result = await container.read(dashboardProvider.future);

      expect(result.stats.todayOrders, 5);
      expect(result.stats.merchantName, 'Test Store');
      expect(result.weeklyTrend.length, 7);
    });

    test('build() 失败时 state 转为 AsyncError', () async {
      final mockService = _MockDashboardService()..throwOnFetch = true;
      final container = makeContainer(mockService);
      addTearDown(container.dispose);

      // 等待 future 完成（会抛异常）
      await expectLater(
        container.read(dashboardProvider.future),
        throwsA(isA<DashboardException>()),
      );

      expect(container.read(dashboardProvider).hasError, true);
    });
  });

  group('DashboardNotifier — refresh()', () {
    test('refresh() 重新调用 fetch 并更新数据', () async {
      int callCount = 0;
      final mockService = _MockDashboardService();
      // 第一次返回 5 orders，第二次返回 9 orders
      mockService.stubbedData = _buildData(todayOrders: 5);

      final container = makeContainer(mockService);
      addTearDown(container.dispose);

      // 等待初始加载
      await container.read(dashboardProvider.future);
      expect(container.read(dashboardProvider).value?.stats.todayOrders, 5);

      // 更改 stub 数据后刷新
      mockService.stubbedData = _buildData(todayOrders: 9);
      callCount = mockService.fetchCallCount;

      await container.read(dashboardProvider.notifier).refresh();

      expect(mockService.fetchCallCount, callCount + 1);
      expect(container.read(dashboardProvider).value?.stats.todayOrders, 9);
    });
  });

  group('DashboardNotifier — toggleOnlineStatus()', () {
    test('成功时 state 中 isOnline 更新为 false', () async {
      final mockService = _MockDashboardService()
        ..stubbedData = _buildData(isOnline: true);
      final container = makeContainer(mockService);
      addTearDown(container.dispose);

      await container.read(dashboardProvider.future);

      // 切换为 offline
      await container.read(dashboardProvider.notifier).toggleOnlineStatus(false);

      final updatedState = container.read(dashboardProvider).value;
      expect(updatedState?.stats.isOnline, false);
    });

    test('失败时 storeOnlineProvider 回滚', () async {
      final mockService = _MockDashboardService()
        ..stubbedData = _buildData(isOnline: true)
        ..throwOnUpdate = true;
      final container = makeContainer(mockService);
      addTearDown(container.dispose);

      await container.read(dashboardProvider.future);

      // 乐观更新到 false
      bool threw = false;
      try {
        await container.read(dashboardProvider.notifier).toggleOnlineStatus(false);
      } catch (_) {
        threw = true;
      }

      expect(threw, true);
      // storeOnlineProvider 应回滚到 true
      expect(container.read(storeOnlineProvider), true);
    });

    test('成功时 storeOnlineProvider 同步更新', () async {
      final mockService = _MockDashboardService()
        ..stubbedData = _buildData(isOnline: true);
      final container = makeContainer(mockService);
      addTearDown(container.dispose);

      await container.read(dashboardProvider.future);

      await container.read(dashboardProvider.notifier).toggleOnlineStatus(false);

      expect(container.read(storeOnlineProvider), false);
    });
  });

  group('storeOnlineProvider — 初始值同步', () {
    test('从 dashboardProvider 同步初始 isOnline 值', () async {
      final mockService = _MockDashboardService()
        ..stubbedData = _buildData(isOnline: false);
      final container = makeContainer(mockService);
      addTearDown(container.dispose);

      // 等待 dashboard 加载
      await container.read(dashboardProvider.future);

      // storeOnlineProvider 应与 stats.isOnline 一致
      expect(container.read(storeOnlineProvider), false);
    });
  });
}
