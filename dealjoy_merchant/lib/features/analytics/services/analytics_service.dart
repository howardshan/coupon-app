// =============================================================
// 数据分析业务服务层
// 封装所有与 Edge Function merchant-analytics 的通信逻辑
// 对应路由:
//   GET /merchant-analytics/overview?days=7|30  — 经营概览
//   GET /merchant-analytics/deal-funnel         — Deal 转化漏斗
//   GET /merchant-analytics/customers           — 客群分析
// =============================================================

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/analytics_data.dart';
import '../../store/services/store_service.dart';

// =============================================================
// AnalyticsException — 数据分析模块自定义异常
// =============================================================
class AnalyticsException implements Exception {
  final String message;
  final String code;

  const AnalyticsException({required this.message, required this.code});

  @override
  String toString() => 'AnalyticsException($code): $message';
}

// =============================================================
// AnalyticsService — 数据分析 API 调用封装
// =============================================================
class AnalyticsService {
  AnalyticsService(this._supabase);

  final SupabaseClient _supabase;

  // Edge Function 名称
  static const String _functionName = 'merchant-analytics';

  // =============================================================
  // fetchOverview — 获取经营概览指标
  // [merchantId] — 商家 ID（仅用于构造参数，实际鉴权由 JWT 完成）
  // [daysRange]  — 时间范围（7 或 30），默认 7
  // 抛出 [AnalyticsException] 若请求失败
  // =============================================================
  Future<OverviewStats> fetchOverview(
    String merchantId, {
    int daysRange = 7,
  }) async {
    try {
      // 校验 daysRange 合法性
      final days = [7, 30].contains(daysRange) ? daysRange : 7;
      final path = '$_functionName/overview?days=$days';

      final response = await _supabase.functions.invoke(
        path,
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      final data = _parseResponse(response);
      _checkError(data);

      return OverviewStats.fromJson(data);
    } on AnalyticsException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw AnalyticsException(
        code:    body?['error'] as String? ?? 'network_error',
        message: body?['message'] as String? ?? 'Failed to fetch overview.',
      );
    } catch (e) {
      if (e is AnalyticsException) rethrow;
      throw const AnalyticsException(
        code:    'network_error',
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // fetchDealFunnel — 获取 Deal 转化漏斗数据
  // [merchantId] — 商家 ID
  // 返回按 Deal 创建时间倒序排列的漏斗列表
  // 抛出 [AnalyticsException] 若请求失败
  // =============================================================
  Future<List<DealFunnelData>> fetchDealFunnel(String merchantId) async {
    try {
      final path = '$_functionName/deal-funnel';

      final response = await _supabase.functions.invoke(
        path,
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      final data = _parseResponse(response);
      _checkError(data);

      // 解析列表
      final rawList = data['data'] as List<dynamic>? ?? [];
      return rawList
          .whereType<Map<String, dynamic>>()
          .map(DealFunnelData.fromJson)
          .toList();
    } on AnalyticsException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw AnalyticsException(
        code:    body?['error'] as String? ?? 'network_error',
        message: body?['message'] as String? ?? 'Failed to fetch deal funnel.',
      );
    } catch (e) {
      if (e is AnalyticsException) rethrow;
      throw const AnalyticsException(
        code:    'network_error',
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // fetchCustomerAnalysis — 获取客群新老分析数据
  // [merchantId] — 商家 ID
  // 抛出 [AnalyticsException] 若请求失败
  // =============================================================
  Future<CustomerAnalysis> fetchCustomerAnalysis(String merchantId) async {
    try {
      final path = '$_functionName/customers';

      final response = await _supabase.functions.invoke(
        path,
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      final data = _parseResponse(response);
      _checkError(data);

      return CustomerAnalysis.fromJson(data);
    } on AnalyticsException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw AnalyticsException(
        code:    body?['error'] as String? ?? 'network_error',
        message: body?['message'] as String? ?? 'Failed to fetch customer analysis.',
      );
    } catch (e) {
      if (e is AnalyticsException) rethrow;
      throw const AnalyticsException(
        code:    'network_error',
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // 私有工具方法
  // =============================================================

  /// 解析 FunctionResponse 为 `Map&lt;String, dynamic&gt;`
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

  /// 检查响应体中是否包含 error 字段，若有则抛出 AnalyticsException
  void _checkError(Map<String, dynamic> data) {
    if (data['error'] != null) {
      throw AnalyticsException(
        code:    data['error'] as String,
        message: data['message'] as String? ?? 'Request failed',
      );
    }
  }

  /// 尝试解析错误体为 Map，失败返回 null
  Map<String, dynamic>? _tryParseBody(dynamic details) {
    try {
      if (details is Map<String, dynamic>) return details;
      if (details is String) {
        return jsonDecode(details) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}
