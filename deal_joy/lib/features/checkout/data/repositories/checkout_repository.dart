import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';

class CheckoutResult {
  final String orderId;
  const CheckoutResult({required this.orderId});
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
  }) async {
    // 1. Call Edge Function to create PaymentIntent
    final response = await _createPaymentIntent(
      amount: total,
      dealId: dealId,
      userId: userId,
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
    );

    return CheckoutResult(orderId: orderId);
  }

  Future<Map<String, dynamic>> _createPaymentIntent({
    required double amount,
    required String dealId,
    required String userId,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-payment-intent',
        body: {
          'amount': amount,
          'currency': 'usd',
          'dealId': dealId,
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
  }) async {
    try {
      final orderRes = await _client.from('orders').insert({
        'user_id': userId,
        'deal_id': dealId,
        'quantity': quantity,
        'unit_price': total / quantity,
        'total_amount': total,
        'status': 'unused',
        'payment_intent_id': paymentIntentId,
      }).select('id').single();

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
