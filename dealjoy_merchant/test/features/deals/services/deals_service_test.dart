// DealsService 单元测试
// 使用 mocktail 模拟 SupabaseClient，不依赖真实网络

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dealjoy_merchant/features/deals/models/merchant_deal.dart';
import 'package:dealjoy_merchant/features/deals/services/deals_service.dart';

// ============================================================
// Mock 类定义
// ============================================================
class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockFunctions extends Mock implements FunctionsClient {}
class MockStorage extends Mock implements SupabaseStorageClient {}
class MockStorageBucket extends Mock implements StorageFileApi {}

/// 构造测试用 FunctionResponse
FunctionResponse _mockResponse(int status, Map<String, dynamic> data) {
  return FunctionResponse(status: status, data: data);
}

/// 构造测试用 MerchantDeal
MerchantDeal _testDeal({
  String id = 'deal-uuid-001',
  DealStatus status = DealStatus.inactive,
}) {
  return MerchantDeal(
    id:              id,
    merchantId:      'merchant-uuid-001',
    title:           'Test BBQ Set',
    description:     'A great BBQ experience',
    category:        'Restaurant',
    originalPrice:   49.99,
    discountPrice:   29.99,
    stockLimit:      50,
    totalSold:       10,
    rating:          4.5,
    reviewCount:     8,
    isActive:        status == DealStatus.active,
    dealStatus:      status,
    validityType:    ValidityType.fixedDate,
    expiresAt:       DateTime(2026, 12, 31),
    usageDays:       const ['Mon', 'Tue', 'Wed'],
    isStackable:     true,
    images:          const [],
    createdAt:       DateTime(2026, 3, 1),
    updatedAt:       DateTime(2026, 3, 1),
  );
}

/// 构造 Deal JSON（Edge Function 返回格式）
Map<String, dynamic> _dealJson({String id = 'deal-uuid-001'}) {
  return {
    'id':              id,
    'merchant_id':     'merchant-uuid-001',
    'title':           'Test BBQ Set',
    'description':     'A great BBQ experience',
    'category':        'Restaurant',
    'original_price':  49.99,
    'discount_price':  29.99,
    'discount_percent': 40,
    'stock_limit':     50,
    'total_sold':      10,
    'rating':          4.5,
    'review_count':    8,
    'is_active':       false,
    'deal_status':     'inactive',
    'package_contents': '2x BBQ Plates',
    'usage_notes':     'Reservation required',
    'validity_type':   'fixed_date',
    'validity_days':   null,
    'expires_at':      '2026-12-31T00:00:00Z',
    'usage_days':      ['Mon', 'Tue', 'Wed'],
    'max_per_person':  null,
    'is_stackable':    true,
    'review_notes':    null,
    'published_at':    null,
    'deal_images':     [],
    'created_at':      '2026-03-01T10:00:00Z',
    'updated_at':      '2026-03-01T10:00:00Z',
  };
}

