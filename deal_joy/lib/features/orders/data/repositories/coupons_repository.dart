// 团购券 Repository — 封装 Supabase coupons 表的所有查询与操作

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
import '../models/coupon_model.dart';

/// Supabase 查询中携带 deals 和 merchants 的 select 字符串
const _couponSelect =
    'id, order_id, user_id, deal_id, merchant_id, qr_code, status, '
    'expires_at, used_at, created_at, gifted_from, verified_by, '
    'deals(id, title, description, image_urls, refund_policy, '
    'merchants(name, logo_url, address, phone)), '
    'orders(order_number)';

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

  /// 仅提交退款申请（更新订单状态为 refund_requested），不调用 Stripe；审核由 Admin 通过后执行退款
  Future<void> requestRefund(String couponId, {String? reason}) async {
    final couponData = await _client
        .from('coupons')
        .select('order_id')
        .eq('id', couponId)
        .single();
    final orderId = couponData['order_id'] as String;
    await _updateOrderToRefundRequested(orderId, reason: reason);
  }

  /// 通过 orderId 仅提交退款申请（供退款页/订单列表使用）
  Future<void> requestRefundByOrderId(String orderId, {String? reason}) async {
    await _updateOrderToRefundRequested(orderId, reason: reason);
  }

  Future<void> _updateOrderToRefundRequested(String orderId,
      {String? reason}) async {
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
}
