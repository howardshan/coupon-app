// NotificationRepository — 通知数据访问层
// 操作 notifications 表，支持分页获取、标记已读、未读计数

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
import '../models/notification_model.dart';

class NotificationRepository {
  final SupabaseClient _client;

  NotificationRepository(this._client);

  // ================================================================
  // 通知列表
  // ================================================================

  /// 获取当前用户的通知列表（按创建时间倒序，支持分页）
  /// [userId] 用户 ID（具名参数，与 provider 调用方式对齐）
  /// [page] 页码从 0 开始，[pageSize] 每页条数，默认 20
  Future<List<NotificationModel>> fetchNotifications({
    required String userId,
    int page = 0,
    int pageSize = 20,
  }) async {
    try {
      final from = page * pageSize;
      final to = from + pageSize - 1;

      final data = await _client
          .from('notifications')
          .select('id, type, title, body, data, is_read, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(from, to);

      return (data as List)
          .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to fetch notifications: ${e.message}',
        code: e.code,
      );
    }
  }

  // ================================================================
  // 未读数量
  // ================================================================

  /// 查询当前用户的未读通知数量
  Future<int> fetchUnreadCount(String userId) async {
    try {
      final data = await _client
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);

      return (data as List).length;
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to fetch notification unread count: ${e.message}',
        code: e.code,
      );
    }
  }

  // ================================================================
  // 标记已读
  // ================================================================

  /// 将指定通知标记为已读
  Future<void> markAsRead(String notificationId) async {
    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to mark notification as read: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 将当前用户所有未读通知一次性标记为已读
  Future<void> markAllAsRead(String userId) async {
    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to mark all notifications as read: ${e.message}',
        code: e.code,
      );
    }
  }
}
