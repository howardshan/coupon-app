// DealsListPage Widget 测试
// 验证 Tab 渲染、DealCard 列表、loading/error/empty 状态、FAB 按钮

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dealjoy_merchant/features/deals/models/merchant_deal.dart';
import 'package:dealjoy_merchant/features/deals/pages/deals_list_page.dart';
import 'package:dealjoy_merchant/features/deals/providers/deals_provider.dart';
import 'package:dealjoy_merchant/features/deals/services/deals_service.dart';

// ============================================================
// Mock 类
// ============================================================
class MockDealsService extends Mock implements DealsService {}

// 测试路由（避免 GoRouter 依赖真实导航）
final _testRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const DealsListPage(),
    ),
    GoRoute(
      path: '/deals/create',
      builder: (_, _) => const Scaffold(body: Text('Create Deal Page')),
    ),
    GoRoute(
      path: '/deals/:id',
      builder: (_, _) => const Scaffold(body: Text('Deal Detail Page')),
    ),
  ],
);

/// 构造测试用 MerchantDeal
MerchantDeal _makeDeal({
  String id = 'deal-001',
  String title = 'Test Deal',
  DealStatus status = DealStatus.active,
}) {
  return MerchantDeal(
    id:              id,
    merchantId:      'merchant-001',
    title:           title,
    description:     'A test deal',
    category:        'Restaurant',
    originalPrice:   49.99,
    discountPrice:   29.99,
    stockLimit:      50,
    totalSold:       5,
    rating:          4.0,
    reviewCount:     3,
    isActive:        status == DealStatus.active,
    dealStatus:      status,
    validityType:    ValidityType.fixedDate,
    expiresAt:       DateTime(2026, 12, 31),
    usageDays:       const [],
    isStackable:     true,
    images:          const [],
    createdAt:       DateTime(2026, 3, 1),
    updatedAt:       DateTime(2026, 3, 1),
  );
}

