// 商家通知 Riverpod Providers
// NotificationsNotifier: 通知列表（分页 + Realtime 实时订阅）
// unreadOnlyFilterProvider: All/Unread Tab 筛选状态
// unreadCountProvider: 未读数量（用于底部导航 Badge）
// soundAlertEnabledProvider: 声音/震动提醒开关（SharedPreferences 持久化）

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/merchant_notification.dart';
import '../services/notifications_service.dart';

// =============================================================
// notificationsServiceProvider — 单例服务 Provider
// =============================================================
final notificationsServiceProvider = Provider<NotificationsService>((ref) {
  return NotificationsService(Supabase.instance.client);
});

// =============================================================
// unreadOnlyFilterProvider — All/Unread Tab 筛选状态
// true = 只显示未读，false = 显示全部
// =============================================================
final unreadOnlyFilterProvider = StateProvider<bool>((ref) => false);

// =============================================================
// unreadCountProvider — 未读数量（用于底部导航 Badge）
// =============================================================
final unreadCountProvider = FutureProvider<int>((ref) async {
  // 监听通知列表变化，列表更新时自动刷新未读数
  ref.watch(notificationsNotifierProvider);
  final service = ref.read(notificationsServiceProvider);
  return service.fetchUnreadCount();
});

// =============================================================
// soundAlertEnabledProvider — 声音提醒开关
// P2 功能：从 SharedPreferences 读取/写入开关状态
// =============================================================
final soundAlertEnabledProvider =
    AsyncNotifierProvider<SoundAlertNotifier, bool>(SoundAlertNotifier.new);

class SoundAlertNotifier extends AsyncNotifier<bool> {
  static const _prefKey = 'notification_sound_alert_enabled';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    // 默认开启声音提醒
    return prefs.getBool(_prefKey) ?? true;
  }

  /// 切换开关状态并持久化
  Future<void> toggle() async {
    final current = state.value ?? true;
    final next = !current;
    state = AsyncData(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, next);
  }

  /// 设置指定值
  Future<void> setValue(bool value) async {
    state = AsyncData(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }
}

// =============================================================
// NotificationsNotifier — 通知列表（分页 + Realtime）
// 支持：下拉刷新、加载更多、标记已读、全部已读、Realtime 实时追加
// =============================================================
final notificationsNotifierProvider =
    AsyncNotifierProvider<NotificationsNotifier, List<MerchantNotification>>(
        NotificationsNotifier.new);

class NotificationsNotifier extends AsyncNotifier<List<MerchantNotification>> {
  // 分页状态
  int _currentPage = 1;
  bool _hasMore = false;
  int _total = 0;
  bool _isLoadingMore = false;

  // Supabase Realtime 订阅句柄（用于 dispose 时取消）
  RealtimeChannel? _channel;

  bool get hasMore => _hasMore;
  int get total => _total;
  bool get isLoadingMore => _isLoadingMore;

  @override
  Future<List<MerchantNotification>> build() async {
    // 监听筛选条件变化，切换 Tab 时自动重置到第一页
    ref.watch(unreadOnlyFilterProvider);

    // 加载第一页
    final result = await _fetchPage(1, replace: true);

    // 订阅 Realtime（加载完成后异步启动）
    _subscribeRealtime();

    // dispose 时取消订阅（避免内存泄漏）
    ref.onDispose(() {
      _unsubscribeRealtime();
    });

    return result;
  }

  // =============================================================
  // _fetchPage — 内部分页获取方法
  // =============================================================
  Future<List<MerchantNotification>> _fetchPage(
    int page, {
    required bool replace,
  }) async {
    final unreadOnly = ref.read(unreadOnlyFilterProvider);
    final service = ref.read(notificationsServiceProvider);

    final result = await service.fetchNotifications(
      unreadOnly: unreadOnly,
      page:       page,
      perPage:    20,
    );

    _currentPage = result.page;
    _hasMore     = result.hasMore;
    _total       = result.total;

    if (replace) {
      return result.data;
    } else {
      return [...(state.value ?? []), ...result.data];
    }
  }

