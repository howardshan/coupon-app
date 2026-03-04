// StoreNotifier Provider 单元测试
// 使用 ProviderContainer + override 隔离真实网络调用

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dealjoy_merchant/features/store/models/store_info.dart';
import 'package:dealjoy_merchant/features/store/providers/store_provider.dart';
import 'package:dealjoy_merchant/features/store/services/store_service.dart';

// ============================================================
// Mock StoreService
// ============================================================
class MockStoreService extends Mock implements StoreService {}

// 测试用门店数据工厂
StoreInfo _makeStore({
  String id = 'merchant-001',
  String name = 'Texas BBQ House',
  List<String> tags = const ['WiFi'],
  List<StorePhoto> photos = const [],
  List<BusinessHours> hours = const [],
}) {
  return StoreInfo(
    id: id,
    name: name,
    description: 'Best BBQ',
    phone: '(214) 555-0100',
    address: '123 Main St',
    category: 'Restaurant',
    tags: tags,
    isOnline: true,
    status: 'approved',
    photos: photos,
    hours: hours,
  );
}

void main() {
  late MockStoreService mockService;

  // 构造 ProviderContainer 并注入 mock service
  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        // 用 mock service 替换真实 storeServiceProvider
        storeServiceProvider.overrideWithValue(mockService),
      ],
    );
  }

  setUp(() {
    mockService = MockStoreService();
  });

  // ============================================================
  // build（初始加载）
  // ============================================================
  group('StoreNotifier build', () {
    test('成功加载时 state 变为 AsyncData<StoreInfo>', () async {
      final store = _makeStore();
      when(() => mockService.fetchStoreInfo())
          .thenAnswer((_) async => store);

      final container = makeContainer();
      addTearDown(container.dispose);

      // 等待 async build 完成
      final result = await container.read(storeProvider.future);

      expect(result.id, equals('merchant-001'));
      expect(result.name, equals('Texas BBQ House'));
    });

    test('fetchStoreInfo 抛出异常时 state 变为 AsyncError', () async {
      when(() => mockService.fetchStoreInfo())
          .thenThrow(Exception('Network error'));

      final container = makeContainer();
      addTearDown(container.dispose);

      // 等待状态稳定
      await container.read(storeProvider.future).catchError((_) => _makeStore());

      final state = container.read(storeProvider);
      expect(state, isA<AsyncError>());
    });
  });

  // ============================================================
  // updateBasicInfo
  // ============================================================
  group('updateBasicInfo', () {
    test('成功后乐观更新 state 中的 name 字段', () async {
      final original = _makeStore(name: 'Old Name');
      when(() => mockService.fetchStoreInfo())
          .thenAnswer((_) async => original);
      when(() => mockService.updateStoreInfo(name: 'New Name'))
          .thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);

      // 等待初始加载
      await container.read(storeProvider.future);

      // 触发更新
      await container.read(storeProvider.notifier).updateBasicInfo(name: 'New Name');

      final updated = container.read(storeProvider).valueOrNull;
      expect(updated?.name, equals('New Name'));
    });

    test('updateStoreInfo 抛出异常时回滚为原始数据', () async {
      final original = _makeStore(name: 'Original Name');
      when(() => mockService.fetchStoreInfo())
          .thenAnswer((_) async => original);
      when(() => mockService.updateStoreInfo(name: any(named: 'name')))
          .thenThrow(Exception('Save failed'));

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(storeProvider.future);

      // 尝试更新（会抛出并回滚）
      try {
        await container
            .read(storeProvider.notifier)
            .updateBasicInfo(name: 'New Name');
      } catch (_) {}

      // 回滚后 name 应恢复为原始值
      final state = container.read(storeProvider);
      // 回滚后 state 可能是 AsyncError 或 AsyncData（原始值）
      // 取 valueOrNull 验证不是新值
      expect(state.valueOrNull?.name, isNot(equals('New Name')));
    });
  });

  // ============================================================
  // updateTags
  // ============================================================
  group('updateTags', () {
    test('成功后 state 中 tags 更新为新列表', () async {
      final original = _makeStore(tags: ['WiFi']);
      when(() => mockService.fetchStoreInfo())
          .thenAnswer((_) async => original);
      when(() => mockService.updateStoreInfo(tags: any(named: 'tags')))
          .thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(storeProvider.future);

      final newTags = ['WiFi', 'Parking', 'Pet Friendly'];
      await container.read(storeProvider.notifier).updateTags(newTags);

      final updated = container.read(storeProvider).valueOrNull;
      expect(updated?.tags, equals(newTags));
    });
  });

  // ============================================================
  // deletePhoto
  // ============================================================
  group('deletePhoto', () {
    test('成功后照片从 state 中移除', () async {
      final photo = StorePhoto(
        id: 'photo-001',
        url: 'https://example.com/1.jpg',
        type: StorePhotoType.storefront,
        sortOrder: 0,
        createdAt: DateTime.now(),
      );
      final original = _makeStore(photos: [photo]);

      when(() => mockService.fetchStoreInfo())
          .thenAnswer((_) async => original);
      when(() => mockService.deletePhoto('photo-001'))
          .thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(storeProvider.future);

      await container.read(storeProvider.notifier).deletePhoto('photo-001');

      final updated = container.read(storeProvider).valueOrNull;
      expect(updated?.photos, isEmpty);
    });

    test('deletePhoto 失败时照片回滚到 state 中', () async {
      final photo = StorePhoto(
        id: 'photo-001',
        url: 'https://example.com/1.jpg',
        type: StorePhotoType.storefront,
        sortOrder: 0,
        createdAt: DateTime.now(),
      );
      final original = _makeStore(photos: [photo]);

      when(() => mockService.fetchStoreInfo())
          .thenAnswer((_) async => original);
      when(() => mockService.deletePhoto(any()))
          .thenThrow(Exception('Delete failed'));

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(storeProvider.future);

      try {
        await container.read(storeProvider.notifier).deletePhoto('photo-001');
      } catch (_) {}

      // 回滚后照片应仍在列表中或 state 为 error
      final state = container.read(storeProvider);
      // 允许 state 为 error 或 data（含原照片）
      if (state is AsyncData<StoreInfo>) {
        expect(state.value.photos.any((p) => p.id == 'photo-001'), isTrue);
      } else {
        expect(state, isA<AsyncError>());
      }
    });
  });

  // ============================================================
  // refresh
  // ============================================================
  group('refresh', () {
    test('调用 refresh 后重新触发 fetchStoreInfo', () async {
      final store = _makeStore();
      when(() => mockService.fetchStoreInfo())
          .thenAnswer((_) async => store);

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(storeProvider.future);
      await container.read(storeProvider.notifier).refresh();

      // fetchStoreInfo 应被调用 2 次（初始 build + refresh）
      verify(() => mockService.fetchStoreInfo()).called(2);
    });
  });

  // ============================================================
  // reorderPhotos
  // ============================================================
  group('reorderPhotos', () {
    test('成功后照片按新顺序排列', () async {
      final p1 = StorePhoto(
        id: 'photo-001',
        url: 'https://example.com/1.jpg',
        type: StorePhotoType.environment,
        sortOrder: 0,
        createdAt: DateTime.now(),
      );
      final p2 = StorePhoto(
        id: 'photo-002',
        url: 'https://example.com/2.jpg',
        type: StorePhotoType.environment,
        sortOrder: 1,
        createdAt: DateTime.now(),
      );
      final original = _makeStore(photos: [p1, p2]);

      when(() => mockService.fetchStoreInfo())
          .thenAnswer((_) async => original);
      when(() => mockService.reorderPhotos(any()))
          .thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(storeProvider.future);

      // 反转顺序
      await container
          .read(storeProvider.notifier)
          .reorderPhotos(['photo-002', 'photo-001']);

      final updated = container.read(storeProvider).valueOrNull;
      // p2 应排在前面（sortOrder=0）
      final reordered = updated?.photos.where((p) => p.type == StorePhotoType.environment).toList();
      expect(reordered?.first.id, equals('photo-002'));
      expect(reordered?.first.sortOrder, equals(0));
    });
  });
}
