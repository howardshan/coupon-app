import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
// FunctionException 已在 supabase_flutter 中导出，无需额外导入
import '../models/order_detail_model.dart';
import '../models/order_model.dart';

class OrdersRepository {
  final SupabaseClient _client;

  OrdersRepository(this._client);

  Future<List<OrderModel>> fetchUserOrders(String userId) async {
    try {
      final data = await _client
          .from('orders')
          .select(
            'id, user_id, deal_id, coupon_id, quantity, total_amount, status, payment_intent_id, refund_reason, created_at, order_number, refund_requested_at, refunded_at, refund_rejected_at, deals(id, title, image_urls, merchants(name)), coupons!fk_orders_coupon_id(expires_at)',
          )
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
            'id, user_id, deal_id, coupon_id, quantity, total_amount, status, payment_intent_id, refund_reason, created_at, order_number, refund_requested_at, refunded_at, refund_rejected_at, deals(id, title, image_urls, merchants(name)), coupons!fk_orders_coupon_id(expires_at)',
          )
          .eq('id', orderId)
          .single();
      return OrderModel.fromJson(data);
    } on PostgrestException catch (e) {
      throw AppException('Order not found: ${e.message}', code: e.code);
    }
  }

  /// 从 user-order-detail Edge Function 获取订单详情（含时间线、支付状态、券码等）
  /// 将 access_token 放入 body，避免网关不转发 Authorization 导致 401
  Future<OrderDetailModel> fetchOrderDetailFromApi(String orderId) async {
    try {
      final token = _client.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) {
        throw const AppException(
          'Not signed in. Please sign in and retry.',
          code: 'unauthorized',
        );
      }
      final res = await _client.functions.invoke(
        'user-order-detail',
        body: {'order_id': orderId, 'access_token': token},
      );
      if (res.data == null) {
        throw AppException(
          res.status == 404 ? 'Order not found' : 'Failed to load order detail',
          code: res.status == 404 ? 'not_found' : 'server_error',
        );
      }
      final data = res.data as Map<String, dynamic>;
      if (data.containsKey('error')) {
        throw AppException(
          data['message'] as String? ?? 'Request failed',
          code: data['error'] as String? ?? 'error',
        );
      }
      final orderJson = data['order'];
      if (orderJson == null || orderJson is! Map<String, dynamic>) {
        throw const AppException('Invalid response', code: 'invalid_response');
      }
      return OrderDetailModel.fromJson(orderJson);
    } on AppException {
      rethrow;
    } on PostgrestException catch (e) {
      throw AppException('Failed to load order: ${e.message}', code: e.code);
    }
  }

  /// 仅提交退款申请（状态改为 refund_requested），不调用 Stripe；审核通过由 Admin 调用退款
  Future<void> requestRefund(String orderId, {String? reason}) async {
    try {
      await _client.from('orders').update({
        'status': 'refund_requested',
        'refund_requested_at': DateTime.now().toUtc().toIso8601String(),
        if (reason != null && reason.isNotEmpty) 'refund_reason': reason,
      }).eq('id', orderId);
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to request refund: ${e.message}',
        code: e.code,
      );
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

  /// 核销后退款申请 — 调用 submit-refund-request Edge Function
  /// [orderId] 订单 ID
  /// [reason] 退款原因（必填，min 10 chars，由 UI 层保证）
  Future<void> submitPostUseRefundRequest({
    required String orderId,
    required String reason,
  }) async {
    try {
      final token = _client.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) {
        throw const AppException(
          'Not signed in. Please sign in and retry.',
          code: 'unauthorized',
        );
      }
      final res = await _client.functions.invoke(
        'submit-refund-request',
        body: {
          'orderId': orderId,
          'reason': reason,
          'access_token': token,
        },
      );
      if (res.data == null) {
        throw AppException(
          'Failed to submit refund request',
          code: 'server_error',
        );
      }
      final data = res.data as Map<String, dynamic>;
      if (data.containsKey('error')) {
        throw AppException(
          data['message'] as String? ?? data['error'] as String? ?? 'Request failed',
          code: data['error'] as String? ?? 'error',
        );
      }
    } on AppException {
      rethrow;
    } on FunctionException catch (e) {
      final details = e.details;
      String message;
      if (details is Map && details.containsKey('message')) {
        message = details['message'].toString();
      } else if (details is Map && details.containsKey('error')) {
        message = details['error'].toString();
      } else {
        message = 'Failed to submit refund request (${e.status})';
      }
      throw AppException(message);
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Refund request failed: $e');
    }
  }
}
