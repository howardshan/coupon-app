// ScanService 单元测试
// 覆盖: verifyCoupon / redeemCoupon / fetchRedemptionHistory
// 使用 mocktail mock SupabaseClient 的 functions 调用

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dealjoy_merchant/features/scan/models/coupon_info.dart';
import 'package:dealjoy_merchant/features/tips/models/tip_models.dart';
import 'package:dealjoy_merchant/features/scan/services/scan_service.dart';

// Mock 类定义
class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockFunctionsClient extends Mock implements FunctionsClient {}

// 顶层测试用固定时间
final _testNow = DateTime(2026, 3, 3, 14, 30, 0);
final _testValidUntil = DateTime(2026, 6, 1, 23, 59, 59);

// 标准成功响应数据（顶层函数，避免在 main() 内使用 getter 语法）
Map<String, dynamic> _validCouponJson() => {
      'id': 'coupon-uuid-001',
      'code': 'DJ-XXXXXXXXXXXX',
      'deal_title': 'Texas BBQ House — 2 Person Set',
      'user_name': 'J*** Smith',
      'valid_until': _testValidUntil.toIso8601String(),
      'status': 'active',
      'redeemed_at': null,
      'error': null,
    };

void main() {
  late MockSupabaseClient mockClient;
  late MockFunctionsClient mockFunctions;
  late ScanService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockFunctions = MockFunctionsClient();
    // 让 client.functions 返回 mock
    when(() => mockClient.functions).thenReturn(mockFunctions);
    service = ScanService(mockClient);
  });

  // =============================================================
  // verifyCoupon 测试组
  // =============================================================
  group('verifyCoupon', () {
    test('返回 CouponInfo 当券码有效', () async {
      // Arrange
      when(() => mockFunctions.invoke(
            any(),
            method: any(named: 'method'),
            body: any(named: 'body'),
          )).thenAnswer(
        (_) async => FunctionResponse(data: _validCouponJson(), status: 200),
      );

      // Act
      final result = await service.verifyCoupon('DJ-XXXXXXXXXXXX');

      // Assert
      expect(result.id, equals('coupon-uuid-001'));
      expect(result.code, equals('DJ-XXXXXXXXXXXX'));
      expect(result.dealTitle, equals('Texas BBQ House — 2 Person Set'));
      expect(result.userName, equals('J*** Smith'));
      expect(result.status, equals(CouponStatus.active));
      expect(result.isRedeemable, isTrue);
    });

    test('抛出 ScanException(alreadyUsed) 当券已核销', () async {
      // Arrange
      when(() => mockFunctions.invoke(
            any(),
            method: any(named: 'method'),
            body: any(named: 'body'),
          )).thenAnswer(
        (_) async => FunctionResponse(
          data: {
            'error': 'already_used',
            'message': 'This voucher has already been redeemed on Mar 1, 2026',
            'detail': _testNow.toIso8601String(),
          },
          status: 400,
        ),
      );

      // Act & Assert
      expect(
        () => service.verifyCoupon('DJ-XXXXXXXXXXXX'),
        throwsA(
          isA<ScanException>().having(
            (e) => e.error,
            'error',
            ScanError.alreadyUsed,
          ),
        ),
      );
    });

    test('抛出 ScanException(expired) 当券已过期', () async {
      when(() => mockFunctions.invoke(
            any(),
            method: any(named: 'method'),
            body: any(named: 'body'),
          )).thenAnswer(
        (_) async => FunctionResponse(
          data: {
            'error': 'expired',
            'message': 'This voucher expired on Jan 1, 2026',
            'detail': null,
          },
          status: 400,
        ),
      );

      expect(
        () => service.verifyCoupon('DJ-XXXXXXXXXXXX'),
        throwsA(isA<ScanException>()
            .having((e) => e.error, 'error', ScanError.expired)),
      );
    });

    test('抛出 ScanException(notFound) 当券码不存在', () async {
      when(() => mockFunctions.invoke(
            any(),
            method: any(named: 'method'),
            body: any(named: 'body'),
          )).thenAnswer(
        (_) async => FunctionResponse(
          data: {'error': 'not_found', 'message': 'Invalid voucher code'},
          status: 404,
        ),
      );

      expect(
        () => service.verifyCoupon('INVALID'),
        throwsA(isA<ScanException>()
            .having((e) => e.error, 'error', ScanError.notFound)),
      );
    });

    test('抛出 ScanException(wrongMerchant) 当券不属于当前商家', () async {
      when(() => mockFunctions.invoke(
            any(),
            method: any(named: 'method'),
            body: any(named: 'body'),
          )).thenAnswer(
        (_) async => FunctionResponse(
          data: {
            'error': 'wrong_merchant',
            'message': 'This voucher is not valid for your store',
          },
          status: 403,
        ),
      );

      expect(
        () => service.verifyCoupon('DJ-OTHERSTORE'),
        throwsA(isA<ScanException>()
            .having((e) => e.error, 'error', ScanError.wrongMerchant)),
      );
    });

    test('FunctionException 映射为 ScanException(network)', () async {
      when(() => mockFunctions.invoke(
            any(),
            method: any(named: 'method'),
            body: any(named: 'body'),
          )).thenThrow(
        const FunctionException(status: 500, reasonPhrase: 'Internal Server Error'),
      );

      expect(
        () => service.verifyCoupon('DJ-XXXXXXXXXXXX'),
        throwsA(isA<ScanException>()
            .having((e) => e.error, 'error', ScanError.network)),
      );
    });
  });

  // =============================================================
  // redeemCoupon 测试组
  // =============================================================
  group('redeemCoupon', () {
    test('返回 RedeemResult 当核销成功', () async {
      final expectedTime = DateTime(2026, 3, 3, 14, 30, 0).toUtc();

      when(() => mockFunctions.invoke(
            any(),
            method: any(named: 'method'),
            body: any(named: 'body'),
          )).thenAnswer(
        (_) async => FunctionResponse(
          data: {
            'redeemed_at': expectedTime.toIso8601String(),
            'coupon_id': 'coupon-uuid-001',
            'deal': {'tips_enabled': false},
            'tip_base_cents': 0,
          },
          status: 200,
        ),
      );

      final result = await service.redeemCoupon('coupon-uuid-001');
      expect(result.redeemedAt, equals(expectedTime));
      expect(result.tip, isA<TipDealConfig>());
      expect(result.tip.tipsEnabled, isFalse);
    });

    test('抛出 ScanException(alreadyUsed) 当重复核销', () async {
      when(() => mockFunctions.invoke(
            any(),
            method: any(named: 'method'),
            body: any(named: 'body'),
          )).thenAnswer(
        (_) async => FunctionResponse(
          data: {
            'error': 'already_used',
            'message': 'This voucher has already been redeemed',
          },
          status: 400,
        ),
      );

      expect(
        () => service.redeemCoupon('coupon-uuid-001'),
        throwsA(isA<ScanException>()
            .having((e) => e.error, 'error', ScanError.alreadyUsed)),
      );
    });
  });

  // =============================================================
  // fetchRedemptionHistory 测试组
  // =============================================================
  group('fetchRedemptionHistory', () {
    test('返回分页数据', () async {
      final redeemedAt = DateTime(2026, 3, 3, 10, 0, 0).toUtc();

      when(() => mockFunctions.invoke(
            any(),
            method: any(named: 'method'),
          )).thenAnswer(
        (_) async => FunctionResponse(
          data: {
            'data': [
              {
                'id': 'log-uuid-001',
                'coupon_id': 'coupon-uuid-001',
                'coupon_code': 'DJ-XXXXXXXXXXXX',
                'deal_title': 'Texas BBQ House — 2 Person Set',
                'user_name': 'J*** Smith',
                'redeemed_at': redeemedAt.toIso8601String(),
                'is_reverted': false,
                'reverted_at': null,
              }
            ],
            'total': 1,
            'page': 1,
            'per_page': 20,
            'has_more': false,
          },
          status: 200,
        ),
      );

      final result = await service.fetchRedemptionHistory();
      final records = result['data'] as List<RedemptionRecord>;

      expect(records.length, equals(1));
      expect(records.first.couponCode, equals('DJ-XXXXXXXXXXXX'));
      expect(records.first.isReverted, isFalse);
      expect(result['total'], equals(1));
      expect(result['has_more'], isFalse);
    });

    test('已撤销记录 isReverted 为 true', () async {
      final redeemedAt = DateTime(2026, 3, 3, 10, 0, 0).toUtc();
      final revertedAt = DateTime(2026, 3, 3, 10, 5, 0).toUtc();

      when(() => mockFunctions.invoke(
            any(),
            method: any(named: 'method'),
          )).thenAnswer(
        (_) async => FunctionResponse(
          data: {
            'data': [
              {
                'id': 'log-uuid-002',
                'coupon_id': 'coupon-uuid-002',
                'coupon_code': 'DJ-YYYYYYYYYYYY',
                'deal_title': 'Hot Pot Paradise',
                'user_name': 'L*** Chen',
                'redeemed_at': redeemedAt.toIso8601String(),
                'is_reverted': true,
                'reverted_at': revertedAt.toIso8601String(),
              }
            ],
            'total': 1,
            'page': 1,
            'per_page': 20,
            'has_more': false,
          },
          status: 200,
        ),
      );

      final result = await service.fetchRedemptionHistory();
      final records = result['data'] as List<RedemptionRecord>;

      expect(records.first.isReverted, isTrue);
      expect(records.first.revertedAt, equals(revertedAt));
      // 已撤销的记录 canRevert 应为 false
      expect(records.first.canRevert, isFalse);
    });
  });
}
