import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
// FunctionException 已在 supabase_flutter 中导出，无需额外导入
import '../models/order_detail_model.dart';
import '../models/order_model.dart';

/// V3 订单查询 select — 含 order_items join deals/merchants/coupons
const _orderSelect =
    'id, user_id, order_number, total_amount, items_amount, service_fee_total, '
    'payment_intent_id, store_credit_used, paid_at, created_at, '
    'order_items('
    '  id, deal_id, unit_price, service_fee, customer_status, merchant_status, '
    '  coupon_id, redeemed_at, refunded_at, refund_method, '
    '  deals(id, title, image_urls, merchants(id, name)), '
    '  coupons!order_items_coupon_id_fkey(id, qr_code, coupon_code, status, expires_at)'
    ')';

class OrdersRepository {
  final SupabaseClient _client;

  OrdersRepository(this._client);

  /// 获取当前用户全部订单，每个订单含 order_items 列表
  Future<List<OrderModel>> fetchUserOrders(String userId) async {
    try {
      final data = await _client
          .from('orders')
          .select(_orderSelect)
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return (data as List).map((e) => OrderModel.fromJson(e)).toList();
    } on PostgrestException catch (e) {
      throw AppException('Failed to load orders: ${e.message}', code: e.code);
    }
  }

  /// 获取单个订单详情（含 order_items）
  Future<OrderModel> fetchOrderById(String orderId) async {
    try {
      final data = await _client
          .from('orders')
          .select(_orderSelect)
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

  /// V3：通过 orderItemId 请求退款，调用 create-refund Edge Function
  /// [refundMethod] 退款方式：'store_credit' | 'original_payment'
  /// [reason] 退款原因，可选
  Future<Map<String, dynamic>> requestItemRefund(
    String orderItemId,
    String refundMethod, {
    String? reason,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-refund',
        body: {
          'orderItemId': orderItemId,
          'refundMethod': refundMethod,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );

      final rawData = response.data;
      if (rawData is! Map) {
        throw AppException('Unexpected response format from refund service');
      }
      final data = Map<String, dynamic>.from(rawData);

      if (data.containsKey('error')) {
        throw AppException(data['error'] as String);
      }

      return data; // { refundId, status, amount }
    } on AppException {
      rethrow;
    } on FunctionException catch (e) {
      // HTTP 非 2xx：从 details 中提取 Edge Function 返回的 error 字段
      final details = e.details;
      String message;
      if (details is Map && details.containsKey('error')) {
        message = details['error'].toString();
      } else {
        message = 'Refund request failed (${e.status})';
      }
      throw AppException(message);
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to request refund: ${e.message}',
        code: e.code,
      );
    } catch (e) {
      throw AppException('Refund failed: $e');
    }
  }

  /// 旧版：通过 orderId 请求退款（向后兼容，V3 建议改用 requestItemRefund）
  @Deprecated('V3 请使用 requestItemRefund(orderItemId, refundMethod)')
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
}
