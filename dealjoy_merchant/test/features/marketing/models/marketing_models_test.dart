// 营销工具模型单元测试
// 覆盖: FlashDeal / NewCustomerOffer / Promotion / PromoType
// 测试范围: fromJson / toJson / copyWith / 计算属性

import 'package:flutter_test/flutter_test.dart';
import 'package:dealjoy_merchant/features/marketing/models/marketing_models.dart';

void main() {
  // ============================================================
  // PromoType 枚举测试
  // ============================================================
  group('PromoType', () {
    test('fromValue 正确解析已知值', () {
      expect(PromoType.fromValue('spend_x_get_y'), PromoType.spendXGetY);
    });

    test('fromValue 未知值时回退到 spendXGetY', () {
      expect(PromoType.fromValue('unknown_type'), PromoType.spendXGetY);
    });

    test('value 字段返回数据库存储字符串', () {
      expect(PromoType.spendXGetY.value, 'spend_x_get_y');
    });

    test('displayName 返回可读名称', () {
      expect(PromoType.spendXGetY.displayName, 'Spend X Get Y');
    });
  });

  // ============================================================
  // FlashDeal 模型测试
  // ============================================================
  group('FlashDeal', () {
    // 基准测试数据
    final baseJson = {
      'id': 'fd-001',
      'deal_id': 'deal-001',
      'merchant_id': 'merchant-001',
      'discount_percentage': 10.0,
      'start_time': '2026-03-03T10:00:00.000Z',
      'end_time': '2026-03-03T20:00:00.000Z',
      'is_active': true,
      'created_at': '2026-03-03T08:00:00.000Z',
      'updated_at': '2026-03-03T08:00:00.000Z',
    };

    test('fromJson 正确解析所有字段', () {
      final flashDeal = FlashDeal.fromJson(baseJson);

      expect(flashDeal.id, 'fd-001');
      expect(flashDeal.dealId, 'deal-001');
      expect(flashDeal.merchantId, 'merchant-001');
      expect(flashDeal.discountPercentage, 10.0);
      expect(flashDeal.isActive, true);
      expect(flashDeal.startTime, DateTime.parse('2026-03-03T10:00:00.000Z'));
      expect(flashDeal.endTime, DateTime.parse('2026-03-03T20:00:00.000Z'));
    });

    test('toJson 正确序列化所有字段', () {
      final flashDeal = FlashDeal.fromJson(baseJson);
      final json = flashDeal.toJson();

      expect(json['id'], 'fd-001');
      expect(json['deal_id'], 'deal-001');
      expect(json['merchant_id'], 'merchant-001');
      expect(json['discount_percentage'], 10.0);
      expect(json['is_active'], true);
    });

    test('fromJson -> toJson 往返序列化一致', () {
      final flashDeal = FlashDeal.fromJson(baseJson);
      final json = flashDeal.toJson();
      final restored = FlashDeal.fromJson(json);

      expect(restored.id, flashDeal.id);
      expect(restored.discountPercentage, flashDeal.discountPercentage);
      expect(restored.startTime, flashDeal.startTime);
      expect(restored.endTime, flashDeal.endTime);
    });

    test('copyWith 正确更新指定字段', () {
      final original = FlashDeal.fromJson(baseJson);
      final updated = original.copyWith(discountPercentage: 20.0, isActive: false);

      expect(updated.discountPercentage, 20.0);
      expect(updated.isActive, false);
      // 未变更字段保持不变
      expect(updated.id, original.id);
      expect(updated.dealId, original.dealId);
    });

    test('copyWith 不传参数时返回等值对象', () {
      final original = FlashDeal.fromJson(baseJson);
      final copy = original.copyWith();

      expect(copy.id, original.id);
      expect(copy.discountPercentage, original.discountPercentage);
    });

    test('isCurrentlyActive: isActive=false 时返回 false', () {
      final flashDeal = FlashDeal.fromJson({...baseJson, 'is_active': false});
      expect(flashDeal.isCurrentlyActive, false);
    });

    test('isCurrentlyActive: 已过期时返回 false', () {
      final flashDeal = FlashDeal.fromJson({
        ...baseJson,
        'start_time': '2020-01-01T00:00:00.000Z',
        'end_time': '2020-01-02T00:00:00.000Z',
        'is_active': true,
      });
      expect(flashDeal.isCurrentlyActive, false);
    });

    test('== 运算符基于 id 比较', () {
      final a = FlashDeal.fromJson(baseJson);
      final b = FlashDeal.fromJson({...baseJson, 'discount_percentage': 99.0});
      // 同 id，不同字段 -> 相等
      expect(a, b);
    });

    test('hashCode 基于 id', () {
      final a = FlashDeal.fromJson(baseJson);
      final b = FlashDeal.fromJson(baseJson);
      expect(a.hashCode, b.hashCode);
    });

    test('toString 包含关键信息', () {
      final flashDeal = FlashDeal.fromJson(baseJson);
      final str = flashDeal.toString();
      expect(str, contains('fd-001'));
      expect(str, contains('10.0'));
    });
  });

  // ============================================================
  // NewCustomerOffer 模型测试
  // ============================================================
  group('NewCustomerOffer', () {
    final baseJson = {
      'id': 'nco-001',
      'deal_id': 'deal-002',
      'merchant_id': 'merchant-001',
      'special_price': 9.99,
      'is_active': true,
      'created_at': '2026-03-03T08:00:00.000Z',
      'updated_at': '2026-03-03T08:00:00.000Z',
    };

    test('fromJson 正确解析所有字段', () {
      final offer = NewCustomerOffer.fromJson(baseJson);

      expect(offer.id, 'nco-001');
      expect(offer.dealId, 'deal-002');
      expect(offer.merchantId, 'merchant-001');
      expect(offer.specialPrice, 9.99);
      expect(offer.isActive, true);
    });

    test('toJson 正确序列化所有字段', () {
      final offer = NewCustomerOffer.fromJson(baseJson);
      final json = offer.toJson();

      expect(json['id'], 'nco-001');
      expect(json['deal_id'], 'deal-002');
      expect(json['special_price'], 9.99);
      expect(json['is_active'], true);
    });

    test('fromJson -> toJson 往返序列化一致', () {
      final offer = NewCustomerOffer.fromJson(baseJson);
      final json = offer.toJson();
      final restored = NewCustomerOffer.fromJson(json);

      expect(restored.id, offer.id);
      expect(restored.specialPrice, offer.specialPrice);
    });

    test('copyWith 正确更新指定字段', () {
      final original = NewCustomerOffer.fromJson(baseJson);
      final updated = original.copyWith(specialPrice: 7.99, isActive: false);

      expect(updated.specialPrice, 7.99);
      expect(updated.isActive, false);
      expect(updated.id, original.id);
    });

    test('copyWith 不传参数时返回等值对象', () {
      final original = NewCustomerOffer.fromJson(baseJson);
      final copy = original.copyWith();

      expect(copy.specialPrice, original.specialPrice);
    });

    test('specialPrice 从整数 JSON 值也能正确解析', () {
      final offer = NewCustomerOffer.fromJson({...baseJson, 'special_price': 10});
      expect(offer.specialPrice, 10.0);
    });

    test('== 运算符基于 id 比较', () {
      final a = NewCustomerOffer.fromJson(baseJson);
      final b = NewCustomerOffer.fromJson({...baseJson, 'special_price': 1.0});
      expect(a, b);
    });

    test('toString 包含关键信息', () {
      final offer = NewCustomerOffer.fromJson(baseJson);
      final str = offer.toString();
      expect(str, contains('nco-001'));
      expect(str, contains('9.99'));
    });
  });

  // ============================================================
  // Promotion 模型测试
  // ============================================================
  group('Promotion', () {
    // 完整字段 JSON
    final fullJson = {
      'id': 'promo-001',
      'merchant_id': 'merchant-001',
      'deal_id': 'deal-003',
      'promo_type': 'spend_x_get_y',
      'min_spend': 30.0,
      'discount_amount': 5.0,
      'is_active': true,
      'start_time': '2026-03-03T00:00:00.000Z',
      'end_time': '2026-03-31T23:59:59.000Z',
      'title': 'Spend \$30 Get \$5 Off',
      'description': 'Limited time promotion',
      'usage_limit': 100,
      'per_user_limit': 1,
      'created_at': '2026-03-03T08:00:00.000Z',
      'updated_at': '2026-03-03T08:00:00.000Z',
    };

    // 最简 JSON（nullable 字段为 null）
    final minimalJson = {
      'id': 'promo-002',
      'merchant_id': 'merchant-001',
      'deal_id': null,
      'promo_type': 'spend_x_get_y',
      'min_spend': 50.0,
      'discount_amount': 8.0,
      'is_active': true,
      'start_time': null,
      'end_time': null,
      'title': null,
      'description': null,
      'usage_limit': null,
      'per_user_limit': null,
      'created_at': '2026-03-03T08:00:00.000Z',
      'updated_at': '2026-03-03T08:00:00.000Z',
    };

    test('fromJson 正确解析完整字段', () {
      final promo = Promotion.fromJson(fullJson);

      expect(promo.id, 'promo-001');
      expect(promo.merchantId, 'merchant-001');
      expect(promo.dealId, 'deal-003');
      expect(promo.promoType, PromoType.spendXGetY);
      expect(promo.minSpend, 30.0);
      expect(promo.discountAmount, 5.0);
      expect(promo.isActive, true);
      expect(promo.title, 'Spend \$30 Get \$5 Off');
      expect(promo.usageLimit, 100);
      expect(promo.perUserLimit, 1);
    });

    test('fromJson 正确处理 nullable 字段为 null', () {
      final promo = Promotion.fromJson(minimalJson);

      expect(promo.dealId, isNull);
      expect(promo.startTime, isNull);
      expect(promo.endTime, isNull);
      expect(promo.title, isNull);
      expect(promo.description, isNull);
      expect(promo.usageLimit, isNull);
      expect(promo.perUserLimit, isNull);
    });

    test('toJson 正确序列化完整字段', () {
      final promo = Promotion.fromJson(fullJson);
      final json = promo.toJson();

      expect(json['id'], 'promo-001');
      expect(json['promo_type'], 'spend_x_get_y');
      expect(json['min_spend'], 30.0);
      expect(json['discount_amount'], 5.0);
      expect(json['title'], 'Spend \$30 Get \$5 Off');
    });

    test('toJson 正确序列化 null 字段', () {
      final promo = Promotion.fromJson(minimalJson);
      final json = promo.toJson();

      expect(json['deal_id'], isNull);
      expect(json['start_time'], isNull);
      expect(json['end_time'], isNull);
      expect(json['title'], isNull);
    });

    test('fromJson -> toJson 往返序列化一致', () {
      final promo = Promotion.fromJson(fullJson);
      final json = promo.toJson();
      final restored = Promotion.fromJson(json);

      expect(restored.id, promo.id);
      expect(restored.minSpend, promo.minSpend);
      expect(restored.discountAmount, promo.discountAmount);
      expect(restored.promoType, promo.promoType);
    });

    test('copyWith 正确更新指定字段', () {
      final original = Promotion.fromJson(fullJson);
      final updated = original.copyWith(
        minSpend: 50.0,
        discountAmount: 10.0,
        isActive: false,
      );

      expect(updated.minSpend, 50.0);
      expect(updated.discountAmount, 10.0);
      expect(updated.isActive, false);
      // 未变更字段保持不变
      expect(updated.id, original.id);
      expect(updated.promoType, original.promoType);
    });

    test('copyWith 不传参数时返回等值对象', () {
      final original = Promotion.fromJson(fullJson);
      final copy = original.copyWith();

      expect(copy.minSpend, original.minSpend);
      expect(copy.dealId, original.dealId);
    });

    test('isCurrentlyActive: isActive=false 时返回 false', () {
      final promo = Promotion.fromJson({...fullJson, 'is_active': false});
      expect(promo.isCurrentlyActive, false);
    });

    test('isCurrentlyActive: 无时间限制的活动为 true', () {
      final promo = Promotion.fromJson(minimalJson);
      // start_time 和 end_time 均为 null，应视为永久有效
      expect(promo.isCurrentlyActive, true);
    });

    test('isCurrentlyActive: 已过期活动返回 false', () {
      final promo = Promotion.fromJson({
        ...fullJson,
        'end_time': '2020-01-01T00:00:00.000Z',
      });
      expect(promo.isCurrentlyActive, false);
    });

    test('isCurrentlyActive: 未开始活动返回 false', () {
      final promo = Promotion.fromJson({
        ...fullJson,
        'start_time': '2099-01-01T00:00:00.000Z',
        'end_time': '2099-12-31T00:00:00.000Z',
      });
      expect(promo.isCurrentlyActive, false);
    });

    test('isStoreWide: dealId 为 null 时返回 true', () {
      final promo = Promotion.fromJson(minimalJson);
      expect(promo.isStoreWide, true);
    });

    test('isStoreWide: dealId 非 null 时返回 false', () {
      final promo = Promotion.fromJson(fullJson);
      expect(promo.isStoreWide, false);
    });

    test('displayTitle: title 为空时自动生成', () {
      final promo = Promotion.fromJson(minimalJson);
      // minimalJson: minSpend=50, discountAmount=8
      expect(promo.displayTitle, 'Spend \$50 Get \$8 Off');
    });

    test('displayTitle: title 非空时返回 title', () {
      final promo = Promotion.fromJson(fullJson);
      expect(promo.displayTitle, 'Spend \$30 Get \$5 Off');
    });

    test('== 运算符基于 id 比较', () {
      final a = Promotion.fromJson(fullJson);
      final b = Promotion.fromJson({...fullJson, 'min_spend': 999.0});
      expect(a, b);
    });

    test('hashCode 基于 id', () {
      final a = Promotion.fromJson(fullJson);
      final b = Promotion.fromJson(fullJson);
      expect(a.hashCode, b.hashCode);
    });

    test('toString 包含关键信息', () {
      final promo = Promotion.fromJson(fullJson);
      final str = promo.toString();
      expect(str, contains('promo-001'));
      expect(str, contains('30.0'));
      expect(str, contains('5.0'));
    });
  });
}
