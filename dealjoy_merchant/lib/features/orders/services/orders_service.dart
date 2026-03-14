// 订单管理业务服务层
// 封装所有与 Edge Function merchant-orders 的通信逻辑

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/merchant_order.dart';

/// 订单服务异常
class OrdersException implements Exception {
  final String message;
  final String code;

  const OrdersException({required this.message, required this.code});

  @override
  String toString() => 'OrdersException($code): $message';
}

/// 分页结果包装类
class PagedResult<T> {
  final List<T> data;
  final int total;
  final int page;
  final int perPage;
  final bool hasMore;

  const PagedResult({
    required this.data,
    required this.total,
    required this.page,
    required this.perPage,
    required this.hasMore,
  });
}

/// 订单管理所有 API 调用的服务类
/// 通过 Supabase Edge Function merchant-orders 交互
class OrdersService {
  OrdersService(this._supabase);

  final SupabaseClient _supabase;

  // Edge Function 名称
  static const String _functionName = 'merchant-orders';

  /// 确保 session 有效（functions.invoke 不会自动刷新 token）
  Future<void> _ensureFreshSession() async {
    final session = _supabase.auth.currentSession;
    if (session == null) return;
    try {
      await _supabase.auth.refreshSession();
    } catch (_) {
      // refresh 失败则继续使用现有 token
    }
  }

  /// 请求头：用自定义头传 JWT（网关可能不转发 Authorization 到 Edge Function）
  Map<String, String> get _authHeaders {
    final session = _supabase.auth.currentSession;
    if (session?.accessToken != null) {
      return {
        'Authorization': 'Bearer ${session!.accessToken}',
        'x-app-bearer': session.accessToken!,
      };
    }
    return {};
  }

  /// 当前 session 的 access token（供 URL query 传参，解决网关不转发 header 导致 401）
  String? get _accessToken => _supabase.auth.currentSession?.accessToken;

