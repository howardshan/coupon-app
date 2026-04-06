// 团购券 CouponModel 单元测试

import 'package:flutter_test/flutter_test.dart';
import 'package:deal_joy/features/orders/data/models/coupon_model.dart';

void main() {
  group('CouponModel', () {
    final baseJson = {
      'id': 'coupon-001',
      'order_id': 'order-001',
      'user_id': 'user-001',
      'deal_id': 'deal-001',
      'merchant_id': 'merchant-001',
      'qr_code': 'abc123hex',
      'status': 'unused',
      'expires_at': '2026-04-01T00:00:00.000Z',
      'used_at': null,
      'created_at': '2026-03-01T10:00:00.000Z',
      'gifted_from': null,
      'verified_by': null,
      'deals': {
        'id': 'deal-001',
        'title': 'BBQ Combo for 2',
        'description': 'Includes ribs, brisket, and sides',
        'image_urls': ['https://example.com/bbq.jpg'],
        'refund_policy': 'Refund anytime before use, refund when expired',
        'usage_rules': [
          '1 deal per table per visit',
          'Cannot be combined with other offers',
        ],
        'merchants': {
          'name': 'Texas BBQ House',
          'logo_url': 'https://example.com/logo.png',
          'address': '123 Main St, Dallas, TX',
          'phone': '+1-972-555-0100',
        },
      },
    };

    test('fromJson creates model correctly with full data', () {
      final coupon = CouponModel.fromJson(baseJson);

      expect(coupon.id, 'coupon-001');
      expect(coupon.orderId, 'order-001');
      expect(coupon.userId, 'user-001');
      expect(coupon.dealId, 'deal-001');
      expect(coupon.merchantId, 'merchant-001');
      expect(coupon.qrCode, 'abc123hex');
      expect(coupon.status, 'unused');
      expect(coupon.expiresAt, DateTime.utc(2026, 4, 1));
      expect(coupon.usedAt, isNull);
      expect(coupon.createdAt, DateTime.utc(2026, 3, 1, 10));
      expect(coupon.giftedFrom, isNull);
      expect(coupon.verifiedBy, isNull);

      // Join 字段
      expect(coupon.dealTitle, 'BBQ Combo for 2');
      expect(coupon.dealDescription, 'Includes ribs, brisket, and sides');
      expect(coupon.dealImageUrl, 'https://example.com/bbq.jpg');
      expect(coupon.refundPolicy, 'Refund anytime before use, refund when expired');
      expect(coupon.usageRules.length, 2);
      expect(coupon.usageRules.first, '1 deal per table per visit');
      expect(coupon.merchantName, 'Texas BBQ House');
      expect(coupon.merchantLogoUrl, 'https://example.com/logo.png');
      expect(coupon.merchantAddress, '123 Main St, Dallas, TX');
      expect(coupon.merchantPhone, '+1-972-555-0100');
    });

    test('fromJson handles null deals gracefully', () {
      final json = Map<String, dynamic>.from(baseJson);
      json['deals'] = null;

      final coupon = CouponModel.fromJson(json);

      expect(coupon.dealTitle, isNull);
      expect(coupon.merchantName, isNull);
      expect(coupon.dealImageUrl, isNull);
    });

    test('fromJson handles empty image_urls', () {
      final json = Map<String, dynamic>.from(baseJson);
      json['deals'] = {
        'id': 'deal-001',
        'title': 'Some Deal',
        'description': null,
        'image_urls': [],
        'refund_policy': null,
        'merchants': null,
      };

      final coupon = CouponModel.fromJson(json);

      expect(coupon.dealTitle, 'Some Deal');
      expect(coupon.dealImageUrl, isNull);
      expect(coupon.merchantName, isNull);
    });

    test('fromJson parses used_at when present', () {
      final json = Map<String, dynamic>.from(baseJson);
      json['status'] = 'used';
      json['used_at'] = '2026-03-15T19:30:00.000Z';

      final coupon = CouponModel.fromJson(json);

      expect(coupon.usedAt, DateTime.utc(2026, 3, 15, 19, 30));
      expect(coupon.isUsed, isTrue);
    });

    test('fromJson parses gifted_from and verified_by', () {
      final json = Map<String, dynamic>.from(baseJson);
      json['gifted_from'] = 'coupon-original';
      json['verified_by'] = 'merchant-user-001';

      final coupon = CouponModel.fromJson(json);

      expect(coupon.giftedFrom, 'coupon-original');
      expect(coupon.verifiedBy, 'merchant-user-001');
    });

    test('status getters work correctly', () {
      CouponModel fromStatus(String s) {
        final json = Map<String, dynamic>.from(baseJson);
        json['status'] = s;
        // 避免随系统日期超过 expires_at 后 isExpired 误判
        json['expires_at'] = '2099-12-31T00:00:00.000Z';
        return CouponModel.fromJson(json);
      }

      expect(fromStatus('unused').isUnused, isTrue);
      expect(fromStatus('unused').isUsed, isFalse);

      expect(fromStatus('used').isUsed, isTrue);
      expect(fromStatus('used').isUnused, isFalse);

      expect(fromStatus('expired').isExpired, isTrue);
      expect(fromStatus('expired').isUsed, isFalse);

      expect(fromStatus('refunded').isRefunded, isTrue);
      expect(fromStatus('refunded').isExpired, isFalse);
    });

    test('effectiveHolderUserId and viewerCanManagePurchaseActions', () {
      final json = Map<String, dynamic>.from(baseJson);
      json['current_holder_user_id'] = 'user-friend';
      final c = CouponModel.fromJson(json);
      expect(c.effectiveHolderUserId, 'user-friend');
      expect(c.isHeldByUser('user-friend'), isTrue);
      expect(c.isHeldByUser('user-001'), isFalse);
      expect(c.viewerCanManagePurchaseActions('user-001'), isFalse);
      expect(c.viewerCanManagePurchaseActions('user-friend'), isFalse);
    });

    test('viewerCanManagePurchaseActions when holder is purchaser', () {
      final c = CouponModel.fromJson(baseJson);
      expect(c.effectiveHolderUserId, 'user-001');
      expect(c.viewerCanManagePurchaseActions('user-001'), isTrue);
      expect(c.viewerCanManagePurchaseActions(null), isFalse);
    });

    test('fromJson parses deals as List embed (PostgREST) and usage_rules', () {
      final json = Map<String, dynamic>.from(baseJson);
      final dealsMap = Map<String, dynamic>.from(
          json['deals'] as Map<String, dynamic>);
      json['deals'] = [dealsMap];
      final coupon = CouponModel.fromJson(json);
      expect(coupon.usageRules.length, 2);
      expect(coupon.dealTitle, 'BBQ Combo for 2');
    });

    test('parseUsageRulesDynamic handles JSON string array', () {
      final rules = CouponModel.parseUsageRulesDynamic(
          '["Rule one", "Rule two"]');
      expect(rules, ['Rule one', 'Rule two']);
    });

    test('usageDisplayLines falls back to usage_notes when usage_rules empty',
        () {
      final json = Map<String, dynamic>.from(baseJson);
      final deals = Map<String, dynamic>.from(
          json['deals'] as Map<String, dynamic>);
      deals['usage_rules'] = <String>[];
      deals['usage_notes'] = 'Line one\nLine two';
      json['deals'] = deals;
      final coupon = CouponModel.fromJson(json);
      expect(coupon.usageRules, isEmpty);
      expect(coupon.usageDisplayLines, ['Line one', 'Line two']);
    });
  });
}
