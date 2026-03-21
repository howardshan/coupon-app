import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../cart/data/models/cart_item_model.dart';

/// 结账结果
class CheckoutResult {
  final String orderId;
  final String? orderNumber;
  final int? itemCount;

  const CheckoutResult({
    required this.orderId,
    this.orderNumber,
    this.itemCount,
  });
}

/// 优惠码验证结果
class PromoCodeResult {
  final String code;
  final String discountType; // 'percentage' | 'fixed'
  final double discountValue;
  final double? maxDiscount;
  final double calculatedDiscount; // 根据 subtotal 计算出的实际折扣金额

  const PromoCodeResult({
    required this.code,
    required this.discountType,
    required this.discountValue,
    this.maxDiscount,
    required this.calculatedDiscount,
  });

  /// 折扣描述文字
  String get label => discountType == 'percentage'
      ? '${discountValue.toStringAsFixed(0)}% off'
      : '\$${discountValue.toStringAsFixed(2)} off';
}

class CheckoutRepository {
  final SupabaseClient _client;

  CheckoutRepository(this._client);

  // ────────────────────────────────────────────────────────────────
  // V3 购物车多 deal 结账
  // ────────────────────────────────────────────────────────────────

  /// V3 购物车结账：
  /// 1. 调新版 create-payment-intent（传 items 数组）
  /// 2. 弹出 Stripe 支付表单
  /// 3. 调 create-order-v3 Edge Function 写入订单
  /// 4. 返回 [CheckoutResult]
  Future<CheckoutResult> checkoutCart({
    required String userId,
    required List<CartItemModel> cartItems,
    List<String>? cartItemIds, // 用于清理购物车 DB 记录（可选）
  }) async {
    if (userId.isEmpty) {
      throw const PaymentException('User not authenticated', code: 'unauthenticated');
    }
    if (cartItems.isEmpty) {
      throw const PaymentException('Cart is empty', code: 'empty_cart');
    }

    // 1. 构建 items 数组传给 Edge Function
    final items = cartItems
        .map((c) => {
              'dealId': c.dealId,
              'unitPrice': c.unitPrice,
              if (c.purchasedMerchantId != null)
                'purchasedMerchantId': c.purchasedMerchantId,
              if (c.selectedOptions != null)
                'selectedOptions': c.selectedOptions,
            })
        .toList();

    // 2. 调用新版 create-payment-intent（v3 多 deal 版本）
    final piResponse = await _createPaymentIntentV3(
      items: items,
      userId: userId,
    );

    final clientSecret = piResponse['clientSecret'] as String? ?? '';
    final paymentIntentId = piResponse['paymentIntentId'] as String? ?? '';
    final serviceFeeTotal = (piResponse['serviceFee'] as num?)?.toDouble() ?? 0.0;
    final subtotal = (piResponse['subtotal'] as num?)?.toDouble() ?? 0.0;
    final totalAmount = (piResponse['totalAmount'] as num?)?.toDouble() ?? 0.0;

    // 3. 弹出 Stripe 支付表单
    await _presentPaymentSheet(clientSecret);

    // 4. 调用 create-order-v3 Edge Function 创建订单
    final orderResult = await _createOrderV3(
      paymentIntentId: paymentIntentId,
      userId: userId,
      items: items,
      serviceFeeTotal: serviceFeeTotal,
      subtotal: subtotal,
      totalAmount: totalAmount,
      cartItemIds: cartItemIds,
    );

    return orderResult;
  }

  // ────────────────────────────────────────────────────────────────
  // 单 deal 快速购买（兼容 Deal 详情页 Buy Now）
  // ────────────────────────────────────────────────────────────────

