// OrderModel 及 DealSummary 单元测试

import 'package:flutter_test/flutter_test.dart';
import 'package:deal_joy/features/orders/data/models/order_model.dart';

void main() {
  group('OrderModel', () {
    final baseJson = {
      'id': 'order-001',
      'user_id': 'user-001',
      'deal_id': 'deal-001',
      'coupon_id': 'coupon-001',
      'quantity': 2,
      'total_amount': 59.98,
      'status': 'unused',
      'payment_intent_id': 'pi_test_123',
      'created_at': '2026-03-01T10:00:00.000Z',
      'deals': {
        'id': 'deal-001',
        'title': 'BBQ Combo for 2',
        'image_urls': ['https://example.com/bbq.jpg'],
        'merchants': {'name': 'Texas BBQ House'},
      },
    };

    test('fromJson creates model correctly', () {
      final order = OrderModel.fromJson(baseJson);

      expect(order.id, 'order-001');
      expect(order.userId, 'user-001');
      expect(order.dealId, 'deal-001');
      expect(order.couponId, 'coupon-001');
      expect(order.quantity, 2);
      expect(order.totalAmount, 59.98);
      expect(order.status, 'unused');
      expect(order.paymentIntentId, 'pi_test_123');
      expect(order.createdAt, DateTime.utc(2026, 3, 1, 10));
    });

    test('fromJson parses nested DealSummary', () {
      final order = OrderModel.fromJson(baseJson);

      expect(order.deal, isNotNull);
      expect(order.deal!.id, 'deal-001');
      expect(order.deal!.title, 'BBQ Combo for 2');
      expect(order.deal!.imageUrl, 'https://example.com/bbq.jpg');
      expect(order.deal!.merchantName, 'Texas BBQ House');
    });

    test('fromJson handles null coupon_id', () {
      final json = Map<String, dynamic>.from(baseJson);
      json['coupon_id'] = null;

      final order = OrderModel.fromJson(json);
      expect(order.couponId, isNull);
    });

    test('fromJson handles null deals', () {
      final json = Map<String, dynamic>.from(baseJson);
      json['deals'] = null;

      final order = OrderModel.fromJson(json);
      expect(order.deal, isNull);
    });

    test('status getters work correctly', () {
      OrderModel fromStatus(String s) {
        final json = Map<String, dynamic>.from(baseJson);
        json['status'] = s;
        return OrderModel.fromJson(json);
      }

      expect(fromStatus('unused').isUnused, isTrue);
      expect(fromStatus('unused').isUsed, isFalse);
      expect(fromStatus('unused').isRefunded, isFalse);

      expect(fromStatus('used').isUsed, isTrue);
      expect(fromStatus('used').isUnused, isFalse);

      expect(fromStatus('refunded').isRefunded, isTrue);
      expect(fromStatus('refunded').isUnused, isFalse);

      // 新增状态 getter 测试
      expect(fromStatus('refund_requested').isRefundRequested, isTrue);
      expect(fromStatus('expired').isExpired, isTrue);

      // canRefund：仅 unused 可退款
      expect(fromStatus('unused').canRefund, isTrue);
      expect(fromStatus('used').canRefund, isFalse);
      expect(fromStatus('refunded').canRefund, isFalse);
      expect(fromStatus('refund_requested').canRefund, isFalse);
      expect(fromStatus('expired').canRefund, isFalse);
    });

    test('fromJson parses refund fields correctly', () {
      // 验证退款相关字段可以正确从 JSON 解析
      final json = Map<String, dynamic>.from(baseJson);
      json['refund_reason'] = 'Changed my mind';
      json['refund_requested_at'] = '2026-03-01T12:00:00.000Z';
      json['refunded_at'] = '2026-03-01T12:05:00.000Z';
      json['status'] = 'refunded';

      final order = OrderModel.fromJson(json);
      expect(order.refundReason, 'Changed my mind');
      expect(order.refundRequestedAt, DateTime.utc(2026, 3, 1, 12));
      expect(order.refundedAt, DateTime.utc(2026, 3, 1, 12, 5));
      expect(order.isRefunded, isTrue);
      expect(order.canRefund, isFalse);
    });
  });

  group('DealSummary', () {
    test('fromJson handles empty image_urls', () {
      final json = {
        'id': 'deal-001',
        'title': 'Some Deal',
        'image_urls': <String>[],
        'merchants': null,
      };

      final summary = DealSummary.fromJson(json);
      expect(summary.imageUrl, isNull);
      expect(summary.merchantName, isNull);
    });

    test('fromJson parses first image URL', () {
      final json = {
        'id': 'deal-001',
        'title': 'Some Deal',
        'image_urls': ['https://img1.jpg', 'https://img2.jpg'],
        'merchants': {'name': 'Shop A'},
      };

      final summary = DealSummary.fromJson(json);
      expect(summary.imageUrl, 'https://img1.jpg');
      expect(summary.merchantName, 'Shop A');
    });
  });
}
