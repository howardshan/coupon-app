import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';

class CheckoutResult {
  final String orderId;
  const CheckoutResult({required this.orderId});
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

  /// 获取折扣描述文字
  String get label => discountType == 'percentage'
      ? '${discountValue.toStringAsFixed(0)}% off'
      : '\$${discountValue.toStringAsFixed(2)} off';
}

class CheckoutRepository {
  final SupabaseClient _client;

  CheckoutRepository(this._client);

  /// Full checkout flow: create payment intent → present Stripe sheet → insert order.
  /// Returns [CheckoutResult] with the new order ID on success.
  /// Throws [PaymentException] on failure or rethrows [StripeException] on cancel.
  Future<CheckoutResult> checkout({
    required String userId,
    required String dealId,
    required int quantity,
    required double total,
    String? promoCode, // P0 fix: 将优惠码传给服务端，让 Edge Function 进行服务端价格验证
    String? purchasedMerchantId, // brand deal 用户选择的门店 ID
    List<Map<String, dynamic>>? selectedOptions, // 选项组快照
  }) async {
    // P0 fix: userId 不能为空串，否则订单会插入错误数据
    if (userId.isEmpty) {
      throw const PaymentException('User not authenticated', code: 'unauthenticated');
    }

    // 1. Call Edge Function to create PaymentIntent
    final response = await _createPaymentIntent(
      amount: total,
      dealId: dealId,
      userId: userId,
      promoCode: promoCode,
    );

    final clientSecret = response['clientSecret'] as String;
    final paymentIntentId = response['paymentIntentId'] as String;

    // 2. Initialize & present Stripe payment sheet
    await _presentPaymentSheet(clientSecret);

    // 3. Payment succeeded — create order record
    //    coupon_id is auto-filled by the on_order_created DB trigger
    final orderId = await _createOrder(
      userId: userId,
      dealId: dealId,
      quantity: quantity,
      total: total,
      paymentIntentId: paymentIntentId,
      purchasedMerchantId: purchasedMerchantId,
      selectedOptions: selectedOptions,
    );

    return CheckoutResult(orderId: orderId);
  }

  /// 验证优惠码并计算折扣金额
  /// 如果优惠码无效/过期/不适用，抛出 [AppException]
  Future<PromoCodeResult> validatePromoCode({
    required String code,
    required String dealId,
    required double subtotal,
  }) async {
    try {
      // P0 fix: 在查询层也强制过滤 is_active=true，不能仅依赖 RLS。
      // RLS 在 service_role 连接或策略变更时可能被绕过。
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
      final discountType = data['discount_type'] as String;
      final discountValue = (data['discount_value'] as num).toDouble();
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

  Future<Map<String, dynamic>> _createPaymentIntent({
    required double amount,
    required String dealId,
    required String userId,
    String? promoCode, // P0 fix: 传递优惠码给服务端做价格验证，防止客户端篡改总额
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-payment-intent',
        body: {
          'amount': amount,
          'currency': 'usd',
          'dealId': dealId,
          'userId': userId,
          'promoCode': ?promoCode,
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

  Future<void> _presentPaymentSheet(String clientSecret) async {
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'DealJoy',
        style: ThemeMode.light,
      ),
    );

    // This throws StripeException if user cancels — let it propagate
    await Stripe.instance.presentPaymentSheet();
  }

  Future<String> _createOrder({
    required String userId,
    required String dealId,
    required int quantity,
    required double total,
    required String paymentIntentId,
    String? purchasedMerchantId,
    List<Map<String, dynamic>>? selectedOptions,
  }) async {
    try {
      final orderData = {
        'user_id': userId,
        'deal_id': dealId,
        'quantity': quantity,
        'unit_price': total / quantity,
        'total_amount': total,
        'status': 'unused',
        'payment_intent_id': paymentIntentId,
        if (purchasedMerchantId != null)
          'purchased_merchant_id': purchasedMerchantId,
        if (selectedOptions != null && selectedOptions.isNotEmpty)
          'selected_options': selectedOptions,
      };
      final orderRes = await _client.from('orders').insert(orderData).select('id').single();

      return orderRes['id'] as String;
    } catch (e) {
      throw PaymentException(
        'Payment succeeded but order creation failed. '
        'Please contact support. Error: $e',
        code: 'order_insert_failed',
      );
    }
  }
}