  // =============================================================
  // fetchOrders — 分页获取订单列表（POST + body 传 token，避免网关脱敏 query/header）
  // =============================================================
  /// 获取当前商家的订单列表，支持筛选和分页
  /// 抛出 [OrdersException] 如果请求失败
  Future<PagedResult<MerchantOrder>> fetchOrders({
    OrderFilter? filter,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      await _ensureFreshSession();

      final token = _accessToken;
      if (token == null || token.isEmpty) {
        throw const OrdersException(
          code: 'unauthorized',
          message: 'Not signed in. Please sign in and retry.',
        );
      }

      // POST body：access_token + 分页/筛选参数
      final body = <String, dynamic>{
        'access_token': token,
        'page': page,
        'per_page': perPage,
      };
      if (filter != null) {
        final statusParam = filter.statusParam;
        if (statusParam != null) body['status'] = statusParam;
        if (filter.dateFrom != null) body['date_from'] = _formatDate(filter.dateFrom!);
        if (filter.dateTo != null) body['date_to'] = _formatDate(filter.dateTo!);
        if (filter.dealId != null) body['deal_id'] = filter.dealId!;
      }

      // 不显式设置 Content-Type，避免 SDK 在 header+body 同时存在时发空 body（类似 supabase-js #31098）
      final response = await _supabase.functions.invoke(
        _functionName,
        method: HttpMethod.post,
        headers: _authHeaders,
        body: body,
      );

      final data = _parseResponse(response);

      if (data['error'] != null) {
        throw OrdersException(
          code: data['error'] as String,
          message: data['message'] as String? ?? 'Failed to fetch orders',
        );
      }

      final rawList = data['data'] as List<dynamic>? ?? [];
      final orders = rawList
          .map((item) =>
              MerchantOrder.fromJson(item as Map<String, dynamic>))
          .toList();

      return PagedResult(
        data: orders,
        total: (data['total'] as num?)?.toInt() ?? 0,
        page: (data['page'] as num?)?.toInt() ?? page,
        perPage: (data['per_page'] as num?)?.toInt() ?? perPage,
        hasMore: data['has_more'] as bool? ?? false,
      );
    } on OrdersException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw OrdersException(
        code: body?['error'] as String? ?? 'network_error',
        message: body?['message'] as String? ?? 'Network error. Please try again.',
      );
    } catch (e) {
      throw const OrdersException(
        code: 'network_error',
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // fetchOrderDetail — 获取单个订单详情
  // =============================================================
  /// 获取指定订单的完整详情（含时间线）
  /// 抛出 [OrdersException] 如果请求失败或订单不存在
  Future<MerchantOrderDetail> fetchOrderDetail(String orderId) async {
    try {
      await _ensureFreshSession();
      // 使用 query 参数 ?id= 调用，避免 path 被平台截断导致 404；access_token 解决网关不转发 header 导致 401
      final token = _accessToken;
      final pathWithQuery = token != null && token.isNotEmpty
          ? '$_functionName?id=${Uri.encodeComponent(orderId)}&access_token=${Uri.encodeComponent(token)}'
          : '$_functionName?id=${Uri.encodeComponent(orderId)}';
      final response = await _supabase.functions.invoke(
        pathWithQuery,
        method: HttpMethod.get,
        headers: _authHeaders,
      );

      final data = _parseResponse(response);

      if (data['error'] != null) {
        throw OrdersException(
          code: data['error'] as String,
          message: data['message'] as String? ?? 'Failed to fetch order detail',
        );
      }

      return MerchantOrderDetail.fromJson(data);
    } on OrdersException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      final code = body?['error'] as String? ?? 'network_error';
      if (code == 'not_found') {
        throw const OrdersException(
          code: 'not_found',
          message: 'Order not found.',
        );
      }
      throw OrdersException(
        code: code,
        message: body?['message'] as String? ?? 'Failed to fetch order detail.',
      );
    } catch (e) {
      if (e is OrdersException) rethrow;
      throw const OrdersException(
        code: 'network_error',
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // exportOrdersCsv — 导出 CSV
  // =============================================================
  /// 导出当前筛选条件下的订单为 CSV 字符串
  /// 返回 CSV 文本内容
  /// 抛出 [OrdersException] 如果导出失败
  Future<String> exportOrdersCsv({OrderFilter? filter}) async {
    try {
      final params = <String, String>{};

      if (filter != null) {
        final statusParam = filter.statusParam;
        if (statusParam != null) params['status'] = statusParam;
        if (filter.dateFrom != null) {
          params['date_from'] = _formatDate(filter.dateFrom!);
        }
        if (filter.dateTo != null) {
          params['date_to'] = _formatDate(filter.dateTo!);
        }
        if (filter.dealId != null) params['deal_id'] = filter.dealId!;
      }

      await _ensureFreshSession();
      final token = _accessToken;
      if (token != null && token.isNotEmpty) params['access_token'] = token;

      final queryString = _buildQueryString(params);
      final path = queryString.isEmpty
          ? '$_functionName/export'
          : '$_functionName/export?$queryString';

      final response = await _supabase.functions.invoke(
        path,
        method: HttpMethod.get,
        headers: _authHeaders,
      );

      // CSV 响应直接是文本
      final rawData = response.data;
      if (rawData is String) {
        return rawData;
      }

      // 尝试解析为错误 JSON
      final parsed = _tryParseResponse(response);
      if (parsed != null && parsed['error'] != null) {
        throw OrdersException(
          code: parsed['error'] as String,
          message: parsed['message'] as String? ?? 'Export failed',
        );
      }

      throw const OrdersException(
        code: 'export_failed',
        message: 'Failed to generate CSV. Please try again.',
      );
    } on OrdersException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw OrdersException(
        code: body?['error'] as String? ?? 'export_failed',
        message: body?['message'] as String? ?? 'Export failed.',
      );
    } catch (e) {
      if (e is OrdersException) rethrow;
      throw const OrdersException(
        code: 'network_error',
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // fetchMerchantDeals — 获取商家所有 deals（供筛选下拉使用）
  // =============================================================
  /// 直接查询 deals 表，返回 {id, title} 列表
  Future<List<Map<String, String>>> fetchMerchantDeals(
      String merchantId) async {
    try {
      final response = await _supabase
          .from('deals')
          .select('id, title')
          .eq('merchant_id', merchantId)
          .order('created_at', ascending: false)
          .limit(100);

      return (response as List<dynamic>).map((item) {
        final map = item as Map<String, dynamic>;
        return {
          'id': map['id'] as String,
          'title': map['title'] as String,
        };
      }).toList();
    } catch (e) {
      throw OrdersException(
        code: 'fetch_deals_failed',
        message: 'Failed to load deals list: $e',
      );
    }
  }

  // =============================================================
  // 私有工具方法
  // =============================================================

  /// 解析 FunctionResponse 为 Map
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

  /// 尝试解析响应，失败返回 null（用于可选解析）
  Map<String, dynamic>? _tryParseResponse(FunctionResponse response) {
    try {
      return _parseResponse(response);
    } catch (_) {
      return null;
    }
  }

  /// 尝试解析错误体，失败返回 null
  Map<String, dynamic>? _tryParseBody(dynamic details) {
    try {
      if (details is Map<String, dynamic>) return details;
      if (details is String) {
        return jsonDecode(details) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// 格式化日期为 YYYY-MM-DD（用于 API 参数）
  String _formatDate(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// 构造 URL 查询字符串
  String _buildQueryString(Map<String, String> params) {
    if (params.isEmpty) return '';
    return params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }
}
