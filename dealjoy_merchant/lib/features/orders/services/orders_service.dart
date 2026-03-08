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

  // =============================================================
  // fetchOrders — 分页获取订单列表
  // =============================================================
  /// 获取当前商家的订单列表，支持筛选和分页
  /// 抛出 [OrdersException] 如果请求失败
  Future<PagedResult<MerchantOrder>> fetchOrders({
    OrderFilter? filter,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      // 构造查询参数
      final params = <String, String>{
        'page': page.toString(),
        'per_page': perPage.toString(),
      };

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

      final queryString = _buildQueryString(params);
      final path = queryString.isEmpty
          ? _functionName
          : '$_functionName?$queryString';

      final response = await _supabase.functions.invoke(
        path,
        method: HttpMethod.get,
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
      // 使用 query 参数 ?id= 调用，避免 path 被平台截断导致 404
      final pathWithQuery = '$_functionName?id=${Uri.encodeComponent(orderId)}';
      final response = await _supabase.functions.invoke(
        pathWithQuery,
        method: HttpMethod.get,
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

      final queryString = _buildQueryString(params);
      final path = queryString.isEmpty
          ? '$_functionName/export'
          : '$_functionName/export?$queryString';

      final response = await _supabase.functions.invoke(
        path,
        method: HttpMethod.get,
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