  // =============================================================
  // refresh — 下拉刷新（重置到第一页）
  // =============================================================
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchPage(1, replace: true));
    // 刷新后也刷新未读数
    ref.invalidate(unreadCountProvider);
  }

  // =============================================================
  // loadMore — 上拉加载更多
  // =============================================================
  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    _isLoadingMore = true;
    try {
      final nextPage = _currentPage + 1;
      final updated  = await _fetchPage(nextPage, replace: false);
      state = AsyncData(updated);
    } catch (_) {
      // 加载更多失败保留现有列表，不清空
    } finally {
      _isLoadingMore = false;
    }
  }

  // =============================================================
  // markRead — 标记单条通知已读（乐观更新）
  // =============================================================
  Future<void> markRead(String notificationId) async {
    // 乐观更新：立即更新本地状态，避免等待网络
    final current = state.value ?? [];
    final updated = current
        .map((n) => n.id == notificationId ? n.copyWith(isRead: true) : n)
        .toList();
    state = AsyncData(updated);

    // 后台请求标记已读
    try {
      final service = ref.read(notificationsServiceProvider);
      await service.markAsRead(notificationId);
    } catch (_) {
      // 如果请求失败，恢复原状态
      state = AsyncData(current);
    }

    // 更新未读数 Badge
    ref.invalidate(unreadCountProvider);
  }

  // =============================================================
  // markAllRead — 全部标记已读（乐观更新）
  // =============================================================
  Future<void> markAllRead() async {
    // 乐观更新：全部标记为已读
    final current = state.value ?? [];
    final updated = current.map((n) => n.copyWith(isRead: true)).toList();
    state = AsyncData(updated);

    try {
      final service = ref.read(notificationsServiceProvider);
      await service.markAllAsRead();
    } catch (_) {
      // 失败则恢复原状态
      state = AsyncData(current);
    }

    ref.invalidate(unreadCountProvider);
  }

  // =============================================================
  // _subscribeRealtime — 订阅 Supabase Realtime 新通知
  // =============================================================
  void _subscribeRealtime() {
    final supabase  = Supabase.instance.client;
    final user      = supabase.auth.currentUser;
    if (user == null) return;

    // 先取消已有订阅（防重复）
    _unsubscribeRealtime();

    _channel = supabase
        .channel('merchant_notifications_${user.id}')
        .onPostgresChanges(
          event:  PostgresChangeEvent.insert,
          schema: 'public',
          table:  'merchant_notifications',
          callback: (payload) {
            _onNewNotification(payload.newRecord);
          },
        )
        .subscribe();
  }

  // =============================================================
  // _onNewNotification — Realtime 收到新通知时的回调
  // =============================================================
  void _onNewNotification(Map<String, dynamic> record) {
    try {
      final notification = MerchantNotification.fromJson(record);
      final current = state.value ?? [];

      // 避免重复追加（Realtime 可能触发多次）
      if (current.any((n) => n.id == notification.id)) return;

      // 新通知插入列表顶部
      state = AsyncData([notification, ...current]);

      // 刷新未读数
      ref.invalidate(unreadCountProvider);

      // P2 声音提醒：Realtime 收到新订单时触发 HapticFeedback
      if (notification.type == NotificationType.newOrder) {
        _triggerHapticIfEnabled();
      }
    } catch (_) {
      // 解析失败静默忽略，不影响 UI
    }
  }

  // =============================================================
  // _triggerHapticIfEnabled — 声音/震动提醒（P2）
  // =============================================================
  void _triggerHapticIfEnabled() {
    // 读取声音提醒开关状态（同步读取当前值）
    final soundEnabled = ref.read(soundAlertEnabledProvider).value ?? true;
    if (!soundEnabled) return;

    // 触发系统重震动（HeavyImpact 模拟订单提醒效果）
    HapticFeedback.heavyImpact();
  }

  // =============================================================
  // _unsubscribeRealtime — 取消 Realtime 订阅
  // 在 dispose 时调用，防止内存泄漏
  // =============================================================
  void _unsubscribeRealtime() {
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
      _channel = null;
    }
  }
}