  /// 单 deal 快速购买（Buy Now 入口保持不变）：
  /// 1. 调旧版 create-payment-intent
  /// 2. 弹出 Stripe 支付表单
  /// 3. 直接 INSERT orders 表
  Future<CheckoutResult> checkoutSingleDeal({
    required String userId,
    required String dealId,
    required double unitPrice,
    required int quantity,
    String? purchasedMerchantId,
    List<Map<String, dynamic>>? selectedOptions,
    String? promoCode,
  }) async {
    if (userId.isEmpty) {
      throw const PaymentException('User not authenticated', code: 'unauthenticated');
    }

    final total = unitPrice * quantity;

    // 1. 创建 PaymentIntent（旧版单 deal）
    final piResponse = await _createPaymentIntentSingle(
      amount: total,
      dealId: dealId,
      userId: userId,
      promoCode: promoCode,
    );

    final clientSecret = piResponse['clientSecret'] as String? ?? '';
    final paymentIntentId = piResponse['paymentIntentId'] as String? ?? '';
    final captureMethod = piResponse['captureMethod'] as String? ?? 'automatic';

    // 2. 弹出 Stripe 支付表单
    await _presentPaymentSheet(clientSecret);

    // 3. 直接写入 orders 表
    final orderId = await _insertOrder(
      userId: userId,
      dealId: dealId,
      quantity: quantity,
      total: total,
      paymentIntentId: paymentIntentId,
      purchasedMerchantId: purchasedMerchantId,
      selectedOptions: selectedOptions,
      captureMethod: captureMethod,
    );

    return CheckoutResult(orderId: orderId);
  }

  // ────────────────────────────────────────────────────────────────
  // 优惠码验证（保持不变）
  // ────────────────────────────────────────────────────────────────

  /// 验证优惠码并计算折扣金额
  /// 如果优惠码无效/过期/不适用，抛出 [AppException]
  Future<PromoCodeResult> validatePromoCode({
    required String code,
    required String dealId,
    required double subtotal,
  }) async {
    try {
      // 强制过滤 is_active=true，避免 RLS 绕过
      final data = await _client
          .from('promo_codes')
          .select()
          .eq('code', code.toUpperCase().trim())
          .eq('is_active', true)
          .maybeSingle();

      if (data == null) {
        throw const AppException('Invalid coupon code');
      }

      // 检查是否过期
      final expiresAt = data['expires_at'] as String?;
      if (expiresAt != null && DateTime.parse(expiresAt).isBefore(DateTime.now())) {
        throw const AppException('This coupon has expired');
      }

      // 检查使用次数
      final maxUses = data['max_uses'] as int?;
      final currentUses = data['current_uses'] as int? ?? 0;
      if (maxUses != null && currentUses >= maxUses) {
        throw const AppException('This coupon has reached its usage limit');
      }

      // 检查 deal 限制（null 表示适用于所有 deal）
      final promoDealId = data['deal_id'] as String?;
      if (promoDealId != null && promoDealId != dealId) {
        throw const AppException('This coupon is not valid for this deal');
      }

      // 检查最低消费
      final minOrder = (data['min_order_amount'] as num?)?.toDouble() ?? 0;
      if (subtotal < minOrder) {
        throw AppException(
          'Minimum order \$${minOrder.toStringAsFixed(2)} required for this coupon',
        );
      }

      // 计算折扣
      final discountType = data['discount_type'] as String? ?? 'fixed';
      final discountValue = (data['discount_value'] as num?)?.toDouble() ?? 0.0;
      final maxDiscount = (data['max_discount'] as num?)?.toDouble();

      double calculatedDiscount;
      if (discountType == 'percentage') {
        calculatedDiscount = subtotal * (discountValue / 100);
        if (maxDiscount != null && calculatedDiscount > maxDiscount) {
          calculatedDiscount = maxDiscount;
        }
      } else {
        calculatedDiscount = discountValue;
      }

      // 折扣不能超过小计
      if (calculatedDiscount > subtotal) {
        calculatedDiscount = subtotal;
      }

      return PromoCodeResult(
        code: code.toUpperCase().trim(),
        discountType: discountType,
        discountValue: discountValue,
        maxDiscount: maxDiscount,
        calculatedDiscount: calculatedDiscount,
      );
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Failed to validate coupon: $e');
    }
  }

  // ────────────────────────────────────────────────────────────────
  // 私有辅助方法
  // ────────────────────────────────────────────────────────────────

