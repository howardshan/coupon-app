// 团购券 Repository — 封装 Supabase coupons 表的所有查询与操作

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
import '../models/coupon_model.dart';

/// Supabase 查询中携带 deals、merchants、orders 的 select 字符串
/// orders 需指定 FK：coupons 与 orders 存在双向关系，用 orders!coupons_order_id_fkey 消除歧义
const _couponSelect =
    'id, order_id, user_id, deal_id, merchant_id, qr_code, status, '
    'expires_at, used_at, created_at, gifted_from, verified_by, '
    'void_reason, voided_at, '
    'deals(id, title, description, image_urls, refund_policy, '
    'merchants(name, logo_url, address, phone)), '
    'orders!coupons_order_id_fkey(applicable_store_ids)';

class CouponsRepository {
  final SupabaseClient _client;

  CouponsRepository(this._client);

  /// 获取当前用户的全部团购券，按创建时间倒序
  Future<List<CouponModel>> fetchUserCoupons(String userId) async {
    try {
      final data = await _client
          .from('coupons')
          .select(_couponSelect)
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return (data as List)
          .map((e) => CouponModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw AppException('Failed to load coupons: ${e.message}', code: e.code);
    }
  }

  /// 获取单张团购券详情
  Future<CouponModel> fetchCouponDetail(String couponId) async {
    try {
      final data = await _client
          .from('coupons')
          .select(_couponSelect)
          .eq('id', couponId)
          .single();
      return CouponModel.fromJson(data);
    } on PostgrestException catch (e) {
      throw AppException('Coupon not found: ${e.message}', code: e.code);
    }
  }

  /// 将团购券转赠给其他用户（通过邮箱查找收件人，然后调用 RPC）
  Future<String> giftCoupon(String couponId, String recipientEmail) async {
    try {
      // 先根据邮箱查询收件人 user id
      final userResult = await _client
          .from('users')
          .select('id')
          .eq('email', recipientEmail)
          .maybeSingle();

      if (userResult == null) {
        throw AppException('No user found with that email address.');
      }

      final recipientUserId = userResult['id'] as String;

      // 调用 Supabase RPC 完成转赠逻辑
      final result = await _client.rpc(
        'gift_coupon',
        params: {
          'p_coupon_id': couponId,
          'p_recipient_user_id': recipientUserId,
        },
      );

      return result as String;
    } on PostgrestException catch (e) {
      throw AppException('Failed to gift coupon: ${e.message}', code: e.code);
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Gift failed: $e');
    }
  }

  /// 请求退款：通过 create-refund Edge Function 调用 Stripe 退款
  /// [couponId] 券 ID，先查出 orderId 再调用 Edge Function
  /// [reason] 退款原因，可选，默认 'customer_request'
  Future<Map<String, dynamic>> requestRefund(
    String couponId, {
    String? reason,
  }) async {
    try {
      // 先获取对应 order_id
      final couponData = await _client
          .from('coupons')
          .select('id, order_id')
          .eq('id', couponId)
          .single();

      final orderId = couponData['order_id'] as String;

      // 调用 create-refund Edge Function（内部处理 Stripe 退款 + DB 状态更新）
      // SDK 在 HTTP 2xx 时返回 FunctionResponse，非 2xx 时抛出 FunctionException
      final response = await _client.functions.invoke(
        'create-refund',
        body: {
          'orderId': orderId,
          'reason': ?reason,
        },
      );

      // response.data 类型为 dynamic；Edge Function 返回 application/json，
      // SDK 会将其解码为 Map — 但需做类型安全检查
      final rawData = response.data;
      if (rawData is! Map) {
        throw AppException('Unexpected response format from refund service');
      }
      final data = Map<String, dynamic>.from(rawData);

      // Edge Function 返回 error 字段表示业务错误（此路径通常不触发，
      // 因为 Edge Function 对业务错误返回非 2xx，SDK 会抛 FunctionException）
      if (data.containsKey('error')) {
        throw AppException(data['error'] as String);
      }

      return data; // { refundId, status, amount }
    } on AppException {
      rethrow;
    } on FunctionException catch (e) {
      // HTTP 非 2xx 响应：从 details 中提取 Edge Function 返回的 error 字段
      final details = e.details;
      String message;
      if (details is Map && details.containsKey('error')) {
        message = details['error'].toString();
      } else {
        message = 'Refund request failed (${e.status})';
      }
      throw AppException(message);
    } on PostgrestException catch (e) {
      throw AppException('Failed to request refund: ${e.message}',
          code: e.code);
    } catch (e) {
      throw AppException('Refund failed: $e');
    }
  }

  /// 通过 orderId 请求退款（供 OrdersScreen 使用）
  Future<Map<String, dynamic>> requestRefundByOrderId(
    String orderId, {
    String? reason,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-refund',
        body: {
          'orderId': orderId,
          'reason': ?reason,
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

      return data;
    } on AppException {
      rethrow;
    } on FunctionException catch (e) {
      final details = e.details;
      String message;
      if (details is Map && details.containsKey('error')) {
        message = details['error'].toString();
      } else {
        message = 'Refund request failed (${e.status})';
      }
      throw AppException(message);
    } catch (e) {
      throw AppException('Refund failed: $e');
    }
  }
}
