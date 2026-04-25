// DealsNotifier Provider 单元测试
// 使用 ProviderContainer + override 隔离真实网络调用

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dealjoy_merchant/features/deals/models/merchant_deal.dart';
import 'package:dealjoy_merchant/features/deals/providers/deals_provider.dart';
import 'package:dealjoy_merchant/features/deals/services/deals_service.dart';

// ============================================================
// Mock DealsService
// ============================================================
class MockDealsService extends Mock implements DealsService {}

/// 构造测试用 MerchantDeal
MerchantDeal _makeDeal({
  String id = 'deal-001',
  DealStatus status = DealStatus.inactive,
  bool isActive = false,
}) {
  return MerchantDeal(
    id:              id,
    merchantId:      'merchant-001',
    title:           'Test Deal $id',
    description:     'A test deal',
    category:        'Restaurant',
    originalPrice:   49.99,
    discountPrice:   29.99,
    stockLimit:      50,
    totalSold:       5,
    rating:          4.0,
    reviewCount:     3,
    isActive:        isActive,
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

void main() {
  late MockDealsService mockService;

  setUpAll(() {
    registerFallbackValue(_makeDeal(id: 'fallback-deal'));
  });

  /// 构造 ProviderContainer，注入 mock service
  /// merchantId 从 Supabase auth 获取，这里通过重写 dealsProvider 的 build 来绕过
  ProviderContainer makeContainer(List<MerchantDeal> initialDeals) {
    return ProviderContainer(
      overrides: [
        dealsServiceProvider.overrideWithValue(mockService),
        // 重写 dealsProvider 的 build，注入已知数据
        dealsProvider.overrideWith(() => _TestDealsNotifier(initialDeals)),
      ],
    );
  }

  setUp(() {
    mockService = MockDealsService();
  });

  // ============================================================
  // 初始加载
  // ============================================================
  group('DealsNotifier build', () {
    test('成功加载后 state 为 AsyncData<List<MerchantDeal>>', () async {
      final deals = [_makeDeal(), _makeDeal(id: 'deal-002')];

      final container = makeContainer(deals);
      addTearDown(container.dispose);

      final result = await container.read(dealsProvider.future);

      expect(result.length, equals(2));
      expect(result.first.id, equals('deal-001'));
    });

    test('空列表时 state 为 AsyncData<[]>', () async {
      final container = makeContainer([]);
      addTearDown(container.dispose);

      final result = await container.read(dealsProvider.future);
      expect(result, isEmpty);
    });
  });

  // ============================================================
  // createDeal
  // ============================================================
  group('createDeal', () {
    test('创建成功后新 Deal 插入到列表头部', () async {
      final existing = [_makeDeal(id: 'deal-existing')];
      final newDeal  = _makeDeal(id: 'deal-new', status: DealStatus.pending);

      when(
        () => mockService.createDeal(any()),
      ).thenAnswer((_) async => newDeal);

      final container = makeContainer(existing);
      addTearDown(container.dispose);

      await container.read(dealsProvider.future);
      final created = await container
          .read(dealsProvider.notifier)
          .createDeal(newDeal);

      expect(created.id, equals('deal-new'));

      final state = container.read(dealsProvider).valueOrNull ?? [];
      // 新 Deal 应在列表头部
      expect(state.first.id, equals('deal-new'));
      expect(state.length, equals(2));
    });
  });

  // ============================================================
  // toggleDealStatus
  // ============================================================
  group('toggleDealStatus', () {
    test('上架成功后 deal 状态变为 active', () async {
      final deal = _makeDeal(status: DealStatus.inactive);

      when(
        () => mockService.toggleDealStatus('deal-001', true),
      ).thenAnswer((_) async {});

      final container = makeContainer([deal]);
      addTearDown(container.dispose);

      await container.read(dealsProvider.future);
      await container
          .read(dealsProvider.notifier)
          .toggleDealStatus('deal-001', true);

      final state = container.read(dealsProvider).valueOrNull ?? [];
      final updated = state.firstWhere((d) => d.id == 'deal-001');
      expect(updated.dealStatus, equals(DealStatus.active));
      expect(updated.isActive, isTrue);
    });

    test('下架成功后 deal 状态变为 inactive', () async {
      final deal = _makeDeal(status: DealStatus.active, isActive: true);

      when(
        () => mockService.toggleDealStatus('deal-001', false),
      ).thenAnswer((_) async {});

      final container = makeContainer([deal]);
      addTearDown(container.dispose);

      await container.read(dealsProvider.future);
      await container
          .read(dealsProvider.notifier)
          .toggleDealStatus('deal-001', false);

      final state = container.read(dealsProvider).valueOrNull ?? [];
      final updated = state.firstWhere((d) => d.id == 'deal-001');
      expect(updated.dealStatus, equals(DealStatus.inactive));
      expect(updated.isActive, isFalse);
    });

    test('toggleDealStatus 失败时回滚乐观更新', () async {
      final deal = _makeDeal(status: DealStatus.inactive);

      when(
        () => mockService.toggleDealStatus(any(), any()),
      ).thenThrow(Exception('Server error'));

      final container = makeContainer([deal]);
      addTearDown(container.dispose);

      await container.read(dealsProvider.future);

      try {
        await container
            .read(dealsProvider.notifier)
            .toggleDealStatus('deal-001', true);
      } catch (_) {}

      final state = container.read(dealsProvider);
      // 失败后应回滚：state 为 error 或 data（含原状态）
      if (state is AsyncData<List<MerchantDeal>>) {
        final d = state.value.firstWhere((d) => d.id == 'deal-001');
        expect(d.dealStatus, equals(DealStatus.inactive));
      } else {
        expect(state, isA<AsyncError>());
      }
    });
  });

  // ============================================================
  // deleteDeal
  // ============================================================
  group('deleteDeal', () {
    test('删除成功后 deal 从列表移除', () async {
      final deals = [
        _makeDeal(id: 'deal-001', status: DealStatus.inactive),
        _makeDeal(id: 'deal-002', status: DealStatus.inactive),
      ];

      when(
        () => mockService.deleteDeal('deal-001'),
      ).thenAnswer((_) async {});

      final container = makeContainer(deals);
      addTearDown(container.dispose);

      await container.read(dealsProvider.future);
      await container.read(dealsProvider.notifier).deleteDeal('deal-001');

      final state = container.read(dealsProvider).valueOrNull ?? [];
      expect(state.length, equals(1));
      expect(state.first.id, equals('deal-002'));
    });

    test('deleteDeal 失败时 deal 回滚到列表中', () async {
      final deal = _makeDeal(status: DealStatus.inactive);

      when(
        () => mockService.deleteDeal(any()),
      ).thenThrow(Exception('Delete failed'));

      final container = makeContainer([deal]);
      addTearDown(container.dispose);

      await container.read(dealsProvider.future);

      try {
        await container.read(dealsProvider.notifier).deleteDeal('deal-001');
      } catch (_) {}

      final state = container.read(dealsProvider);
      if (state is AsyncData<List<MerchantDeal>>) {
        expect(state.value.any((d) => d.id == 'deal-001'), isTrue);
      } else {
        expect(state, isA<AsyncError>());
      }
    });
  });

  // ============================================================
  // filteredDealsProvider
  // ============================================================
  group('filteredDealsProvider', () {
    test('filter=null 时返回所有 deals', () async {
      final deals = [
        _makeDeal(id: '1', status: DealStatus.active),
        _makeDeal(id: '2', status: DealStatus.inactive),
        _makeDeal(id: '3', status: DealStatus.pending),
      ];

      final container = makeContainer(deals);
      addTearDown(container.dispose);

      await container.read(dealsProvider.future);

      final filtered = container.read(filteredDealsProvider);
      expect(filtered.valueOrNull?.length, equals(3));
    });

    test('filter=active 时只返回 active deals', () async {
      final deals = [
        _makeDeal(id: '1', status: DealStatus.active),
        _makeDeal(id: '2', status: DealStatus.inactive),
        _makeDeal(id: '3', status: DealStatus.active),
      ];

      final container = makeContainer(deals);
      addTearDown(container.dispose);

      await container.read(dealsProvider.future);

      // 设置筛选为 active
      container.read(dealFilterProvider.notifier).state = DealStatus.active;

      final filtered = container.read(filteredDealsProvider);
      expect(filtered.valueOrNull?.length, equals(2));
      expect(
        filtered.valueOrNull?.every((d) => d.dealStatus == DealStatus.active),
        isTrue,
      );
    });

    test('filter=pending 时只返回 pending deals', () async {
      final deals = [
        _makeDeal(id: '1', status: DealStatus.active),
        _makeDeal(id: '2', status: DealStatus.pending),
      ];

      final container = makeContainer(deals);
      addTearDown(container.dispose);

      await container.read(dealsProvider.future);

      container.read(dealFilterProvider.notifier).state = DealStatus.pending;

      final filtered = container.read(filteredDealsProvider);
      expect(filtered.valueOrNull?.length, equals(1));
      expect(filtered.valueOrNull?.first.id, equals('2'));
    });
  });
}

// ============================================================
// 测试用 DealsNotifier（跳过真实 Supabase auth，直接返回注入数据）
// ============================================================
class _TestDealsNotifier extends DealsNotifier {
  _TestDealsNotifier(this._initialDeals);

  final List<MerchantDeal> _initialDeals;

  @override
  Future<List<MerchantDeal>> build() async {
    bindDealsServiceForTest(ref.read(dealsServiceProvider));
    return _initialDeals;
  }
}