  /// 调用新版 create-payment-intent（V3 多 deal）
  Future<Map<String, dynamic>> _createPaymentIntentV3({
    required List<Map<String, dynamic>> items,
    required String userId,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-payment-intent',
        body: {
          'items': items,
          'userId': userId,
        },
      );

      if (response.status != 200) {
        throw PaymentException(
          response.data?['error'] as String? ?? 'Payment setup failed',
          code: 'payment_intent_failed',
        );
      }

      return response.data as Map<String, dynamic>;
    } on PaymentException {
      rethrow;
    } catch (e) {
      throw PaymentException('Failed to create payment: $e');
    }
  }

  /// 调用旧版 create-payment-intent（单 deal，兼容 Buy Now）
  Future<Map<String, dynamic>> _createPaymentIntentSingle({
    required double amount,
    required String dealId,
    required String userId,
    String? promoCode,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-payment-intent',
        body: {
          'amount': amount,
          'currency': 'usd',
          'dealId': dealId,
          'userId': userId,
          'promoCode': promoCode,
        },
      );

      if (response.status != 200) {
        throw PaymentException(
          response.data?['error'] as String? ?? 'Payment setup failed',
          code: 'payment_intent_failed',
        );
      }

      return response.data as Map<String, dynamic>;
    } on PaymentException {
      rethrow;
    } catch (e) {
      throw PaymentException('Failed to create payment: $e');
    }
  }

  /// 初始化并弹出 Stripe 支付表单
  Future<void> _presentPaymentSheet(String clientSecret) async {
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'DealJoy',
        style: ThemeMode.light,
      ),
    );

    // 用户取消会抛出 StripeException，向上传播
    await Stripe.instance.presentPaymentSheet();
  }

  /// 调用 create-order-v3 Edge Function 创建多 deal 订单
  Future<CheckoutResult> _createOrderV3({
    required String paymentIntentId,
    required String userId,
    required List<Map<String, dynamic>> items,
    required double serviceFeeTotal,
    required double subtotal,
    required double totalAmount,
    List<String>? cartItemIds,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-order-v3',
        body: {
          'paymentIntentId': paymentIntentId,
          'userId': userId,
          'items': items,
          'serviceFeeTotal': serviceFeeTotal,
          'subtotal': subtotal,
          'totalAmount': totalAmount,
          'cartItemIds': cartItemIds,
        },
      );

      if (response.status != 200) {
        throw PaymentException(
          response.data?['error'] as String? ??
              'Payment succeeded but order creation failed. Please contact support.',
          code: 'order_create_failed',
        );
      }

      final data = response.data as Map<String, dynamic>;
      return CheckoutResult(
        orderId: data['orderId'] as String? ?? '',
        orderNumber: data['orderNumber'] as String?,
        itemCount: data['itemCount'] as int?,
      );
    } on PaymentException {
      rethrow;
    } catch (e) {
      throw PaymentException(
        'Payment succeeded but order creation failed. '
        'Please contact support. Error: $e',
        code: 'order_create_failed',
      );
    }
  }

  /// 直接 INSERT orders 表（旧版单 deal，Buy Now 用）
  Future<String> _insertOrder({
    required String userId,
    required String dealId,
    required int quantity,
    required double total,
    required String paymentIntentId,
    String? purchasedMerchantId,
    List<Map<String, dynamic>>? selectedOptions,
    String captureMethod = 'automatic',
  }) async {
    try {
      final isManualCapture = captureMethod == 'manual';
      final orderData = {
        'user_id': userId,
        'deal_id': dealId,
        'quantity': quantity,
        'unit_price': total / quantity,
        'total_amount': total,
        'status': isManualCapture ? 'authorized' : 'unused',
        'payment_intent_id': paymentIntentId,
        'capture_method': captureMethod,
        'is_captured': !isManualCapture,
        'purchased_merchant_id': purchasedMerchantId,
        'selected_options': selectedOptions?.isNotEmpty == true ? selectedOptions : null,
      };
      final orderRes =
          await _client.from('orders').insert(orderData).select('id').single();

      return orderRes['id'] as String? ?? '';
    } catch (e) {
      throw PaymentException(
        'Payment succeeded but order creation failed. '
        'Please contact support. Error: $e',
        code: 'order_insert_failed',
      );
    }
  }
}
