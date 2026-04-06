// 团购券 Repository — 封装 Supabase coupons 表的所有查询与操作

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/errors/postgrest_auth_mapper.dart';
import '../models/coupon_model.dart';
import '../models/coupon_gift_model.dart';

/// V3 coupon select — 通过 order_items join 获取 applicable_store_ids
/// order_items 关联使用外键 coupons!order_items_coupon_id_fkey
const _couponSelect =
    'id, order_id, user_id, deal_id, merchant_id, qr_code, status, '
    'expires_at, used_at, created_at, gifted_from, verified_by, '
    'void_reason, voided_at, '
    'gifted_from_user_id, current_holder_user_id, '
    'order_item_id, coupon_code, '
    'deals(id, title, description, image_urls, refund_policy, usage_rules, usage_notes, '
    'merchants(name, logo_url, address, phone)), '
    'gifter_user:users!coupons_gifted_from_user_id_fkey(full_name), '
    'orders!coupons_order_id_fkey(order_number), '
    'order_items!order_items_coupon_id_fkey('
    'applicable_store_ids, unit_price, refunded_at, refund_amount, refund_method, customer_status)';

class CouponsRepository {
  final SupabaseClient _client;

  CouponsRepository(this._client);

  /// 获取当前用户的全部团购券，按创建时间倒序
  Future<List<CouponModel>> fetchUserCoupons(String userId) async {
    try {
      // 查询条件：user_id 或 current_holder_user_id 匹配（好友赠送的券通过后者查到）
      final data = await _client
          .from('coupons')
          .select(_couponSelect)
          .or('user_id.eq.$userId,current_holder_user_id.eq.$userId')
          .order('created_at', ascending: false);
      final list = (data as List)
          .map((e) => CouponModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return _batchEnrichDealUsageRules(list);
    } on PostgrestException catch (e) {
      throwForCouponListPostgrest(e);
    }
  }

  /// 当 embed deals 未带回 usage_rules 时（受赠人场景较常见），按 deal_id 批量补全
  Future<List<CouponModel>> _batchEnrichDealUsageRules(
      List<CouponModel> list) async {
    final needIds = list
        .where((c) =>
            c.dealId.isNotEmpty &&
            c.usageRules.isEmpty &&
            (c.usageNotes == null || c.usageNotes!.trim().isEmpty))
        .map((c) => c.dealId)
        .toSet()
        .toList();
    if (needIds.isEmpty) return list;
    try {
      final rows = await _client
          .from('deals')
          .select('id, usage_rules, refund_policy, usage_notes')
          .inFilter('id', needIds);
      final byDealId = <String, Map<String, dynamic>>{};
      for (final r in rows as List) {
        final m = r as Map<String, dynamic>;
        final id = m['id'] as String?;
        if (id != null) byDealId[id] = m;
      }
      return list.map((c) {
        if (c.usageRules.isNotEmpty ||
            (c.usageNotes != null && c.usageNotes!.trim().isNotEmpty)) {
          return c;
        }
        final row = byDealId[c.dealId];
        if (row == null) return c;
        final rules = CouponModel.parseUsageRulesDynamic(row['usage_rules']);
        final notes = row['usage_notes'] as String?;
        final rp = row['refund_policy'] as String?;
        if (rules.isEmpty &&
            (notes == null || notes.trim().isEmpty) &&
            rp == null) {
          return c;
        }
        return c.copyWith(
          usageRules: rules.isNotEmpty ? rules : c.usageRules,
          usageNotes: c.usageNotes ?? notes,
          refundPolicy: c.refundPolicy ?? rp,
        );
      }).toList();
    } catch (_) {
      return list;
    }
  }

  /// 按 order_item_id 查询券 ID（聊天「View」跳转等；失败返回 null 不阻断主流程）
  Future<String?> fetchCouponIdByOrderItemId(String orderItemId) async {
    try {
      final data = await _client
          .from('coupons')
          .select('id')
          .eq('order_item_id', orderItemId)
          .maybeSingle();
      return data?['id'] as String?;
    } catch (_) {
      return null;
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
      final model = CouponModel.fromJson(data);
      final enriched = await _batchEnrichDealUsageRules([model]);
      return enriched.first;
    } on PostgrestException catch (e) {
      throwForCouponDetailPostgrest(e);
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

  /// V3：通过 couponId 请求退款 — 先查 order_item_id，再调 create-refund Edge Function
  /// [refundMethod] 退款方式：'store_credit' | 'original_payment'
  /// [reason] 退款原因，可选，默认 'customer_request'
  Future<Map<String, dynamic>> requestRefund(
    String couponId, {
    String? reason,
    String refundMethod = 'original_payment',
  }) async {
    try {
      // 先查 order_item_id（V3 via order_item_id 退款，需要此字段）
      final couponData = await _client
          .from('coupons')
          .select('id, order_item_id, order_id')
          .eq('id', couponId)
          .single();

      final orderItemId = couponData['order_item_id'] as String?;

      // V3：优先用 orderItemId 调用退款
      if (orderItemId != null && orderItemId.isNotEmpty) {
        return await _invokeRefundByItemId(
          orderItemId,
          refundMethod: refundMethod,
          reason: reason,
        );
      }

      // 向后兼容旧订单：使用 orderId 退款
      final orderId = couponData['order_id'] as String;
      return await _invokeRefundByOrderId(orderId, reason: reason);
    } on AppException {
      rethrow;
    } on FunctionException catch (e) {
      throw AppException(_extractFunctionError(e));
    } on PostgrestException catch (e) {
      throw AppException('Failed to request refund: ${e.message}',
          code: e.code);
    } catch (e) {
      throw AppException('Refund failed: $e');
    }
  }

  /// V3：通过 orderItemId 直接请求退款（供 OrdersRepository/Provider 使用）
  Future<Map<String, dynamic>> requestRefundByItemId(
    String orderItemId, {
    String refundMethod = 'original_payment',
    String? reason,
  }) async {
    try {
      return await _invokeRefundByItemId(
        orderItemId,
        refundMethod: refundMethod,
        reason: reason,
      );
    } on AppException {
      rethrow;
    } on FunctionException catch (e) {
      throw AppException(_extractFunctionError(e));
    } catch (e) {
      throw AppException('Refund failed: $e');
    }
  }

  /// 通过 orderId 请求退款（旧版向后兼容，供 OrdersScreen 使用）
  Future<Map<String, dynamic>> requestRefundByOrderId(
    String orderId, {
    String? reason,
  }) async {
    try {
      return await _invokeRefundByOrderId(orderId, reason: reason);
    } on AppException {
      rethrow;
    } on FunctionException catch (e) {
      throw AppException(_extractFunctionError(e));
    } catch (e) {
      throw AppException('Refund failed: $e');
    }
  }

  /// 发起赠送 — 调用 send-gift Edge Function
  /// 返回 { gift_id, claim_token }
  Future<Map<String, dynamic>> sendGift({
    required String orderItemId,
    String? recipientEmail,
    String? recipientPhone,
    String? recipientUserId,
    String? giftMessage,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'send-gift',
        body: {
          'order_item_id': orderItemId,
          if (recipientEmail != null) 'recipient_email': recipientEmail,
          if (recipientPhone != null) 'recipient_phone': recipientPhone,
          if (recipientUserId != null) 'recipient_user_id': recipientUserId,
          if (giftMessage != null && giftMessage.isNotEmpty)
            'gift_message': giftMessage,
        },
      );
      final data = response.data;
      if (data is Map && data.containsKey('error')) {
        throw AppException(data['error'] as String);
      }
      return Map<String, dynamic>.from(data as Map);
    } on FunctionException catch (e) {
      throw AppException(_extractFunctionError(e));
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Failed to send gift: $e');
    }
  }

  /// 撤回赠送 — 调用 recall-gift Edge Function
  Future<void> recallGift(String giftId) async {
    try {
      final response = await _client.functions.invoke(
        'recall-gift',
        body: {'gift_id': giftId},
      );
      final data = response.data;
      if (data is Map && data.containsKey('error')) {
        throw AppException(data['error'] as String);
      }
    } on FunctionException catch (e) {
      // HTTP 非 2xx：从 details 中提取 Edge Function 返回的 JSON 字段
      throw AppException(_extractRecallFunctionError(e));
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Failed to recall gift: $e');
    }
  }

  /// 解析 recall-gift / create-refund 等 Edge Function 的业务错误文案
  String _extractRecallFunctionError(FunctionException e) {
    final details = e.details;
    if (details is Map) {
      if (details['error'] != null) return details['error'].toString();
      if (details['message'] != null) return details['message'].toString();
    }
    return 'Recall failed (${e.status})';
  }

  /// 查询某个 order_item 的当前有效 gift（pending 或 claimed）
  Future<CouponGiftModel?> fetchActiveGift(String orderItemId) async {
    try {
      final data = await _client
          .from('coupon_gifts')
          .select()
          .eq('order_item_id', orderItemId)
          .inFilter('status', ['pending', 'claimed'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data == null) return null;
      return CouponGiftModel.fromJson(data);
    } on PostgrestException catch (e) {
      if (isPostgrestSessionExpiredLike(e)) {
        throw AppAuthException(
          'Your session has expired. Please sign in again.',
          code: e.code ?? 'session_expired',
        );
      }
      throw AppException('Failed to fetch gift info: ${e.message}',
          code: e.code);
    }
  }

  // =============================================================
  // 私有辅助方法
  // =============================================================

  /// 调用 create-refund Edge Function（V3 item 维度）
  Future<Map<String, dynamic>> _invokeRefundByItemId(
    String orderItemId, {
    required String refundMethod,
    String? reason,
  }) async {
    final response = await _client.functions.invoke(
      'create-refund',
      body: {
        'orderItemId': orderItemId,
        'refundMethod': refundMethod,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
    return _parseRefundResponse(response);
  }

  /// 调用 create-refund Edge Function（旧版 order 维度）
  Future<Map<String, dynamic>> _invokeRefundByOrderId(
    String orderId, {
    String? reason,
  }) async {
    final response = await _client.functions.invoke(
      'create-refund',
      body: {
        'orderId': orderId,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
    return _parseRefundResponse(response);
  }

  /// 解析 create-refund 响应，统一错误处理
  Map<String, dynamic> _parseRefundResponse(dynamic response) {
    final rawData = response.data;
    if (rawData is! Map) {
      throw AppException('Unexpected response format from refund service');
    }
    final data = Map<String, dynamic>.from(rawData);
    if (data.containsKey('error')) {
      throw AppException(data['error'] as String);
    }
    return data; // { refundId, status, amount }
  }

  /// 从 FunctionException 中提取可读的错误信息
  String _extractFunctionError(FunctionException e) {
    final details = e.details;
    if (details is Map && details.containsKey('error')) {
      return details['error'].toString();
    }
    return 'Refund request failed (${e.status})';
  }
}
