import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/notification_model.dart';
import '../../data/repositories/notification_repository.dart';

// ---- Repository Provider ----

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(supabaseClientProvider));
});

// ---- 每页通知数量 ----
const _kNotificationsPageSize = 20;

// ---- 通知列表 Notifier（支持分页 + 标记已读）----

/// 管理当前用户的通知列表，支持加载更多及标记已读
class NotificationsNotifier extends AsyncNotifier<List<NotificationModel>> {
  int _page = 0;
  bool _hasMore = true;

  /// 是否还有更多通知可加载
  bool get hasMore => _hasMore;

  @override
  Future<List<NotificationModel>> build() async {
    // 重置分页状态
    _page = 0;
    _hasMore = true;
    final user = await ref.watch(currentUserProvider.future);
    if (user == null) return [];
    return ref.read(notificationRepositoryProvider).fetchNotifications(
          userId: user.id,
          page: _page,
          pageSize: _kNotificationsPageSize,
        );
  }

  /// 加载更多通知（向下分页）
  Future<void> loadMore() async {
    if (!_hasMore) return;
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;

    final current = state.valueOrNull ?? [];
    final nextPage = _page + 1;
    final more = await ref
        .read(notificationRepositoryProvider)
        .fetchNotifications(
          userId: user.id,
          page: nextPage,
          pageSize: _kNotificationsPageSize,
        );
    if (more.length < _kNotificationsPageSize) {
      _hasMore = false;
    }
    _page = nextPage;
    state = AsyncValue.data([...current, ...more]);
  }

  /// 将指定通知标记为已读，同时更新本地列表状态
  Future<void> markAsRead(String notificationId) async {
    await ref
        .read(notificationRepositoryProvider)
        .markAsRead(notificationId);

    // 更新本地列表中对应条目的 isRead 状态
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.map((n) {
      if (n.id == notificationId) {
        // NotificationModel 没有 copyWith，手动重建
        return NotificationModel.fromJson({
          'id': n.id,
          'type': n.type,
          'title': n.title,
          'body': n.body,
          'data': n.data,
          'is_read': true,
          'created_at': n.createdAt.toIso8601String(),
        });
      }
      return n;
    }).toList());

    // 刷新未读计数
    ref.invalidate(unreadNotificationCountProvider);
  }

  /// 将所有未读通知标记为已读
  Future<void> markAllAsRead() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;

    await ref
        .read(notificationRepositoryProvider)
        .markAllAsRead(user.id);

    // 将本地所有条目更新为已读
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.map((n) {
      if (n.isRead) return n;
      return NotificationModel.fromJson({
        'id': n.id,
        'type': n.type,
        'title': n.title,
        'body': n.body,
        'data': n.data,
        'is_read': true,
        'created_at': n.createdAt.toIso8601String(),
      });
    }).toList());

    // 刷新未读计数
    ref.invalidate(unreadNotificationCountProvider);
  }
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsNotifier, List<NotificationModel>>(
        NotificationsNotifier.new);

// ---- 未读通知数（用于 badge 展示）----

/// 查询当前用户的未读通知数量
final unreadNotificationCountProvider = FutureProvider<int>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return 0;
  return ref
      .watch(notificationRepositoryProvider)
      .fetchUnreadCount(user.id);
});
