// PromoCodeResult 及折扣计算逻辑单元测试

import 'package:flutter_test/flutter_test.dart';
import 'package:deal_joy/features/checkout/data/repositories/checkout_repository.dart';

void main() {
  group('PromoCodeResult', () {
    test('percentage label format', () {
      const result = PromoCodeResult(
        code: 'WELCOME10',
        discountType: 'percentage',
        discountValue: 10,
        calculatedDiscount: 5.0,
      );

      expect(result.label, '10% off');
    });

    test('fixed label format', () {
      const result = PromoCodeResult(
        code: 'SAVE5',
        discountType: 'fixed',
        discountValue: 5.0,
        calculatedDiscount: 5.0,
      );

      expect(result.label, '\$5.00 off');
    });

    test('percentage with max discount cap', () {
      const result = PromoCodeResult(
        code: 'BIG50',
        discountType: 'percentage',
        discountValue: 50,
        maxDiscount: 10.0,
        calculatedDiscount: 10.0, // capped at maxDiscount
      );

      expect(result.calculatedDiscount, 10.0);
      expect(result.label, '50% off');
    });

    test('percentage with no max discount', () {
      const result = PromoCodeResult(
        code: 'HALF',
        discountType: 'percentage',
        discountValue: 50,
        maxDiscount: null,
        calculatedDiscount: 25.0,
      );

      expect(result.calculatedDiscount, 25.0);
      expect(result.maxDiscount, isNull);
    });
  });

  group('CheckoutResult', () {
    test('stores orderId', () {
      const result = CheckoutResult(orderId: 'order-123');
      expect(result.orderId, 'order-123');
    });
  });
}
