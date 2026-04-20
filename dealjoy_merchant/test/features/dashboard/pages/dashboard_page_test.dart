// DashboardPage Widget 测试
// 策略: 使用 ProviderContainer overrides 注入 mock 数据，
//       验证 UI 各区块的渲染和交互行为。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dealjoy_merchant/features/dashboard/models/dashboard_stats.dart';
import 'package:dealjoy_merchant/features/dashboard/pages/dashboard_page.dart';
import 'package:dealjoy_merchant/features/dashboard/providers/dashboard_provider.dart';
import 'package:dealjoy_merchant/features/dashboard/services/dashboard_service.dart';

// ============================================================
// Mock DashboardService（同 provider 测试中相同策略）
// ============================================================
class MockDashboardService extends DashboardService {
  MockDashboardService() : super(null as dynamic);

  DashboardData? stubbedData;
  bool throwOnFetch = false;
  bool throwOnUpdate = false;
  bool stubbedOnlineResult = true;

  @override
  Future<DashboardData> fetchDashboardData() async {
    if (throwOnFetch) throw DashboardException('Network error');
    return stubbedData ?? _buildData();
  }

  @override
  Future<bool> updateOnlineStatus(bool isOnline) async {
    if (throwOnUpdate) throw DashboardException('Update failed');
    stubbedOnlineResult = isOnline;
    return isOnline;
  }
}

