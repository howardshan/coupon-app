// ScanNotifier / RedemptionHistoryNotifier 单元测试
// 使用 mocktail mock ScanService，通过 ProviderContainer 驱动 Notifier

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dealjoy_merchant/features/scan/models/coupon_info.dart';
import 'package:dealjoy_merchant/features/scan/services/scan_service.dart';
import 'package:dealjoy_merchant/features/scan/providers/scan_provider.dart';

// Mock ScanService
class MockScanService extends Mock implements ScanService {}

// 顶层辅助函数：构造一个基础 CouponInfo
CouponInfo _makeCouponInfo({CouponStatus status = CouponStatus.active}) {
  return CouponInfo(
    id: 'coupon-uuid-001',
    code: 'DJ-XXXXXXXXXXXX',
    dealTitle: 'Texas BBQ House — 2 Person Set',
    userName: 'J*** Smith',
    validUntil: DateTime(2026, 6, 1),
    status: status,
  );
}

void main() {
  late MockScanService mockService;
  late ProviderContainer container;

  setUp(() {
    mockService = MockScanService();
    // 用 override 把 scanServiceProvider 替换为 mock
    container = ProviderContainer(
      overrides: [
        scanServiceProvider.overrideWithValue(mockService),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  // =============================================================
  // ScanNotifier 测试组
  // =============================================================
  group('ScanNotifier', () {
    test('初始状态为 AsyncData(null)', () {
      final state = container.read(scanNotifierProvider);
      expect(state, equals(const AsyncData<CouponInfo?>(null)));
    });

    test('verify() 成功后 state 为 AsyncData(CouponInfo)', () async {
      final coupon = _makeCouponInfo();
      when(() => mockService.verifyCoupon('DJ-XXXXXXXXXXXX'))
          .thenAnswer((_) async => coupon);

      await container
          .read(scanNotifierProvider.notifier)
          .verify('DJ-XXXXXXXXXXXX');

      final state = container.read(scanNotifierProvider);
      expect(state.value, equals(coupon));
    });

    test('verify() 失败后 state 为 AsyncError(ScanException)', () async {
      when(() => mockService.verifyCoupon(any())).thenThrow(
        const ScanException(
          error: ScanError.notFound,
          message: 'Invalid voucher code',
        ),
      );

      await container
          .read(scanNotifierProvider.notifier)
          .verify('INVALID');

      final state = container.read(scanNotifierProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<ScanException>());
    });

    test('redeem() 成功后返回 DateTime', () async {
      final expectedTime = DateTime(2026, 3, 3, 14, 30, 0);
      when(() => mockService.redeemCoupon('coupon-uuid-001'))
          .thenAnswer((_) async => expectedTime);

      final result = await container
          .read(scanNotifierProvider.notifier)
          .redeem('coupon-uuid-001');

      expect(result, equals(expectedTime));
    });

    test('redeem() 失败时抛出 ScanException', () async {
      when(() => mockService.redeemCoupon(any())).thenThrow(
        const ScanException(
          error: ScanError.alreadyUsed,
          message: 'Already redeemed',
        ),
      );

      expect(
        () => container
            .read(scanNotifierProvider.notifier)
            .redeem('coupon-uuid-001'),
        throwsA(isA<ScanException>()),
      );
    });

    test('reset() 后 state 恢复为 AsyncData(null)', () async {
      // 先 verify 让 state 有数据
      final coupon = _makeCouponInfo();
      when(() => mockService.verifyCoupon(any()))
          .thenAnswer((_) async => coupon);
      await container
          .read(scanNotifierProvider.notifier)
          .verify('DJ-XXXXXXXXXXXX');

      // 确认有数据
      expect(container.read(scanNotifierProvider).value, isNotNull);

      // reset
      container.read(scanNotifierProvider.notifier).reset();

      expect(
        container.read(scanNotifierProvider),
        equals(const AsyncData<CouponInfo?>(null)),
      );
    });

  });

  // =============================================================
  // RedemptionHistoryFilter 测试组
  // =============================================================
  group('RedemptionHistoryFilter', () {
    test('初始状态 hasFilter 为 false', () {
      const filter = RedemptionHistoryFilter();
      expect(filter.hasFilter, isFalse);
    });

    test('设置 dateFrom 后 hasFilter 为 true', () {
      final filter = RedemptionHistoryFilter(
        dateFrom: DateTime(2026, 3, 1),
      );
      expect(filter.hasFilter, isTrue);
    });

    test('copyWith clearDeal 清除 dealId', () {
      final filter = RedemptionHistoryFilter(
        dealId: 'deal-uuid-001',
        dealTitle: 'Texas BBQ',
      );
      final cleared = filter.copyWith(clearDeal: true);
      expect(cleared.dealId, isNull);
      expect(cleared.dealTitle, isNull);
    });

    test('copyWith 保留未修改字段', () {
      final from = DateTime(2026, 3, 1);
      final filter = RedemptionHistoryFilter(dateFrom: from);
      final updated = filter.copyWith(dealId: 'deal-001', dealTitle: 'BBQ');
      expect(updated.dateFrom, equals(from));
      expect(updated.dealId, equals('deal-001'));
    });
  });

  // =============================================================
  // RedemptionRecord.canRevert 测试组
  // =============================================================
  group('RedemptionRecord.canRevert', () {
    test('核销10分钟内且未撤销 — canRevert 为 true', () {
      final record = RedemptionRecord(
        id: 'log-001',
        couponId: 'coupon-001',
        couponCode: 'DJ-XXX',
        dealTitle: 'BBQ',
        userName: 'J***',
        redeemedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        isReverted: false,
      );
      expect(record.canRevert, isTrue);
    });

    test('核销超过10分钟 — canRevert 为 false', () {
      final record = RedemptionRecord(
        id: 'log-002',
        couponId: 'coupon-002',
        couponCode: 'DJ-YYY',
        dealTitle: 'Hot Pot',
        userName: 'L***',
        redeemedAt: DateTime.now().subtract(const Duration(minutes: 15)),
        isReverted: false,
      );
      expect(record.canRevert, isFalse);
    });

    test('已撤销记录 — canRevert 为 false', () {
      final record = RedemptionRecord(
        id: 'log-003',
        couponId: 'coupon-003',
        couponCode: 'DJ-ZZZ',
        dealTitle: 'Sushi',
        userName: 'K***',
        redeemedAt: DateTime.now().subtract(const Duration(minutes: 3)),
        isReverted: true,
        revertedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(record.canRevert, isFalse);
    });
  });

  // =============================================================
  // CouponStatus 测试组
  // =============================================================
  group('CouponStatus', () {
    test('fromString 正确映射各枚举值', () {
      expect(CouponStatus.fromString('active'), CouponStatus.active);
      expect(CouponStatus.fromString('unused'), CouponStatus.active); // 兼容旧枚举
      expect(CouponStatus.fromString('used'), CouponStatus.used);
      expect(CouponStatus.fromString('expired'), CouponStatus.expired);
      expect(CouponStatus.fromString('refunded'), CouponStatus.refunded);
    });

    test('active 且未过期的券 isRedeemable 为 true', () {
      final coupon = _makeCouponInfo();
      expect(coupon.isRedeemable, isTrue);
    });

    test('used 状态的券 isRedeemable 为 false', () {
      final coupon = _makeCouponInfo(status: CouponStatus.used);
      expect(coupon.isRedeemable, isFalse);
    });
  });
}
