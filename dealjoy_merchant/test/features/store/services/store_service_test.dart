// StoreService 单元测试
// 使用 mocktail 模拟 SupabaseClient，不依赖真实网络

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dealjoy_merchant/features/store/models/store_info.dart';
import 'package:dealjoy_merchant/features/store/services/store_service.dart';

// ============================================================
// Mock 类定义
// ============================================================
class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockFunctions extends Mock implements FunctionsClient {}
class MockStorage extends Mock implements SupabaseStorageClient {}
class MockStorageBucket extends Mock implements StorageFileApi {}

// FunctionResponse 辅助工厂（模拟不同状态码和数据）
FunctionResponse _mockResponse(int status, Map<String, dynamic> data) {
  return FunctionResponse(status: status, data: data);
}

void main() {
  late MockSupabaseClient mockClient;
  late MockFunctions mockFunctions;
  late MockStorage mockStorage;
  late StoreService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockFunctions = MockFunctions();
    mockStorage = MockStorage();

    when(() => mockClient.functions).thenReturn(mockFunctions);
    when(() => mockClient.storage).thenReturn(mockStorage);

    service = StoreService(mockClient);
  });

  // ============================================================
  // fetchStoreInfo
  // ============================================================
  group('fetchStoreInfo', () {
    // 完整门店信息的测试 JSON
    final fullStoreJson = {
      'store': {
        'id': 'merchant-uuid-001',
        'name': 'Texas BBQ House',
        'description': 'Best BBQ in Dallas',
        'phone': '(214) 555-0100',
        'address': '123 Main St, Dallas, TX 75201',
        'category': 'Restaurant',
        'tags': ['WiFi', 'Parking'],
        'is_online': true,
        'status': 'approved',
        'lat': 32.7767,
        'lng': -96.7970,
      },
      'photos': [
        {
          'id': 'photo-uuid-001',
          'photo_url': 'https://example.com/photo1.jpg',
          'photo_type': 'storefront',
          'sort_order': 0,
          'created_at': '2026-03-01T10:00:00Z',
        }
      ],
      'hours': [
        {
          'id': 'hours-uuid-001',
          'day_of_week': 1,
          'open_time': '10:00',
          'close_time': '22:00',
          'is_closed': false,
        }
      ],
    };

    test('成功时返回 StoreInfo', () async {
      when(
        () => mockFunctions.invoke(
          'merchant-store',
          method: HttpMethod.get,
        ),
      ).thenAnswer((_) async => _mockResponse(200, fullStoreJson));

      final result = await service.fetchStoreInfo();

      expect(result.id, equals('merchant-uuid-001'));
      expect(result.name, equals('Texas BBQ House'));
      expect(result.tags, contains('WiFi'));
      expect(result.photos.length, equals(1));
      expect(result.photos.first.type, equals(StorePhotoType.storefront));
      expect(result.hours.length, equals(1));
      expect(result.hours.first.dayOfWeek, equals(1));
    });

    test('服务器返回非 200 时抛出 Exception', () async {
      when(
        () => mockFunctions.invoke(
          'merchant-store',
          method: HttpMethod.get,
        ),
      ).thenAnswer(
        (_) async => _mockResponse(401, {'error': 'Unauthorized'}),
      );

      expect(() => service.fetchStoreInfo(), throwsException);
    });
  });

  // ============================================================
  // updateStoreInfo
  // ============================================================
  group('updateStoreInfo', () {
    test('有字段时发送 PATCH 请求', () async {
      when(
        () => mockFunctions.invoke(
          'merchant-store',
          method: HttpMethod.patch,
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => _mockResponse(200, {
          'success': true,
          'store': {'id': 'merchant-uuid-001', 'name': 'New Name'},
        }),
      );

      await expectLater(
        service.updateStoreInfo(name: 'New Name'),
        completes,
      );

      verify(
        () => mockFunctions.invoke(
          'merchant-store',
          method: HttpMethod.patch,
          body: any(named: 'body'),
        ),
      ).called(1);
    });

    test('无字段时不发送请求（早返回）', () async {
      // 不调用任何 mock，确认方法提前返回
      await expectLater(service.updateStoreInfo(), completes);

      verifyNever(
        () => mockFunctions.invoke(
          any(),
          method: any(named: 'method'),
          body: any(named: 'body'),
        ),
      );
    });

    test('服务器返回错误时抛出 Exception', () async {
      when(
        () => mockFunctions.invoke(
          'merchant-store',
          method: HttpMethod.patch,
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => _mockResponse(500, {'error': 'Internal server error'}),
      );

      expect(
        () => service.updateStoreInfo(name: 'Test'),
        throwsException,
      );
    });
  });

  // ============================================================
  // updateBusinessHours
  // ============================================================
  group('updateBusinessHours', () {
    final testHours = [
      const BusinessHours(
        dayOfWeek: 1,
        openTime: '10:00',
        closeTime: '22:00',
        isClosed: false,
      ),
      const BusinessHours(
        dayOfWeek: 0,
        openTime: null,
        closeTime: null,
        isClosed: true,
      ),
    ];

    test('成功时返回更新后的营业时间列表', () async {
      when(
        () => mockFunctions.invoke(
          'merchant-store',
          method: HttpMethod.put,
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => _mockResponse(200, {
          'success': true,
          'hours': [
            {
              'id': 'h-uuid-001',
              'day_of_week': 1,
              'open_time': '10:00',
              'close_time': '22:00',
              'is_closed': false,
            },
            {
              'id': 'h-uuid-002',
              'day_of_week': 0,
              'open_time': null,
              'close_time': null,
              'is_closed': true,
            },
          ],
        }),
      );

      final result = await service.updateBusinessHours(testHours);

      expect(result.length, equals(2));
      expect(result.first.dayOfWeek, equals(1));
      expect(result.last.isClosed, isTrue);
    });
  });

  // ============================================================
  // deletePhoto
  // ============================================================
  group('deletePhoto', () {
    test('成功时不抛出异常', () async {
      when(
        () => mockFunctions.invoke(
          'merchant-store/photos/photo-uuid-001',
          method: HttpMethod.delete,
        ),
      ).thenAnswer(
        (_) async => _mockResponse(200, {'success': true, 'deleted_id': 'photo-uuid-001'}),
      );

      await expectLater(
        service.deletePhoto('photo-uuid-001'),
        completes,
      );
    });

    test('服务器返回 404 时抛出 Exception', () async {
      when(
        () => mockFunctions.invoke(
          any(),
          method: HttpMethod.delete,
        ),
      ).thenAnswer(
        (_) async => _mockResponse(404, {'error': 'Photo not found'}),
      );

      expect(() => service.deletePhoto('nonexistent-id'), throwsException);
    });
  });

  // ============================================================
  // StoreInfo model 测试
  // ============================================================
  group('StoreInfo model', () {
    test('storefrontPhoto 返回 storefront 类型的第一张照片', () {
      final store = StoreInfo(
        id: 'mid',
        name: 'Test Store',
        description: null,
        phone: null,
        address: null,
        category: 'Restaurant',
        tags: const [],
        isOnline: true,
        status: 'approved',
        photos: [
          StorePhoto(
            id: 'p1',
            url: 'https://example.com/1.jpg',
            type: StorePhotoType.environment,
            sortOrder: 0,
            createdAt: DateTime.now(),
          ),
          StorePhoto(
            id: 'p2',
            url: 'https://example.com/2.jpg',
            type: StorePhotoType.storefront,
            sortOrder: 0,
            createdAt: DateTime.now(),
          ),
        ],
        hours: const [],
      );

      expect(store.storefrontPhoto?.id, equals('p2'));
      expect(store.environmentPhotos.length, equals(1));
      expect(store.environmentPhotos.first.id, equals('p1'));
    });

    test('isOpenNow 在营业时间内返回 true', () {
      // 当前时间在 00:00-23:59 之间——设置当天全天营业
      final now = DateTime.now();
      // 使用当天的 day_of_week（0=Sunday，1=Monday...）
      final todayDow = now.weekday == 7 ? 0 : now.weekday;

      final store = StoreInfo(
        id: 'mid',
        name: 'Test',
        description: null,
        phone: null,
        address: null,
        category: null,
        tags: const [],
        isOnline: true,
        status: 'approved',
        photos: const [],
        hours: [
          BusinessHours(
            dayOfWeek: todayDow,
            openTime: '00:00',
            closeTime: '23:59',
            isClosed: false,
          ),
        ],
      );

      expect(store.isOpenNow, isTrue);
    });

    test('isClosed 为 true 时 isOpenNow 返回 false', () {
      final now = DateTime.now();
      final todayDow = now.weekday == 7 ? 0 : now.weekday;

      final store = StoreInfo(
        id: 'mid',
        name: 'Test',
        description: null,
        phone: null,
        address: null,
        category: null,
        tags: const [],
        isOnline: true,
        status: 'approved',
        photos: const [],
        hours: [
          BusinessHours(
            dayOfWeek: todayDow,
            openTime: null,
            closeTime: null,
            isClosed: true,
          ),
        ],
      );

      expect(store.isOpenNow, isFalse);
    });
  });

  // ============================================================
  // BusinessHours model 测试
  // ============================================================
  group('BusinessHours model', () {
    test('displayText 返回正确格式', () {
      const open = BusinessHours(
        dayOfWeek: 1,
        openTime: '10:00',
        closeTime: '22:00',
        isClosed: false,
      );
      expect(open.displayText, equals('10:00 - 22:00'));
    });

    test('休息日 displayText 返回 Closed', () {
      const closed = BusinessHours(
        dayOfWeek: 0,
        openTime: null,
        closeTime: null,
        isClosed: true,
      );
      expect(closed.displayText, equals('Closed'));
    });

    test('dayName 返回正确星期名称', () {
      expect(BusinessHours.dayName(0), equals('Sunday'));
      expect(BusinessHours.dayName(1), equals('Monday'));
      expect(BusinessHours.dayName(6), equals('Saturday'));
    });

    test('fromJson 正确解析 JSON', () {
      final json = {
        'id': 'uuid',
        'day_of_week': 3,
        'open_time': '11:00',
        'close_time': '21:00',
        'is_closed': false,
      };
      final h = BusinessHours.fromJson(json);
      expect(h.dayOfWeek, equals(3));
      expect(h.openTime, equals('11:00'));
      expect(h.isClosed, isFalse);
    });
  });
}