void main() {
  late MockSupabaseClient mockClient;
  late MockFunctions mockFunctions;
  late MockStorage mockStorage;
  late DealsService service;

  setUp(() {
    mockClient    = MockSupabaseClient();
    mockFunctions = MockFunctions();
    mockStorage   = MockStorage();

    when(() => mockClient.functions).thenReturn(mockFunctions);
    when(() => mockClient.storage).thenReturn(mockStorage);

    service = DealsService(mockClient);
  });

  // ============================================================
  // fetchDeals
  // ============================================================
  group('fetchDeals', () {
    test('成功时返回 MerchantDeal 列表', () async {
      when(
        () => mockFunctions.invoke(
          'merchant-deals',
          method: HttpMethod.get,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _mockResponse(200, {
          'deals': [_dealJson(), _dealJson(id: 'deal-uuid-002')],
        }),
      );

      final result = await service.fetchDeals('merchant-uuid-001');

      expect(result.length, equals(2));
      expect(result.first.title, equals('Test BBQ Set'));
      expect(result.first.dealStatus, equals(DealStatus.inactive));
    });

    test('支持状态筛选参数', () async {
      when(
        () => mockFunctions.invoke(
          'merchant-deals',
          method: HttpMethod.get,
          queryParameters: {'status': 'active'},
        ),
      ).thenAnswer(
        (_) async => _mockResponse(200, {'deals': []}),
      );

      final result = await service.fetchDeals(
        'merchant-uuid-001',
        filter: DealStatus.active,
      );

      expect(result, isEmpty);
    });

    test('服务器返回 401 时抛出 Exception', () async {
      when(
        () => mockFunctions.invoke(
          'merchant-deals',
          method: HttpMethod.get,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _mockResponse(401, {'error': 'Unauthorized'}),
      );

      expect(
        () => service.fetchDeals('merchant-uuid-001'),
        throwsException,
      );
    });

    test('空列表时返回空数组（不抛出异常）', () async {
      when(
        () => mockFunctions.invoke(
          'merchant-deals',
          method: HttpMethod.get,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _mockResponse(200, {'deals': []}),
      );

      final result = await service.fetchDeals('merchant-uuid-001');
      expect(result, isEmpty);
    });
  });

  // ============================================================
  // createDeal
  // ============================================================
  group('createDeal', () {
    test('成功时返回创建的 MerchantDeal', () async {
      when(
        () => mockFunctions.invoke(
          'merchant-deals',
          method: HttpMethod.post,
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => _mockResponse(201, {'deal': _dealJson()}),
      );

      final deal   = _testDeal();
      final result = await service.createDeal(deal);

      expect(result.id, equals('deal-uuid-001'));
      expect(result.title, equals('Test BBQ Set'));
    });

    test('价格无效时（服务器返回 400）抛出 Exception', () async {
      when(
        () => mockFunctions.invoke(
          'merchant-deals',
          method: HttpMethod.post,
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => _mockResponse(400, {
          'error': 'Deal price must be less than original price',
        }),
      );

      expect(() => service.createDeal(_testDeal()), throwsException);
    });
  });

  // ============================================================
  // updateDeal
  // ============================================================
  group('updateDeal', () {
    test('成功时返回更新后的 MerchantDeal（状态重置为 pending）', () async {
      final updatedJson = {
        ..._dealJson(),
        'deal_status': 'pending',
        'is_active': false,
      };

      when(
        () => mockFunctions.invoke(
          'merchant-deals/deal-uuid-001',
          method: HttpMethod.patch,
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => _mockResponse(200, {'deal': updatedJson}),
      );

      final deal   = _testDeal();
      final result = await service.updateDeal(deal);

      expect(result.dealStatus, equals(DealStatus.pending));
      expect(result.isActive, isFalse);
    });

    test('deal 不存在时（服务器返回 404）抛出 Exception', () async {
      when(
        () => mockFunctions.invoke(
          any(),
          method: HttpMethod.patch,
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => _mockResponse(404, {'error': 'Deal not found'}),
      );

      expect(() => service.updateDeal(_testDeal()), throwsException);
    });
  });

  // ============================================================
  // toggleDealStatus
  // ============================================================
  group('toggleDealStatus', () {
    test('成功上架时不抛出异常', () async {
      when(
        () => mockFunctions.invoke(
          'merchant-deals/deal-uuid-001/status',
          method: HttpMethod.patch,
          body: {'is_active': true},
        ),
      ).thenAnswer(
        (_) async => _mockResponse(200, {
          'deal': {'id': 'deal-uuid-001', 'deal_status': 'active'},
          'new_status': 'active',
        }),
      );

      await expectLater(
        service.toggleDealStatus('deal-uuid-001', true),
        completes,
      );
    });

    test('成功下架时不抛出异常', () async {
      when(
        () => mockFunctions.invoke(
          'merchant-deals/deal-uuid-001/status',
          method: HttpMethod.patch,
          body: {'is_active': false},
        ),
      ).thenAnswer(
        (_) async => _mockResponse(200, {
          'deal': {'id': 'deal-uuid-001', 'deal_status': 'inactive'},
          'new_status': 'inactive',
        }),
      );

      await expectLater(
        service.toggleDealStatus('deal-uuid-001', false),
        completes,
      );
    });

    test('对 pending 状态 deal 上架时服务器返回 400，抛出 Exception', () async {
      when(
        () => mockFunctions.invoke(
          any(),
          method: HttpMethod.patch,
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => _mockResponse(400, {
          'error': 'Cannot activate deal with status: pending',
        }),
      );

      expect(
        () => service.toggleDealStatus('deal-uuid-001', true),
        throwsException,
      );
    });
  });

  // ============================================================
  // deleteDeal
  // ============================================================
  group('deleteDeal', () {
    test('成功删除 inactive deal 时不抛出异常', () async {
      when(
        () => mockFunctions.invoke(
          'merchant-deals/deal-uuid-001',
          method: HttpMethod.delete,
        ),
      ).thenAnswer(
        (_) async => _mockResponse(200, {
          'success': true,
          'deleted_id': 'deal-uuid-001',
        }),
      );

      await expectLater(
        service.deleteDeal('deal-uuid-001'),
        completes,
      );
    });

    test('deal 处于 active 状态时服务器返回 400，抛出 Exception', () async {
      when(
        () => mockFunctions.invoke(
          any(),
          method: HttpMethod.delete,
        ),
      ).thenAnswer(
        (_) async => _mockResponse(400, {
          'error': 'Only inactive deals can be deleted.',
        }),
      );

      expect(() => service.deleteDeal('deal-uuid-001'), throwsException);
    });
  });

  // ============================================================
  // MerchantDeal model 单元测试
  // ============================================================
  group('MerchantDeal model', () {
    test('fromJson 正确解析 JSON', () {
      final deal = MerchantDeal.fromJson(_dealJson());

      expect(deal.id,             equals('deal-uuid-001'));
      expect(deal.title,          equals('Test BBQ Set'));
      expect(deal.originalPrice,  equals(49.99));
      expect(deal.discountPrice,  equals(29.99));
      expect(deal.dealStatus,     equals(DealStatus.inactive));
      expect(deal.validityType,   equals(ValidityType.fixedDate));
      expect(deal.usageDays,      contains('Mon'));
      expect(deal.isStackable,    isTrue);
      expect(deal.images,         isEmpty);
    });

    test('isUnlimited 在 stockLimit=-1 时返回 true', () {
      final deal = _testDeal().copyWith(stockLimit: -1);
      expect(deal.isUnlimited, isTrue);
    });

    test('isSoldOut 在 remainingStock<=0 时返回 true', () {
      final deal = _testDeal().copyWith(stockLimit: 10, totalSold: 10);
      expect(deal.isSoldOut, isTrue);
    });

    test('canEdit 在 pending 状态时返回 false', () {
      final deal = _testDeal(status: DealStatus.pending);
      expect(deal.canEdit, isFalse);
    });

    test('canActivate 仅在 inactive 状态时返回 true', () {
      expect(_testDeal(status: DealStatus.inactive).canActivate, isTrue);
      expect(_testDeal(status: DealStatus.active).canActivate, isFalse);
      expect(_testDeal(status: DealStatus.pending).canActivate, isFalse);
    });

    test('discountLabel 格式正确（40% OFF）', () {
      final deal = _testDeal().copyWith(discountPercent: 40);
      expect(deal.discountLabel, equals('40% OFF'));
    });

    test('coverImageUrl 优先返回 is_primary=true 的图片', () {
      final primaryImg = DealImage(
        id:        'img-001',
        dealId:    'deal-uuid-001',
        imageUrl:  'https://example.com/primary.jpg',
        sortOrder: 0,
        isPrimary: true,
        createdAt: DateTime.now(),
      );
      final secondImg = DealImage(
        id:        'img-002',
        dealId:    'deal-uuid-001',
        imageUrl:  'https://example.com/second.jpg',
        sortOrder: 1,
        isPrimary: false,
        createdAt: DateTime.now(),
      );
      final deal = _testDeal().copyWith(images: [primaryImg, secondImg]);
      expect(deal.coverImageUrl, equals('https://example.com/primary.jpg'));
    });
  });

  // ============================================================
  // DealStatus enum 测试
  // ============================================================
  group('DealStatus enum', () {
    test('fromString 正确解析', () {
      expect(DealStatus.fromString('pending'),  equals(DealStatus.pending));
      expect(DealStatus.fromString('active'),   equals(DealStatus.active));
      expect(DealStatus.fromString('inactive'), equals(DealStatus.inactive));
      expect(DealStatus.fromString('rejected'), equals(DealStatus.rejected));
      expect(DealStatus.fromString(null),       equals(DealStatus.pending));
      expect(DealStatus.fromString('unknown'),  equals(DealStatus.pending));
    });

    test('displayLabel 返回正确文案', () {
      expect(DealStatus.active.displayLabel,   equals('Active'));
      expect(DealStatus.pending.displayLabel,  equals('Pending Review'));
      expect(DealStatus.inactive.displayLabel, equals('Inactive'));
      expect(DealStatus.rejected.displayLabel, equals('Rejected'));
    });
  });

  // ============================================================
  // ValidityType enum 测试
  // ============================================================
  group('ValidityType enum', () {
    test('fromString 正确解析', () {
      expect(
        ValidityType.fromString('fixed_date'),
        equals(ValidityType.fixedDate),
      );
      expect(
        ValidityType.fromString('days_after_purchase'),
        equals(ValidityType.daysAfterPurchase),
      );
      expect(
        ValidityType.fromString(null),
        equals(ValidityType.fixedDate),
      );
    });

    test('value 返回正确 API 字符串', () {
      expect(ValidityType.fixedDate.value,          equals('fixed_date'));
      expect(ValidityType.daysAfterPurchase.value,  equals('days_after_purchase'));
    });
  });
}
