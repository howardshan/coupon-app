// 退款系统单元测试
// 覆盖：CouponModel 状态 getter、OrderModel.canRefund 逻辑

import 'package:flutter_test/flutter_test.dart';
import 'package:deal_joy/features/orders/data/models/coupon_model.dart';
import 'package:deal_joy/features/orders/data/models/order_model.dart';

void main() {
  // ────────────────────────────────────────────────────────────
  // CouponModel 状态 getter 测试
  // ────────────────────────────────────────────────────────────
  group('CouponModel status getters', () {
    // 构造最小 JSON，只覆盖 status 字段
    final baseJson = <String, dynamic>{
      'id': 'coupon-001',
      'order_id': 'order-001',
      'user_id': 'user-001',
      'deal_id': 'deal-001',
      'merchant_id': 'merchant-001',
      'qr_code': 'qrcode-hex',
      'status': 'unused',
      'expires_at': '2026-12-31T00:00:00.000Z',
      'used_at': null,
      'created_at': '2026-03-01T10:00:00.000Z',
      'gifted_from': null,
      'verified_by': null,
      'deals': null,
    };

    CouponModel fromStatus(String s) {
      final json = Map<String, dynamic>.from(baseJson);
      json['status'] = s;
      return CouponModel.fromJson(json);
    }

    test('isUnused is true only for unused status', () {
      // 未使用券的 isUnused 为 true，其余状态均为 false
      expect(fromStatus('unused').isUnused, isTrue);
      expect(fromStatus('used').isUnused, isFalse);
      expect(fromStatus('expired').isUnused, isFalse);
      expect(fromStatus('refunded').isUnused, isFalse);
    });

    test('isUsed is true only for used status', () {
      // 已核销券
      expect(fromStatus('used').isUsed, isTrue);
      expect(fromStatus('unused').isUsed, isFalse);
      expect(fromStatus('expired').isUsed, isFalse);
      expect(fromStatus('refunded').isUsed, isFalse);
    });

    test('isExpired is true only for expired status', () {
      // 已过期券
      expect(fromStatus('expired').isExpired, isTrue);
      expect(fromStatus('unused').isExpired, isFalse);
      expect(fromStatus('used').isExpired, isFalse);
      expect(fromStatus('refunded').isExpired, isFalse);
    });

    test('isRefunded is true only for refunded status', () {
      // 已退款券
      expect(fromStatus('refunded').isRefunded, isTrue);
      expect(fromStatus('unused').isRefunded, isFalse);
      expect(fromStatus('used').isRefunded, isFalse);
      expect(fromStatus('expired').isRefunded, isFalse);
    });

    test('exactly one status getter is true at a time', () {
      // 每种状态有且仅有一个 getter 为 true（互斥检查）
      final statuses = ['unused', 'used', 'expired', 'refunded'];
      for (final s in statuses) {
        final coupon = fromStatus(s);
        final trueCount = [
          coupon.isUnused,
          coupon.isUsed,
          coupon.isExpired,
          coupon.isRefunded,
        ].where((v) => v).length;
        expect(trueCount, 1,
            reason: 'Status "$s" should activate exactly one getter');
      }
    });
  });

  // ────────────────────────────────────────────────────────────
  // OrderModel.canRefund 逻辑测试
  // ────────────────────────────────────────────────────────────
  group('OrderModel canRefund logic', () {
    // 构造最小 OrderModel JSON，只覆盖 status 字段
    final baseJson = <String, dynamic>{
      'id': 'order-001',
      'user_id': 'user-001',
      'deal_id': 'deal-001',
      'coupon_id': null,
      'quantity': 1,
      'total_amount': 29.99,
      'status': 'unused',
      'payment_intent_id': 'pi_test_abc',
      'refund_reason': null,
      'refund_requested_at': null,
      'refunded_at': null,
      'created_at': '2026-03-01T10:00:00.000Z',
      'deals': null,
    };

    OrderModel fromStatus(String s) {
      final json = Map<String, dynamic>.from(baseJson);
      json['status'] = s;
      return OrderModel.fromJson(json);
    }

    test('unused order canRefund is true', () {
      // 只有未使用订单可以发起退款申请
      expect(fromStatus('unused').canRefund, isTrue);
    });

    test('used order canRefund is false', () {
      // 已核销后不可退款
      expect(fromStatus('used').canRefund, isFalse);
    });

    test('refunded order canRefund is false', () {
      // 已退款后不可再次退款
      expect(fromStatus('refunded').canRefund, isFalse);
    });

    test('refund_requested order canRefund is false', () {
      // 退款申请进行中，不可重复申请
      expect(fromStatus('refund_requested').canRefund, isFalse);
    });

    test('expired order canRefund is false', () {
      // 已过期订单不可退款
      expect(fromStatus('expired').canRefund, isFalse);
    });

    test('all non-unused statuses block refund', () {
      // 批量验证：除 unused 外所有状态均禁止退款
      final blocked = ['used', 'refunded', 'refund_requested', 'expired'];
      for (final s in blocked) {
        expect(fromStatus(s).canRefund, isFalse,
            reason: 'Status "$s" should not allow refund');
      }
    });
  });

  // ────────────────────────────────────────────────────────────
  // OrderModel 退款字段解析测试
  // ────────────────────────────────────────────────────────────
  group('OrderModel refund fields', () {
    final baseJson = <String, dynamic>{
      'id': 'order-002',
      'user_id': 'user-001',
      'deal_id': 'deal-001',
      'coupon_id': 'coupon-002',
      'quantity': 1,
      'total_amount': 19.99,
      'status': 'unused',
      'payment_intent_id': 'pi_test_xyz',
      'refund_reason': null,
      'refund_requested_at': null,
      'refunded_at': null,
      'created_at': '2026-03-01T09:00:00.000Z',
      'deals': null,
    };

    test('refund fields default to null when absent from JSON', () {
      // 退款字段均为可空，未提供时默认为 null
      final order = OrderModel.fromJson(baseJson);
      expect(order.refundReason, isNull);
      expect(order.refundRequestedAt, isNull);
      expect(order.refundedAt, isNull);
    });

    test('refund_requested status sets isRefundRequested true', () {
      // 退款申请中状态
      final json = Map<String, dynamic>.from(baseJson);
      json['status'] = 'refund_requested';
      json['refund_reason'] = 'Do not need it anymore';
      json['refund_requested_at'] = '2026-03-01T14:00:00.000Z';

      final order = OrderModel.fromJson(json);
      expect(order.isRefundRequested, isTrue);
      expect(order.refundReason, 'Do not need it anymore');
      expect(order.refundRequestedAt, DateTime.utc(2026, 3, 1, 14));
      expect(order.refundedAt, isNull);
    });

    test('refunded status populates all three refund fields', () {
      // 退款完成状态——三个退款字段均有值
      final json = Map<String, dynamic>.from(baseJson);
      json['status'] = 'refunded';
      json['refund_reason'] = 'Item not as described';
      json['refund_requested_at'] = '2026-03-01T15:00:00.000Z';
      json['refunded_at'] = '2026-03-01T15:30:00.000Z';

      final order = OrderModel.fromJson(json);
      expect(order.isRefunded, isTrue);
      expect(order.refundReason, 'Item not as described');
      expect(order.refundRequestedAt, DateTime.utc(2026, 3, 1, 15));
      expect(order.refundedAt, DateTime.utc(2026, 3, 1, 15, 30));
      expect(order.canRefund, isFalse);
    });
  });
}
