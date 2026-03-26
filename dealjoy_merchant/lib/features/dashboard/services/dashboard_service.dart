// 商家工作台服务层
// 负责: 调用 merchant-dashboard Edge Function，处理 GET / PATCH 请求

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dashboard_stats.dart';
import '../../store/services/store_service.dart';

// ============================================================
// DashboardService — 封装所有工作台 API 调用
// ============================================================
class DashboardService {
  DashboardService(this._supabase);

  final SupabaseClient _supabase;

  // Edge Function 名称（Supabase 会自动解析路径）
  static const String _functionName = 'merchant-dashboard';

  // ----------------------------------------------------------
  // 1. 获取完整 Dashboard 数据
  //    调用: GET /merchant-dashboard
  //    返回: DashboardData（stats + weeklyTrend + todos）
  // ----------------------------------------------------------
  Future<DashboardData> fetchDashboardData() async {
    try {
      final response = await _supabase.functions.invoke(
        _functionName,
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      // 检查 HTTP 状态码
      if (response.status != 200) {
        final body = response.data;
        final message = body is Map ? (body['error'] ?? 'Unknown error') : 'Request failed';
        throw DashboardException('Fetch dashboard failed: $message (${response.status})');
      }

      // 解析响应体
      final Map<String, dynamic> json;
      if (response.data is String) {
        json = jsonDecode(response.data as String) as Map<String, dynamic>;
      } else if (response.data is Map<String, dynamic>) {
        json = response.data as Map<String, dynamic>;
      } else {
        throw DashboardException('Unexpected response format');
      }

      return DashboardData.fromJson(json);
    } on FunctionException catch (e) {
      throw DashboardException('Edge Function error: ${e.details}');
    } catch (e) {
      if (e is DashboardException) rethrow;
      throw DashboardException('Network error: $e');
    }
  }

  // ----------------------------------------------------------
  // 2. 切换门店在线状态
  //    调用: PATCH /merchant-dashboard  body: {is_online: bool}
  //    返回: 更新后的 isOnline 值
  // ----------------------------------------------------------
  Future<bool> updateOnlineStatus(bool isOnline) async {
    try {
      final response = await _supabase.functions.invoke(
        _functionName,
        method: HttpMethod.patch,
        body: {'is_online': isOnline},
        headers: StoreService.merchantIdHeaders,
      );

      if (response.status != 200) {
        final body = response.data;
        final message = body is Map ? (body['error'] ?? 'Unknown error') : 'Update failed';
        throw DashboardException('Update online status failed: $message (${response.status})');
      }

      // 解析返回的 isOnline 确认值
      final Map<String, dynamic> json;
      if (response.data is String) {
        json = jsonDecode(response.data as String) as Map<String, dynamic>;
      } else if (response.data is Map<String, dynamic>) {
        json = response.data as Map<String, dynamic>;
      } else {
        // 如果没有返回体，直接返回传入的值
        return isOnline;
      }

      return json['isOnline'] as bool? ?? isOnline;
    } on FunctionException catch (e) {
      throw DashboardException('Edge Function error: ${e.details}');
    } catch (e) {
      if (e is DashboardException) rethrow;
      throw DashboardException('Network error: $e');
    }
  }

  // ----------------------------------------------------------
  // V2.1 品牌总览 — 获取品牌级汇总数据
  // ----------------------------------------------------------
  Future<BrandOverviewData> fetchBrandOverview() async {
    try {
      final response = await _supabase.functions.invoke(
        '$_functionName/brand-overview',
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      if (response.status != 200) {
        final body = response.data;
        final message = body is Map ? (body['error'] ?? 'Unknown error') : 'Request failed';
        throw DashboardException('Fetch brand overview failed: $message (${response.status})');
      }

      final json = _parseJson(response.data);
      return BrandOverviewData.fromJson(json);
    } on FunctionException catch (e) {
      throw DashboardException('Edge Function error: ${e.details}');
    } catch (e) {
      if (e is DashboardException) rethrow;
      throw DashboardException('Network error: $e');
    }
  }

  // ----------------------------------------------------------
  // V2.1 门店排行
  // ----------------------------------------------------------
  Future<List<StoreRanking>> fetchBrandRankings({
    String sortBy = 'revenue',
    int days = 30,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        '$_functionName/brand-rankings?sort_by=$sortBy&days=$days',
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      if (response.status != 200) {
        final body = response.data;
        final message = body is Map ? (body['error'] ?? 'Unknown error') : 'Request failed';
        throw DashboardException('Fetch brand rankings failed: $message (${response.status})');
      }

      final json = _parseJson(response.data);
      final list = json['rankings'] as List<dynamic>? ?? [];
      return list
          .map((e) => StoreRanking.fromJson(e as Map<String, dynamic>))
          .toList();
    } on FunctionException catch (e) {
      throw DashboardException('Edge Function error: ${e.details}');
    } catch (e) {
      if (e is DashboardException) rethrow;
      throw DashboardException('Network error: $e');
    }
  }

  // ----------------------------------------------------------
  // V2.1 门店健康度
  // ----------------------------------------------------------
  Future<List<StoreHealthAlert>> fetchBrandHealth() async {
    try {
      final response = await _supabase.functions.invoke(
        '$_functionName/brand-health',
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      if (response.status != 200) {
        final body = response.data;
        final message = body is Map ? (body['error'] ?? 'Unknown error') : 'Request failed';
        throw DashboardException('Fetch brand health failed: $message (${response.status})');
      }

      final json = _parseJson(response.data);
      final list = json['alerts'] as List<dynamic>? ?? [];
      return list
          .map((e) => StoreHealthAlert.fromJson(e as Map<String, dynamic>))
          .toList();
    } on FunctionException catch (e) {
      throw DashboardException('Edge Function error: ${e.details}');
    } catch (e) {
      if (e is DashboardException) rethrow;
      throw DashboardException('Network error: $e');
    }
  }

  /// 统一 JSON 解析
  Map<String, dynamic> _parseJson(dynamic data) {
    if (data is String) {
      return jsonDecode(data) as Map<String, dynamic>;
    } else if (data is Map<String, dynamic>) {
      return data;
    }
    throw DashboardException('Unexpected response format');
  }
}

// ============================================================
// DashboardException — 工作台专用异常类型
// ============================================================
class DashboardException implements Exception {
  final String message;

  const DashboardException(this.message);

  @override
  String toString() => 'DashboardException: $message';
}
