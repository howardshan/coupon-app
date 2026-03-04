// StoreProfilePage Widget 测试
// 验证各区块的渲染、Edit 按钮存在性、加载/错误状态

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dealjoy_merchant/features/store/models/store_info.dart';
import 'package:dealjoy_merchant/features/store/pages/store_profile_page.dart';
import 'package:dealjoy_merchant/features/store/providers/store_provider.dart';
import 'package:dealjoy_merchant/features/store/services/store_service.dart';

// ============================================================
// Mock 类
// ============================================================
class MockStoreService extends Mock implements StoreService {}

// 用于 go_router 的空路由（测试不需要真实导航）
final _testRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const StoreProfilePage()),
    GoRoute(path: '/store/edit', builder: (_, _) => const Scaffold(body: Text('Edit Page'))),
    GoRoute(path: '/store/photos', builder: (_, _) => const Scaffold(body: Text('Photos Page'))),
    GoRoute(path: '/store/hours', builder: (_, _) => const Scaffold(body: Text('Hours Page'))),
    GoRoute(path: '/store/tags', builder: (_, _) => const Scaffold(body: Text('Tags Page'))),
  ],
);

// 测试用门店数据
StoreInfo _makeApprovedStore() {
  return StoreInfo(
    id: 'merchant-001',
    name: 'Texas BBQ House',
    description: 'Best BBQ in Dallas',
    phone: '(214) 555-0100',
    address: '123 Main St, Dallas, TX 75201',
    category: 'Restaurant',
    tags: const ['WiFi', 'Parking'],
    isOnline: true,
    status: 'approved',
    photos: [
      StorePhoto(
        id: 'photo-001',
        url: 'https://example.com/storefront.jpg',
        type: StorePhotoType.storefront,
        sortOrder: 0,
        createdAt: DateTime(2026, 3, 1),
      ),
    ],
    hours: const [
      BusinessHours(
        dayOfWeek: 1,
        openTime: '10:00',
        closeTime: '22:00',
        isClosed: false,
      ),
      BusinessHours(
        dayOfWeek: 0,
        openTime: null,
        closeTime: null,
        isClosed: true,
      ),
    ],
  );
}

// ============================================================
// 测试用 Widget 包装器（注入 ProviderContainer + GoRouter）
// ============================================================
Widget _buildTestWidget({
  required AsyncValue<StoreInfo> storeState,
}) {
  final mockService = MockStoreService();

  // 根据 storeState 决定 mock 行为
  if (storeState is AsyncData<StoreInfo>) {
    when(() => mockService.fetchStoreInfo())
        .thenAnswer((_) async => storeState.value);
  } else if (storeState is AsyncError) {
    when(() => mockService.fetchStoreInfo())
        .thenThrow(storeState.error!);
  }
  // AsyncLoading: fetchStoreInfo 永远不完成（模拟加载中）
  if (storeState is AsyncLoading) {
    when(() => mockService.fetchStoreInfo())
        .thenAnswer((_) => Future.delayed(const Duration(days: 999)));
  }

  return ProviderScope(
    overrides: [
      storeServiceProvider.overrideWithValue(mockService),
    ],
    child: MaterialApp.router(
      routerConfig: _testRouter,
    ),
  );
}

void main() {
  // ============================================================
  // 加载状态
  // ============================================================
  group('StoreProfilePage — loading state', () {
    testWidgets('显示加载骨架时不渲染门店内容', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(storeState: const AsyncLoading()),
      );
      await tester.pump(); // 触发第一帧

      // 加载中不应显示 "Basic Info"
      expect(find.text('Basic Info'), findsNothing);
    });
  });

  // ============================================================
  // 正常数据状态
  // ============================================================
  group('StoreProfilePage — data state', () {
    testWidgets('显示 4 个区块标题', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(storeState: AsyncData(_makeApprovedStore())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Basic Info'), findsOneWidget);
      expect(find.text('Store Photos'), findsOneWidget);
      expect(find.text('Business Hours'), findsOneWidget);
      expect(find.text('Category & Tags'), findsOneWidget);
    });

    testWidgets('显示门店名称', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(storeState: AsyncData(_makeApprovedStore())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Texas BBQ House'), findsOneWidget);
    });

    testWidgets('显示 4 个 Edit 按钮', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(storeState: AsyncData(_makeApprovedStore())),
      );
      await tester.pumpAndSettle();

      // 每个区块都有一个 Edit TextButton
      expect(find.text('Edit'), findsNWidgets(4));
    });

    testWidgets('显示营业时间（Monday + Sunday Closed）', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(storeState: AsyncData(_makeApprovedStore())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('Sunday'), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
    });

    testWidgets('显示标签 WiFi 和 Parking', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(storeState: AsyncData(_makeApprovedStore())),
      );
      await tester.pumpAndSettle();

      expect(find.text('WiFi'), findsOneWidget);
      expect(find.text('Parking'), findsOneWidget);
    });

    testWidgets('approved 状态时不显示 StatusBanner', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(storeState: AsyncData(_makeApprovedStore())),
      );
      await tester.pumpAndSettle();

      // approved 时不显示审核横幅关键词
      expect(find.text('under review'), findsNothing);
      expect(find.text('rejected'), findsNothing);
    });

    testWidgets('pending 状态显示 StatusBanner', (tester) async {
      final pendingStore = _makeApprovedStore().copyWith(status: 'pending');

      await tester.pumpWidget(
        _buildTestWidget(storeState: AsyncData(pendingStore)),
      );
      await tester.pumpAndSettle();

      // pending 横幅包含 "under review" 文字
      expect(
        find.textContaining('under review'),
        findsOneWidget,
      );
    });
  });

  // ============================================================
  // 错误状态
  // ============================================================
  group('StoreProfilePage — error state', () {
    testWidgets('显示错误视图和 Retry 按钮', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          storeState: AsyncError(
            Exception('Network error'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Failed to load store info'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  // ============================================================
  // AppBar
  // ============================================================
  group('StoreProfilePage — AppBar', () {
    testWidgets('AppBar 标题为 Store Profile', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(storeState: AsyncData(_makeApprovedStore())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Store Profile'), findsOneWidget);
    });

    testWidgets('AppBar 有刷新按钮', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(storeState: AsyncData(_makeApprovedStore())),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    });
  });
}
