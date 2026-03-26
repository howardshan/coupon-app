// 商家通知服务层
// 封装所有与 Edge Function merchant-notifications 的通信逻辑
// 包含：获取列表、标记已读、全部已读、注册 FCM Token、获取未读数

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../store/services/store_service.dart';
import '../models/merchant_notification.dart';

// =============================================================
// NotificationsException — 服务层统一异常
// =============================================================
class NotificationsException implements Exception {
  const NotificationsException({required this.message, required this.code});

  final String message;
  final String code;

  @override
  String toString() => 'NotificationsException($code): $message';
}

// =============================================================
// PagedResult — 分页结果包装
// =============================================================
class PagedResult<T> {
  const PagedResult({
    required this.data,
    required this.total,
    required this.page,
    required this.perPage,
    required this.hasMore,
  });

  final List<T> data;
  final int total;
  final int page;
  final int perPage;
  final bool hasMore;
}

// =============================================================
// NotificationsService — 核心服务类
// =============================================================
class NotificationsService {
  NotificationsService(this._supabase);

  final SupabaseClient _supabase;

  // Edge Function 名称
  static const String _functionName = 'merchant-notifications';

  // =============================================================
  // fetchNotifications — 分页获取通知列表
  // =============================================================
  /// 获取当前商家的通知列表
  /// [unreadOnly] 为 true 时只返回未读通知
  /// 抛出 [NotificationsException] 如果请求失败
  Future<PagedResult<MerchantNotification>> fetchNotifications({
    bool unreadOnly = false,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final params = <String, String>{
        'page':     page.toString(),
        'per_page': perPage.toString(),
      };
      if (unreadOnly) params['unread_only'] = 'true';

      final queryString = _buildQueryString(params);
      final path = queryString.isEmpty
          ? _functionName
          : '$_functionName?$queryString';

      final response = await _supabase.functions.invoke(
        path,
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      final data = _parseResponse(response);

      if (data['error'] != null) {
        throw NotificationsException(
          code:    data['error'] as String,
          message: data['message'] as String? ?? 'Failed to fetch notifications',
        );
      }

      final rawList = data['data'] as List<dynamic>? ?? [];
      final notifications = rawList
          .map((item) => MerchantNotification.fromJson(item as Map<String, dynamic>))
          .toList();

      return PagedResult(
        data:    notifications,
        total:   (data['total']    as num?)?.toInt() ?? 0,
        page:    (data['page']     as num?)?.toInt() ?? page,
        perPage: (data['per_page'] as num?)?.toInt() ?? perPage,
        hasMore: data['has_more']  as bool? ?? false,
      );
    } on NotificationsException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw NotificationsException(
        code:    body?['error'] as String? ?? 'network_error',
        message: body?['message'] as String? ?? 'Network error. Please try again.',
      );
    } catch (e) {
      if (e is NotificationsException) rethrow;
      throw const NotificationsException(
        code:    'network_error',
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // markAsRead — 标记单条通知为已读
  // =============================================================
  /// 将指定 ID 的通知标记为已读
  /// 抛出 [NotificationsException] 如果请求失败
  Future<void> markAsRead(String notificationId) async {
    try {
      final response = await _supabase.functions.invoke(
        '$_functionName/$notificationId/read',
        method: HttpMethod.patch,
        headers: StoreService.merchantIdHeaders,
      );

      final data = _parseResponse(response);

      if (data['error'] != null) {
        throw NotificationsException(
          code:    data['error'] as String,
          message: data['message'] as String? ?? 'Failed to mark notification as read',
        );
      }
    } on NotificationsException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw NotificationsException(
        code:    body?['error'] as String? ?? 'network_error',
        message: body?['message'] as String? ?? 'Network error.',
      );
    } catch (e) {
      if (e is NotificationsException) rethrow;
      throw const NotificationsException(
        code:    'network_error',
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // markAllAsRead — 全部标记已读
  // =============================================================
  /// 将当前商家所有未读通知标记为已读
  /// 抛出 [NotificationsException] 如果请求失败
  Future<void> markAllAsRead() async {
    try {
      final response = await _supabase.functions.invoke(
        '$_functionName/read-all',
        method: HttpMethod.patch,
        headers: StoreService.merchantIdHeaders,
      );

      final data = _parseResponse(response);

      if (data['error'] != null) {
        throw NotificationsException(
          code:    data['error'] as String,
          message: data['message'] as String? ?? 'Failed to mark all notifications as read',
        );
      }
    } on NotificationsException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw NotificationsException(
        code:    body?['error'] as String? ?? 'network_error',
        message: body?['message'] as String? ?? 'Network error.',
      );
    } catch (e) {
      if (e is NotificationsException) rethrow;
      throw const NotificationsException(
        code:    'network_error',
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // registerFcmToken — 注册/更新 FCM Token
  // =============================================================
  /// V1 阶段：接口已就绪，但不依赖 Firebase SDK
  /// [token] FCM 推送 Token 字符串
  /// [deviceType] 设备类型 'ios' 或 'android'
  Future<void> registerFcmToken(String token, String deviceType) async {
    try {
      final response = await _supabase.functions.invoke(
        '$_functionName/fcm-token',
        method: HttpMethod.post,
        headers: StoreService.merchantIdHeaders,
        body: {
          'fcm_token':   token,
          'device_type': deviceType,
        },
      );

      final data = _parseResponse(response);

      if (data['error'] != null) {
        throw NotificationsException(
          code:    data['error'] as String,
          message: data['message'] as String? ?? 'Failed to register FCM token',
        );
      }
    } on NotificationsException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw NotificationsException(
        code:    body?['error'] as String? ?? 'network_error',
        message: body?['message'] as String? ?? 'Network error.',
      );
    } catch (e) {
      if (e is NotificationsException) rethrow;
      throw const NotificationsException(
        code:    'network_error',
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // fetchUnreadCount — 获取未读通知数量
  // =============================================================
  /// 返回当前商家未读通知总数，用于底部导航 Badge
  Future<int> fetchUnreadCount() async {
    try {
      final response = await _supabase.functions.invoke(
        '$_functionName/unread-count',
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      final data = _parseResponse(response);

      if (data['error'] != null) {
        // 未读数查询失败不应影响 UI，静默返回 0
        return 0;
      }

      return (data['unread_count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      // 网络失败静默降级返回 0
      return 0;
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

  /// 构造 URL 查询字符串
  String _buildQueryString(Map<String, String> params) {
    if (params.isEmpty) return '';
    return params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }
}
