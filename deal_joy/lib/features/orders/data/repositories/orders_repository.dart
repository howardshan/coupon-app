import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
import '../models/order_model.dart';

class OrdersRepository {
  final SupabaseClient _client;

  OrdersRepository(this._client);

  Future<List<OrderModel>> fetchUserOrders(String userId) async {
    try {
      final data = await _client
          .from('orders')
          .select(
              'id, user_id, deal_id, coupon_id, quantity, total_amount, status, payment_intent_id, created_at, deals(id, title, image_urls, merchants(name))')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return (data as List).map((e) => OrderModel.fromJson(e)).toList();
    } on PostgrestException catch (e) {
      throw AppException('Failed to load orders: ${e.message}', code: e.code);
    }
  }

  Future<OrderModel> fetchOrderById(String orderId) async {
    try {
      final data = await _client
          .from('orders')
          .select(
              'id, user_id, deal_id, coupon_id, quantity, total_amount, status, payment_intent_id, created_at, deals(id, title, image_urls, merchants(name))')
          .eq('id', orderId)
          .single();
      return OrderModel.fromJson(data);
    } on PostgrestException catch (e) {
      throw AppException('Order not found: ${e.message}', code: e.code);
    }
  }

  Future<void> requestRefund(String orderId) async {
    try {
      await _client
          .from('orders')
          .update({'status': 'refund_requested'}).eq('id', orderId);
    } on PostgrestException catch (e) {
      throw AppException('Failed to request refund: ${e.message}',
          code: e.code);
    }
  }

  Future<Map<String, dynamic>> fetchCoupon(String couponId) async {
    try {
      final data = await _client
          .from('coupons')
          .select()
          .eq('id', couponId)
          .single();
      return data;
    } on PostgrestException catch (e) {
      throw AppException('Coupon not found: ${e.message}', code: e.code);
    }
  }
}
