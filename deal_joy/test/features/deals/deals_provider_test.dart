import 'package:flutter_test/flutter_test.dart';
import 'package:deal_joy/core/utils/location_utils.dart';
import 'package:deal_joy/features/deals/data/models/deal_model.dart';

void main() {
  group('haversineDistanceMiles', () {
    test('同一点距离为0', () {
      expect(
        haversineDistanceMiles(32.7767, -96.7970, 32.7767, -96.7970),
        0.0,
      );
    });

    test('Dallas → Fort Worth 约30英里', () {
      final d = haversineDistanceMiles(32.7767, -96.7970, 32.7555, -97.3308);
      expect(d, greaterThan(28));
      expect(d, lessThan(35));
    });

    test('Dallas → Houston 约240英里', () {
      final d = haversineDistanceMiles(32.7767, -96.7970, 29.7604, -95.3698);
      expect(d, greaterThan(220));
      expect(d, lessThan(260));
    });

    test('对称性: A→B == B→A', () {
      final ab = haversineDistanceMiles(32.7767, -96.7970, 29.7604, -95.3698);
      final ba = haversineDistanceMiles(29.7604, -95.3698, 32.7767, -96.7970);
      expect(ab, closeTo(ba, 0.001));
    });
  });

  group('DealModel', () {
    final sampleJson = {
      'id': 'deal-1',
      'merchant_id': 'merchant-1',
      'title': 'Test Deal',
      'description': 'A great deal',
      'category': 'Food',
      'original_price': 50.0,
      'discount_price': 30.0,
      'discount_percent': 40,
      'discount_label': '40% OFF',
      'image_urls': ['https://example.com/img.jpg'],
      'dishes': ['Dish A', 'Dish B'],
      'rating': 4.5,
      'review_count': 100,
      'total_sold': 500,
      'stock_limit': 200,
      'expires_at': '2027-12-31T23:59:59Z',
      'is_featured': true,
      'refund_policy': 'No questions asked',
      'lat': 32.7767,
      'lng': -96.7970,
      'address': '123 Main St, Dallas',
    };

    test('fromJson 解析完整 JSON', () {
      final deal = DealModel.fromJson(sampleJson);
      expect(deal.id, 'deal-1');
      expect(deal.merchantId, 'merchant-1');
      expect(deal.title, 'Test Deal');
      expect(deal.category, 'Food');
      expect(deal.originalPrice, 50.0);
      expect(deal.discountPrice, 30.0);
      expect(deal.discountPercent, 40);
      expect(deal.discountLabel, '40% OFF');
      expect(deal.imageUrls, ['https://example.com/img.jpg']);
      expect(deal.products, ['Dish A', 'Dish B']);
      expect(deal.rating, 4.5);
      expect(deal.reviewCount, 100);
      expect(deal.totalSold, 500);
      expect(deal.stockLimit, 200);
      expect(deal.isFeatured, true);
      expect(deal.lat, 32.7767);
      expect(deal.lng, -96.7970);
      expect(deal.address, '123 Main St, Dallas');
    });

    test('fromJson 缺省值回退', () {
      final minJson = {
        'id': 'deal-2',
        'merchant_id': 'm-2',
        'title': 'Minimal Deal',
        'description': 'desc',
        'category': 'Beauty',
        'original_price': 100,
        'discount_price': 60,
        'expires_at': '2027-06-01T00:00:00Z',
      };
      final deal = DealModel.fromJson(minJson);
      expect(deal.discountPercent, 40); // 自动计算 (1-60/100)*100
      expect(deal.discountLabel, '');
      expect(deal.rating, 0.0);
      expect(deal.reviewCount, 0);
      expect(deal.totalSold, 0);
      expect(deal.stockLimit, 100);
      expect(deal.isFeatured, false);
      expect(deal.lat, isNull);
      expect(deal.merchant, isNull);
    });

    test('effectiveDiscountLabel 优先使用 discountLabel', () {
      final deal = DealModel.fromJson(sampleJson);
      expect(deal.effectiveDiscountLabel, '40% OFF');
    });

    test('effectiveDiscountLabel 回退到百分比', () {
      final json = Map<String, dynamic>.from(sampleJson);
      json['discount_label'] = '';
      final deal = DealModel.fromJson(json);
      expect(deal.effectiveDiscountLabel, '40% OFF');
    });

    test('savingsAmount 计算正确', () {
      final deal = DealModel.fromJson(sampleJson);
      expect(deal.savingsAmount, 20.0);
    });

    test('isExpired 判断过期', () {
      // 未来日期不过期
      final deal = DealModel.fromJson(sampleJson);
      expect(deal.isExpired, false);

      // 过去日期已过期
      final expired = DealModel.fromJson({
        ...sampleJson,
        'expires_at': '2020-01-01T00:00:00Z',
      });
      expect(expired.isExpired, true);
    });
  });

  group('MerchantSummary', () {
    test('fromJson 解析', () {
      final json = {
        'id': 'm-1',
        'name': 'Test Restaurant',
        'logo_url': 'https://example.com/logo.png',
        'phone': '214-555-0100',
        'address': '456 Elm St',
        'hours': 'Mon-Fri 9am-9pm',
        'rating': 4.8,
        'review_count': 250,
      };
      final m = MerchantSummary.fromJson(json);
      expect(m.id, 'm-1');
      expect(m.name, 'Test Restaurant');
      expect(m.logoUrl, 'https://example.com/logo.png');
      expect(m.phone, '214-555-0100');
      expect(m.rating, 4.8);
      expect(m.reviewCount, 250);
    });

    test('fromJson 缺省值', () {
      final json = {'id': 'm-2', 'name': 'Minimal'};
      final m = MerchantSummary.fromJson(json);
      expect(m.logoUrl, isNull);
      expect(m.phone, isNull);
      expect(m.rating, 0.0);
      expect(m.reviewCount, 0);
    });
  });
}
