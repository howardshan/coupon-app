// Supabase Realtime 服务：监听订单和券状态变化，自动刷新相关 providers
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../features/chat/domain/providers/notification_provider.dart';
import '../../../features/orders/domain/providers/orders_provider.dart';
import '../../../features/orders/domain/providers/coupons_provider.dart';

/// 监听 order_items / coupons 表的 UPDATE 事件，自动 invalidate 相关 providers
class RealtimeService {
  final Ref _ref;
  RealtimeChannel? _channel;

  RealtimeService(this._ref);

  /// 核销/退款等会更新 DB，券详情页使用 [couponDetailProvider]；仅 invalidate 列表会导致详情仍显示旧 QR
  void _invalidateCouponDetailIfPresent(dynamic row, {required String idKey}) {
    if (row is! Map) return;
    final map = Map<String, dynamic>.from(row);
    final raw = map[idKey];
    final id = raw?.toString().trim();
    if (id == null || id.isEmpty) return;
    _ref.invalidate(couponDetailProvider(id));
  }

  /// 开始监听（用户登录成功后调用）
  void startListening(String userId) {
    // 先取消已有订阅，避免重复
    _channel?.unsubscribe();

    _channel = Supabase.instance.client
        .channel('user_realtime_$userId') // 用 userId 区分 channel，避免多用户冲突
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'order_items',
          callback: (payload) {
            // order_items 状态变化（如核销）→ 同时刷新订单列表和券列表
            debugPrint('[Realtime] order_items updated: ${payload.newRecord}');
            _ref.invalidate(userOrdersProvider);
            _ref.invalidate(userCouponsProvider);
            _invalidateCouponDetailIfPresent(
              payload.newRecord,
              idKey: 'coupon_id',
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'coupons',
          callback: (payload) {
            // coupons 状态变化（如退款、核销）→ 刷新券列表与当前券详情
            debugPrint('[Realtime] coupons updated: ${payload.newRecord}');
            _ref.invalidate(userCouponsProvider);
            _invalidateCouponDetailIfPresent(
              payload.newRecord,
              idKey: 'id',
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            // 新通知到达 → 刷新未读计数和通知列表
            debugPrint('[Realtime] new notification: ${payload.newRecord}');
            _ref.invalidate(unreadNotificationCountProvider);
            _ref.invalidate(notificationsProvider);
          },
        )
        .subscribe((status, [error]) {
          // 连接失败只打印日志，不影响 app 正常使用（graceful degradation）
          if (error != null) {
            debugPrint('[Realtime] subscribe error: $error');
          } else {
            debugPrint('[Realtime] channel status: $status');
          }
        });
  }

  /// 停止监听（用户登出时调用）
  void stopListening() {
    _channel?.unsubscribe();
    _channel = null;
    debugPrint('[Realtime] stopped listening');
  }
}

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  // ref.onDispose 确保 provider 销毁时自动 unsubscribe
  final service = RealtimeService(ref);
  ref.onDispose(service.stopListening);
  return service;
});