/// 构造测试 Widget（注入 ProviderContainer + GoRouter）
Widget _buildTestWidget(AsyncValue<List<MerchantDeal>> dealsState) {
  final mockService = MockDealsService();

  return ProviderScope(
    overrides: [
      dealsServiceProvider.overrideWithValue(mockService),
      dealsProvider.overrideWith(
        () => _TestDealsNotifier(dealsState),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: _testRouter,
    ),
  );
}

void main() {
  // ============================================================
  // AppBar 和 Tab 渲染
  // ============================================================
  group('DealsListPage — AppBar & Tabs', () {
    testWidgets('显示 4 个 Tab: All/Active/Inactive/Pending', (tester) async {
      await tester.pumpWidget(_buildTestWidget(const AsyncData([])));
      await tester.pumpAndSettle();

      expect(find.text('All'),      findsOneWidget);
      expect(find.text('Active'),   findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('Pending'),  findsOneWidget);
    });

    testWidgets('AppBar 标题为 My Deals', (tester) async {
      await tester.pumpWidget(_buildTestWidget(const AsyncData([])));
      await tester.pumpAndSettle();

      expect(find.text('My Deals'), findsOneWidget);
    });

    testWidgets('显示刷新图标按钮', (tester) async {
      await tester.pumpWidget(_buildTestWidget(const AsyncData([])));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    });
  });

  // ============================================================
  // FAB 按钮
  // ============================================================
  group('DealsListPage — FAB', () {
    testWidgets('显示 Create Deal FAB 按钮', (tester) async {
      await tester.pumpWidget(_buildTestWidget(const AsyncData([])));
      await tester.pumpAndSettle();

      expect(find.text('Create Deal'),    findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });
  });

  // ============================================================
  // 空状态（All Tab）
  // ============================================================
  group('DealsListPage — empty state (All Tab)', () {
    testWidgets('无 Deal 时显示空状态文案和创建按钮', (tester) async {
      await tester.pumpWidget(_buildTestWidget(const AsyncData([])));
      await tester.pumpAndSettle();

      expect(find.text('No Deals Yet'),          findsOneWidget);
      expect(find.text('Create Your First Deal'), findsOneWidget);
    });
  });

  // ============================================================
  // 数据列表渲染
  // ============================================================
  group('DealsListPage — data state', () {
    testWidgets('All Tab 显示所有 Deal 标题', (tester) async {
      final deals = [
        _makeDeal(id: '1', title: 'BBQ Set',      status: DealStatus.active),
        _makeDeal(id: '2', title: 'Hot Pot Deal',  status: DealStatus.inactive),
        _makeDeal(id: '3', title: 'Sushi Combo',   status: DealStatus.pending),
      ];

      await tester.pumpWidget(_buildTestWidget(AsyncData(deals)));
      await tester.pumpAndSettle();

      expect(find.text('BBQ Set'),      findsOneWidget);
      expect(find.text('Hot Pot Deal'), findsOneWidget);
      expect(find.text('Sushi Combo'),  findsOneWidget);
    });

    testWidgets('Active Tab 仅显示 active 状态 Deal', (tester) async {
      final deals = [
        _makeDeal(id: '1', title: 'Active Deal',   status: DealStatus.active),
        _makeDeal(id: '2', title: 'Inactive Deal',  status: DealStatus.inactive),
      ];

      await tester.pumpWidget(_buildTestWidget(AsyncData(deals)));
      await tester.pumpAndSettle();

      // 切换到 Active Tab
      await tester.tap(find.text('Active'));
      await tester.pumpAndSettle();

      expect(find.text('Active Deal'),   findsOneWidget);
      expect(find.text('Inactive Deal'), findsNothing);
    });

    testWidgets('Inactive Tab 无数据时显示 No Inactive Deals', (tester) async {
      final deals = [
        _makeDeal(id: '1', status: DealStatus.active),
      ];

      await tester.pumpWidget(_buildTestWidget(AsyncData(deals)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inactive'));
      await tester.pumpAndSettle();

      expect(find.text('No Inactive Deals'), findsOneWidget);
    });

    testWidgets('Pending Tab 仅显示 pending 状态 Deal', (tester) async {
      final deals = [
        _makeDeal(id: '1', title: 'Pending BBQ',   status: DealStatus.pending),
        _makeDeal(id: '2', title: 'Active Sushi',  status: DealStatus.active),
      ];

      await tester.pumpWidget(_buildTestWidget(AsyncData(deals)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pending'));
      await tester.pumpAndSettle();

      expect(find.text('Pending BBQ'),  findsOneWidget);
      expect(find.text('Active Sushi'), findsNothing);
    });
  });

  // ============================================================
  // 加载状态
  // ============================================================
  group('DealsListPage — loading state', () {
    testWidgets('加载中不显示 Deal 标题，AppBar 仍存在', (tester) async {
      await tester.pumpWidget(_buildTestWidget(const AsyncLoading()));
      await tester.pump(); // 仅渲染第一帧，不等待

      expect(find.text('BBQ Set'),  findsNothing);
      expect(find.text('My Deals'), findsOneWidget);
    });
  });

  // ============================================================
  // 错误状态
  // ============================================================
  group('DealsListPage — error state', () {
    testWidgets('错误时显示 Failed to load deals 和 Retry 按钮', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          AsyncError(Exception('Network error'), StackTrace.empty),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Failed to load deals'), findsOneWidget);
      expect(find.text('Retry'),                findsOneWidget);
    });
  });
}

// ============================================================
// 测试用 DealsNotifier（接受预注入的 AsyncValue 状态，跳过真实 Supabase auth）
// ============================================================
class _TestDealsNotifier extends DealsNotifier {
  _TestDealsNotifier(this._stateOverride);

  final AsyncValue<List<MerchantDeal>> _stateOverride;

  @override
  Future<List<MerchantDeal>> build() async {
    if (_stateOverride case AsyncData(:final value)) {
      return value;
    }
    if (_stateOverride case AsyncError(:final error)) {
      throw error;
    }
    // AsyncLoading: 永远不 resolve（模拟加载中）
    await Future.delayed(const Duration(days: 999));
    return [];
  }

  @override
  String get merchantId => 'merchant-001';
}
