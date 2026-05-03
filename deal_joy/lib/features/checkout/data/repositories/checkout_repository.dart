import 'package:flutter_stripe/flutter_stripe.dart';
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
  /// 购物车结账入口：检查 deal 是否仍上架且未过 listing 截止时间；返回不可购买的标题（按 deal 去重）
  Future<List<String>> validateCartDealsPurchasable(
    List<CartItemModel> items,
  ) async {
    if (items.isEmpty) return [];
    final dealIds = items.map((e) => e.dealId).toSet().toList();
    final res = await _client
        .from('deals')
        .select('id, title, expires_at, is_active')
        .inFilter('id', dealIds);
    final rows = (res as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final byId = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final id = r['id'] as String?;
      if (id != null && id.isNotEmpty) byId[id] = r;
    }
    final bad = <String>[];
    final seen = <String>{};
    for (final id in dealIds) {
      if (id.isEmpty) continue;
      final row = byId[id];
      if (row == null) {
        final match = items.where((i) => i.dealId == id).firstOrNull;
        final title = match?.dealTitle ?? '';
        if (seen.add(id)) bad.add(title.isNotEmpty ? title : 'Deal');
        continue;
      }
      final active = row['is_active'] as bool? ?? false;
      final expStr = row['expires_at'] as String?;
      final exp =
          expStr != null && expStr.isNotEmpty ? DateTime.tryParse(expStr) : null;
      final expired = exp != null && DateTime.now().isAfter(exp);
      if (!active || expired) {
        final title = row['title'] as String? ?? '';
        if (seen.add(id)) bad.add(title.isNotEmpty ? title : 'Deal');
      }
    }
    return bad;
  }

  Future<CheckoutResult> checkoutCart({
    required String userId,
    required List<CartItemModel> cartItems,
    List<String>? cartItemIds,
    String paymentMethod = 'card', // 'card' | 'google' | 'apple'
    BillingDetails? billingDetails,
    double storeCreditUsed = 0.0, // Store Credit 抵扣金额
    String? savedPaymentMethodId, // 已保存卡的 PM ID
    String? savedCardCvc, // 已保存卡重新输入的 CVV
    bool saveCard = false, // 是否保存新卡片供下次使用
    // create-payment-intent 返回后的回调，用于把后端权威税费金额同步给 UI
    // 签名：(subtotal, serviceFee, totalTax, totalAmount)
    void Function(double subtotal, double serviceFee, double totalTax, double totalAmount)?
        onPaymentBreakdown,
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

    // 2. 调用新版 create-payment-intent（v3 多 deal 版本），传入 Store Credit
    final piResponse = await _createPaymentIntentV3(
      items: items,
      userId: userId,
      paymentMethod: paymentMethod,
      storeCreditUsed: storeCreditUsed,
      saveCard: saveCard,
    );

    final serviceFeeTotal = (piResponse['serviceFee'] as num?)?.toDouble() ?? 0.0;
    final subtotal = (piResponse['subtotal'] as num?)?.toDouble() ?? 0.0;
    final totalAmount = (piResponse['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final totalTax = (piResponse['totalTax'] as num?)?.toDouble() ?? 0.0;

    // 通知 UI 最终权威金额（用于刷新 Tax 行和 Total 行，以便 Stripe PaymentSheet 弹出前 UI 值一致）
    onPaymentBreakdown?.call(subtotal, serviceFeeTotal, totalTax, totalAmount);

    // 检查 Store Credit 是否全额覆盖（后端返回特殊标记）
    final fullyCovered = piResponse['fullyCoveredByCredit'] as bool? ?? false;

    if (fullyCovered) {
      // Store Credit 全额覆盖，跳过 Stripe，直接创建订单
      final orderResult = await _createOrderV3(
        paymentIntentId: 'store_credit_${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        items: items,
        serviceFeeTotal: serviceFeeTotal,
        subtotal: subtotal,
        totalAmount: totalAmount,
        totalTax: totalTax,
        cartItemIds: cartItemIds,
        storeCreditUsed: storeCreditUsed,
        skipStripeVerification: true,
      );
      return orderResult;
    }

    final clientSecret = piResponse['clientSecret'] as String? ?? '';
    final paymentIntentId = piResponse['paymentIntentId'] as String? ?? '';

    // 从后端响应中读取 Stripe Customer 信息（用于显示已保存的卡片）
    final customerId = piResponse['customerId'] as String?;
    final ephemeralKey = piResponse['ephemeralKey'] as String?;

    // 3. 根据支付方式调用对应的 Stripe API
    await _processPayment(
      clientSecret: clientSecret,
      paymentMethod: paymentMethod,
      amount: totalAmount,
      customerId: customerId,
      ephemeralKey: ephemeralKey,
      billingDetails: billingDetails,
      savedPaymentMethodId: savedPaymentMethodId,
      savedCardCvc: savedCardCvc,
    );

    // 4. 调用 create-order-v3 Edge Function 创建订单
    final orderResult = await _createOrderV3(
      paymentIntentId: paymentIntentId,
      userId: userId,
      items: items,
      serviceFeeTotal: serviceFeeTotal,
      subtotal: subtotal,
      totalAmount: totalAmount,
      totalTax: totalTax,
      cartItemIds: cartItemIds,
      storeCreditUsed: storeCreditUsed,
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
    String paymentMethod = 'card',
    BillingDetails? billingDetails,
    double storeCreditUsed = 0.0, // Store Credit 抵扣金额
    String? savedPaymentMethodId, // 已保存卡的 PM ID
    String? savedCardCvc, // 已保存卡重新输入的 CVV
    bool saveCard = false, // 是否保存新卡片供下次使用
    // create-payment-intent 返回后的回调，用于把后端权威税费金额同步给 UI
    void Function(double subtotal, double serviceFee, double totalTax, double totalAmount)?
        onPaymentBreakdown,
  }) async {
    if (userId.isEmpty) {
      throw const PaymentException('User not authenticated', code: 'unauthenticated');
    }

    // V3: 单 deal 也走 items 数组格式
    // 构建 items：quantity 张同一 deal
    final items = List.generate(quantity, (_) => {
      'dealId': dealId,
      'unitPrice': unitPrice,
      if (promoCode != null) 'promoCode': promoCode,
    });

    // 1. 创建 PaymentIntent（V3 格式，传入支付方式和 Store Credit）
    final piResponse = await _createPaymentIntentV3(
      items: items,
      userId: userId,
      paymentMethod: paymentMethod,
      storeCreditUsed: storeCreditUsed,
      saveCard: saveCard,
    );

    final totalAmount = (piResponse['totalAmount'] as num?)?.toDouble() ?? unitPrice * quantity;
    final serviceFeeTotal = (piResponse['serviceFee'] as num?)?.toDouble() ?? 0.99;
    final subtotal = (piResponse['subtotal'] as num?)?.toDouble() ?? unitPrice * quantity;
    final singleTotalTax = (piResponse['totalTax'] as num?)?.toDouble() ?? 0.0;

    // 通知 UI 最终权威金额
    onPaymentBreakdown?.call(subtotal, serviceFeeTotal, singleTotalTax, totalAmount);

    // 检查 Store Credit 是否全额覆盖
    final fullyCovered = piResponse['fullyCoveredByCredit'] as bool? ?? false;

    final orderItems = items.map((item) => {
      'dealId': item['dealId'],
      'unitPrice': item['unitPrice'],
      if (purchasedMerchantId != null) 'purchasedMerchantId': purchasedMerchantId,
      if (selectedOptions != null) 'selectedOptions': selectedOptions,
    }).toList();

    if (fullyCovered) {
      // Store Credit 全额覆盖，跳过 Stripe
      return await _createOrderV3(
        paymentIntentId: 'store_credit_${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        items: orderItems,
        serviceFeeTotal: serviceFeeTotal,
        subtotal: subtotal,
        totalAmount: totalAmount,
        totalTax: singleTotalTax,
        cartItemIds: [],
        storeCreditUsed: storeCreditUsed,
        skipStripeVerification: true,
      );
    }

    final clientSecret = piResponse['clientSecret'] as String? ?? '';
    final paymentIntentId = piResponse['paymentIntentId'] as String? ?? '';
    // 从后端响应中读取 Stripe Customer 信息（用于显示已保存的卡片）
    final customerId = piResponse['customerId'] as String?;
    final ephemeralKey = piResponse['ephemeralKey'] as String?;

    // 2. 根据支付方式调用对应的 Stripe API
    await _processPayment(
      clientSecret: clientSecret,
      paymentMethod: paymentMethod,
      amount: totalAmount,
      customerId: customerId,
      ephemeralKey: ephemeralKey,
      billingDetails: billingDetails,
      savedPaymentMethodId: savedPaymentMethodId,
      savedCardCvc: savedCardCvc,
    );

    // 3. 调用 create-order-v3 创建订单（触发器自动创建 coupons）
    return await _createOrderV3(
      paymentIntentId: paymentIntentId,
      userId: userId,
      items: orderItems,
      serviceFeeTotal: serviceFeeTotal,
      subtotal: subtotal,
      totalAmount: totalAmount,
      totalTax: singleTotalTax,
      cartItemIds: [],
      storeCreditUsed: storeCreditUsed,
    );
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

  /// 调用新版 create-payment-intent（V3 多 deal），支持 Store Credit 抵扣
  Future<Map<String, dynamic>> _createPaymentIntentV3({
    required List<Map<String, dynamic>> items,
    required String userId,
    String paymentMethod = 'card',
    double storeCreditUsed = 0.0,
    bool saveCard = false,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-payment-intent',
        body: {
          'items': items,
          'userId': userId,
          'paymentMethod': paymentMethod,
          if (storeCreditUsed > 0) 'storeCreditUsed': storeCreditUsed,
          if (saveCard) 'saveCard': true,
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

  /// 根据支付方式调用不同的 Stripe API
  /// paymentMethod: 'card' | 'google' | 'apple'
  /// customerId / ephemeralKey 用于 PaymentSheet 显示已保存的卡片
  /// billingDetails 用于信用卡支付时携带账单地址
  /// savedPaymentMethodId: 已保存卡的 Stripe PM ID（有值时直接用该卡支付，不走 CardField）
  Future<void> _processPayment({
    required String clientSecret,
    required String paymentMethod,
    required double amount,
    String? customerId,
    String? ephemeralKey,
    String label = 'Crunchy Plum',
    BillingDetails? billingDetails,
    String? savedPaymentMethodId,
    String? savedCardCvc,
  }) async {
    if (paymentMethod == 'google') {
      // Google Pay — Platform Pay API
      await Stripe.instance.confirmPlatformPayPaymentIntent(
        clientSecret: clientSecret,
        confirmParams: PlatformPayConfirmParams.googlePay(
          googlePay: GooglePayParams(
            testEnv: false,
            merchantName: 'Crunchy Plum',
            merchantCountryCode: 'US',
            currencyCode: 'usd',
          ),
        ),
      );
    } else if (paymentMethod == 'apple') {
      // Apple Pay — Platform Pay API（仅 iOS）
      await Stripe.instance.confirmPlatformPayPaymentIntent(
        clientSecret: clientSecret,
        confirmParams: PlatformPayConfirmParams.applePay(
          applePay: ApplePayParams(
            merchantCountryCode: 'US',
            currencyCode: 'usd',
            cartItems: [
              ApplePayCartSummaryItem.immediate(
                label: label,
                amount: amount.toStringAsFixed(2),
              ),
            ],
          ),
        ),
      );
    } else if (savedPaymentMethodId != null && savedPaymentMethodId.isNotEmpty) {
      // 已保存卡 — 用 PM ID + 重新输入的 CVV 确认支付
      await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: clientSecret,
        data: PaymentMethodParams.cardFromMethodId(
          paymentMethodData: PaymentMethodDataCardFromMethod(
            paymentMethodId: savedPaymentMethodId,
            cvc: savedCardCvc,
          ),
        ),
      );
    } else {
      // 新信用卡 — 通过 CardField 收集卡片信息后 confirmPayment
      await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: clientSecret,
        data: PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(
            billingDetails: billingDetails,
          ),
        ),
      );
    }
  }

  /// 调用 create-order-v3 Edge Function 创建多 deal 订单，支持 Store Credit 抵扣
  Future<CheckoutResult> _createOrderV3({
    required String paymentIntentId,
    required String userId,
    required List<Map<String, dynamic>> items,
    required double serviceFeeTotal,
    required double subtotal,
    required double totalAmount,
    double totalTax = 0.0,
    List<String>? cartItemIds,
    double storeCreditUsed = 0.0,
    bool skipStripeVerification = false, // Store Credit 全额覆盖时跳过 Stripe 验证
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
          'totalTax': totalTax,
          'cartItemIds': cartItemIds,
          if (storeCreditUsed > 0) 'storeCreditUsed': storeCreditUsed,
          if (skipStripeVerification) 'skipStripeVerification': true,
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
