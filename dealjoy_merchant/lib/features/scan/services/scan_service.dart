// 扫码核销业务服务层
// 封装所有与 Edge Function merchant-scan 的通信逻辑

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/coupon_info.dart';
import '../../store/services/store_service.dart';

/// 核销相关所有 API 调用的服务类
/// 通过 Supabase Edge Function 间接操作数据库，确保 RLS 安全策略正确执行
class ScanService {
  ScanService(this._supabase);

  final SupabaseClient _supabase;

  // Edge Function 名称
  static const String _functionName = 'merchant-scan';

  // =============================================================
  // verifyCoupon — 验证券码（只查询，不核销）
  // =============================================================
  /// 通过券码查询券信息，用于在确认页展示
  /// 抛出 [ScanException] 如果券无效或状态异常
  Future<CouponInfo> verifyCoupon(String code) async {
    try {
      final response = await _supabase.functions.invoke(
        '$_functionName/verify',
        method: HttpMethod.post,
        headers: StoreService.merchantIdHeaders,
        body: {'code': code},
      );

      final data = _parseResponse(response);

      // Edge Function 通过 HTTP status 400+ 表示错误
      if (data['error'] != null) {
        throw ScanException(
          error: ScanError.fromString(data['error'] as String),
          message: data['message'] as String? ?? 'Unknown error',
          detail: data['detail'] as String?,
        );
      }

      return CouponInfo.fromJson(data);
    } on ScanException {
      rethrow;
    } on FunctionException catch (e) {
      // Edge Function 返回非 2xx 状态码
      final body = _tryParseBody(e.details);
      throw ScanException(
        error: body != null
            ? ScanError.fromString(body['error'] as String? ?? 'unknown')
            : ScanError.network,
        message: body?['message'] as String? ?? e.reasonPhrase ?? 'Request failed',
        detail: body?['detail'] as String?,
      );
    } catch (e) {
      throw ScanException(
        error: ScanError.network,
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // redeemCoupon — 执行核销
  // =============================================================
  /// 对指定 couponId 执行核销操作
  /// 返回核销时间 [DateTime]
  /// 抛出 [ScanException] 如果核销失败
  Future<DateTime> redeemCoupon(String couponId) async {
    try {
      final response = await _supabase.functions.invoke(
        '$_functionName/redeem',
        method: HttpMethod.post,
        headers: StoreService.merchantIdHeaders,
        body: {'coupon_id': couponId},
      );

      final data = _parseResponse(response);

      if (data['error'] != null) {
        throw ScanException(
          error: ScanError.fromString(data['error'] as String),
          message: data['message'] as String? ?? 'Redemption failed',
          detail: data['detail'] as String?,
        );
      }

      return DateTime.parse(data['redeemed_at'] as String);
    } on ScanException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw ScanException(
        error: body != null
            ? ScanError.fromString(body['error'] as String? ?? 'unknown')
            : ScanError.network,
        message: body?['message'] as String? ?? 'Redemption failed',
        detail: body?['detail'] as String?,
      );
    } catch (e) {
      throw ScanException(
        error: ScanError.network,
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // revertRedemption — 撤销核销（10分钟内）
  // =============================================================
  /// 撤销指定 couponId 的核销操作
  /// 抛出 [ScanException] 如果超过10分钟或撤销失败
  Future<void> revertRedemption(String couponId) async {
    try {
      final response = await _supabase.functions.invoke(
        '$_functionName/revert',
        method: HttpMethod.post,
        headers: StoreService.merchantIdHeaders,
        body: {'coupon_id': couponId},
      );

      final data = _parseResponse(response);

      if (data['error'] != null) {
        throw ScanException(
          error: ScanError.fromString(data['error'] as String),
          message: data['message'] as String? ?? 'Revert failed',
          detail: data['detail'] as String?,
        );
      }
    } on ScanException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw ScanException(
        error: body != null
            ? ScanError.fromString(body['error'] as String? ?? 'unknown')
            : ScanError.network,
        message: body?['message'] as String? ?? 'Revert failed',
        detail: body?['detail'] as String?,
      );
    } catch (e) {
      throw ScanException(
        error: ScanError.network,
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // fetchRedemptionHistory — 分页获取核销历史
  // =============================================================
  /// 获取核销历史记录，支持日期范围和 Deal 筛选
  /// 返回包含 data/total/page/per_page/has_more 的 Map
  Future<Map<String, dynamic>> fetchRedemptionHistory({
    DateTime? from,
    DateTime? to,
    String? dealId,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      // 构造查询参数
      final params = <String, String>{
        'page': page.toString(),
        'per_page': perPage.toString(),
      };
      if (from != null) {
        params['date_from'] =
            '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
      }
      if (to != null) {
        params['date_to'] =
            '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';
      }
      if (dealId != null) {
        params['deal_id'] = dealId;
      }

      // 构造带查询参数的路径
      final queryString =
          params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

      final response = await _supabase.functions.invoke(
        '$_functionName/history?$queryString',
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      final data = _parseResponse(response);

      if (data['error'] != null) {
        throw ScanException(
          error: ScanError.serverError,
          message: data['message'] as String? ?? 'Failed to load history',
        );
      }

      // 转换 records 列表
      final rawList = data['data'] as List<dynamic>? ?? [];
      final records = rawList
          .map((item) => RedemptionRecord.fromJson(item as Map<String, dynamic>))
          .toList();

      return {
        'data': records,
        'total': data['total'] as int? ?? 0,
        'page': data['page'] as int? ?? page,
        'per_page': data['per_page'] as int? ?? perPage,
        'has_more': data['has_more'] as bool? ?? false,
      };
    } on ScanException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw ScanException(
        error: ScanError.network,
        message: body?['message'] as String? ?? 'Failed to load history',
      );
    } catch (e) {
      throw ScanException(
        error: ScanError.network,
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // 私有工具方法
  // =============================================================

  /// 解析 FunctionResponse 的 data 字段
  Map<String, dynamic> _parseResponse(FunctionResponse response) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        return jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {};
  }

  /// 尝试解析错误体，失败返回 null
  Map<String, dynamic>? _tryParseBody(dynamic details) {
    try {
      if (details is Map<String, dynamic>) return details;
      if (details is String) return jsonDecode(details) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }
}