// ============================================================
// 测试 helper：构建标准 DashboardData
// ============================================================
DashboardData _buildData({
  bool isOnline = true,
  bool hasTodos = false,
}) {
  return DashboardData(
    stats: DashboardStats(
      todayOrders: 5,
      todayRedemptions: 3,
      todayRevenue: 128.50,
      pendingCoupons: 10,
      merchantId: 'merchant-1',
      merchantName: 'Texas BBQ House',
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
    todos: TodoCounts(
      pendingReviews: hasTodos ? 2 : 0,
      pendingRefunds: hasTodos ? 1 : 0,
      pendingAfterSales: 0,
      influencerRequests: 0,
    ),
  );
}

// ============================================================
// 测试脚手架：包装 MaterialApp + GoRouter + ProviderScope
// ============================================================
Widget buildTestApp({
  required MockDashboardService mockService,
  String initialLocation = '/dashboard',
}) {
  // 最简 GoRouter，只注册 /dashboard 路由
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/dashboard',
        builder: (ctx, st) => const DashboardPage(),
      ),
      // stub 路由（快捷入口跳转目标）
      GoRoute(path: '/scan',      builder: (ctx, st) => const Scaffold(body: Text('Scan'))),
      GoRoute(path: '/deals',     builder: (ctx, st) => const Scaffold(body: Text('Deals'))),
      GoRoute(path: '/orders',    builder: (ctx, st) => const Scaffold(body: Text('Orders'))),
      GoRoute(path: '/reviews',   builder: (ctx, st) => const Scaffold(body: Text('Reviews'))),
      GoRoute(path: '/analytics', builder: (ctx, st) => const Scaffold(body: Text('Analytics'))),
      GoRoute(path: '/me',        builder: (ctx, st) => const Scaffold(body: Text('Me'))),
    ],
  );

  return ProviderScope(
    overrides: [
      dashboardServiceProvider.overrideWithValue(mockService),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ============================================================
// 测试套件
// ============================================================
void main() {
  // ----------------------------------------------------------
  // 正常数据渲染测试
  // ----------------------------------------------------------
  group('DashboardPage — 正常数据渲染', () {
    testWidgets('显示商家名称', (tester) async {
      final mockService = MockDashboardService()
        ..stubbedData = _buildData();

      await tester.pumpWidget(buildTestApp(mockService: mockService));
      await tester.pumpAndSettle(); // 等待 AsyncNotifier build 完成

      expect(find.text('Texas BBQ House'), findsOneWidget);
    });

    testWidgets('显示 4 个数据卡片标题', (tester) async {
      final mockService = MockDashboardService()
        ..stubbedData = _buildData();

      await tester.pumpWidget(buildTestApp(mockService: mockService));
      await tester.pumpAndSettle();

      expect(find.text('Today Orders'), findsOneWidget);
      expect(find.text('Redeemed'),     findsOneWidget);
      expect(find.text('Revenue'),      findsOneWidget);
      expect(find.text('Pending'),      findsOneWidget);
    });

    testWidgets('显示今日订单数值', (tester) async {
      final mockService = MockDashboardService()
        ..stubbedData = _buildData();

      await tester.pumpWidget(buildTestApp(mockService: mockService));
      await tester.pumpAndSettle();

      // todayOrders = 5
      expect(find.text('5'), findsWidgets); // 可能多处出现（orders + 趋势）
    });

    testWidgets('显示收入格式化为美元', (tester) async {
      final mockService = MockDashboardService()
        ..stubbedData = _buildData();

      await tester.pumpWidget(buildTestApp(mockService: mockService));
      await tester.pumpAndSettle();

      // todayRevenue = 128.50
      expect(find.text('\$128.50'), findsOneWidget);
    });

    testWidgets('显示 7 天趋势区块标题', (tester) async {
      final mockService = MockDashboardService()
        ..stubbedData = _buildData();

      await tester.pumpWidget(buildTestApp(mockService: mockService));
      await tester.pumpAndSettle();

      expect(find.text('7-Day Trend'), findsOneWidget);
    });

    testWidgets('显示趋势表头列名', (tester) async {
      final mockService = MockDashboardService()
        ..stubbedData = _buildData();

      await tester.pumpWidget(buildTestApp(mockService: mockService));
      await tester.pumpAndSettle();

      expect(find.text('Date'),    findsOneWidget);
      expect(find.text('Orders'),  findsOneWidget);
      expect(find.text('Revenue'), findsOneWidget);
    });
  });

  // ----------------------------------------------------------
  // 在线状态开关测试
  // ----------------------------------------------------------
  group('DashboardPage — 在线状态开关', () {
    testWidgets('门店在线时 Switch 为开启状态', (tester) async {
      final mockService = MockDashboardService()
        ..stubbedData = _buildData(isOnline: true);

      await tester.pumpWidget(buildTestApp(mockService: mockService));
      await tester.pumpAndSettle();

      // 找到 Switch 并验证 value = true
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      final switchWidget = tester.widget<Switch>(switchFinder);
      expect(switchWidget.value, true);
    });

    testWidgets('门店下线时 Switch 为关闭状态且显示 Offline', (tester) async {
      final mockService = MockDashboardService()
        ..stubbedData = _buildData(isOnline: false);

      await tester.pumpWidget(buildTestApp(mockService: mockService));
      await tester.pumpAndSettle();

      expect(find.text('Offline'), findsOneWidget);
      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, false);
    });

    testWidgets('切换开关后显示成功 SnackBar', (tester) async {
      final mockService = MockDashboardService()
        ..stubbedData = _buildData(isOnline: true);

      await tester.pumpWidget(buildTestApp(mockService: mockService));
      await tester.pumpAndSettle();

      // 点击 Switch
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // 验证 SnackBar 出现
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Store is now offline'), findsOneWidget);
    });
  });

  // ----------------------------------------------------------
  // 待办区块测试
  // ----------------------------------------------------------
  group('DashboardPage — 待办区块', () {
    testWidgets('无待办时不显示 Action Required 区块', (tester) async {
      final mockService = MockDashboardService()
        ..stubbedData = _buildData(hasTodos: false);

      await tester.pumpWidget(buildTestApp(mockService: mockService));
      await tester.pumpAndSettle();

      expect(find.text('Action Required'), findsNothing);
    });

    testWidgets('有待办时显示 Action Required 区块', (tester) async {
      final mockService = MockDashboardService()
        ..stubbedData = _buildData(hasTodos: true);

      await tester.pumpWidget(buildTestApp(mockService: mockService));
      await tester.pumpAndSettle();

      expect(find.text('Action Required'), findsOneWidget);
      // 待回复评价 (pendingReviews = 2)；pendingRefunds 待办入口已统一为 After-sales 列表
      expect(find.text('Reviews to reply'), findsOneWidget);
      expect(find.text('After-sales'), findsOneWidget);
    });
  });

  // ----------------------------------------------------------
  // 错误状态测试
  // ----------------------------------------------------------
  group('DashboardPage — 错误状态', () {
    testWidgets('加载失败时显示 Retry 按钮', (tester) async {
      final mockService = MockDashboardService()..throwOnFetch = true;

      await tester.pumpWidget(buildTestApp(mockService: mockService));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load dashboard'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('点击 Retry 后重新发起请求', (tester) async {
      final mockService = MockDashboardService()..throwOnFetch = true;

      await tester.pumpWidget(buildTestApp(mockService: mockService));
      await tester.pumpAndSettle();

      // 修改 stub，第二次成功
      mockService.throwOnFetch = false;
      mockService.stubbedData = _buildData();

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // 数据加载成功，商家名显示
      expect(find.text('Texas BBQ House'), findsOneWidget);
    });
  });

  // ----------------------------------------------------------
  // 快捷入口导航测试
  // ----------------------------------------------------------
  group('DashboardPage — 快捷入口导航', () {
    testWidgets('显示 6 个快捷入口标签', (tester) async {
      final mockService = MockDashboardService()
        ..stubbedData = _buildData();

      await tester.pumpWidget(buildTestApp(mockService: mockService));
      await tester.pumpAndSettle();

      expect(find.text('Redeem'),    findsOneWidget);
      expect(find.text('Deals'),     findsOneWidget);
      expect(find.text('Orders'),    findsOneWidget); // AppBar 里无 Orders 文字，只在 grid
      expect(find.text('Reviews'),   findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);
      expect(find.text('Settings'),  findsOneWidget);
    });

    testWidgets('点击 Redeem 跳转到 /scan（显示 Scan 页面）', (tester) async {
      final mockService = MockDashboardService()
        ..stubbedData = _buildData();

      await tester.pumpWidget(buildTestApp(mockService: mockService));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Redeem'));
      await tester.pumpAndSettle();

      expect(find.text('Scan'), findsOneWidget);
    });
  });
}
