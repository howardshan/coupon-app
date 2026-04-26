// 推送通知服务：管理 FCM token 注册、前台/后台消息处理、通知点击跳转
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../core/router/app_router.dart';

/// FCM 推送通知服务，负责：
/// 1. 请求通知权限
/// 2. 获取/刷新 FCM token 并注册到 user_fcm_tokens 表
/// 3. 前台消息 → 本地通知弹出
/// 4. 通知点击 → 根据 data 字段路由跳转
class PushNotificationService {
  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  String? _currentUserId;

  PushNotificationService();

  /// 初始化推送服务（用户登录后调用）
  Future<void> init(String userId) async {
    _currentUserId = userId;

    // 请求通知权限
    await _requestPermission();

    // 初始化本地通知插件
    await _setupLocalNotifications();

    // 获取并注册 FCM token
    await _getAndRegisterToken();

    // 监听 token 刷新
    _messaging.onTokenRefresh.listen(_onTokenRefresh);

    // 前台消息监听
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 后台通知点击（App 在后台被唤醒）
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);

    // App 从终止状态被通知唤醒
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _onNotificationTap(initialMessage);
    }
  }

  /// 请求通知权限（iOS 必须，Android 13+ 必须）
  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[FCM] permission: ${settings.authorizationStatus}');
  }

  /// 初始化 flutter_local_notifications
  Future<void> _setupLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // 已通过 FCM 请求
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // 创建 Android 通知 channel
    const channel = AndroidNotificationChannel(
      'crunchyplum_notifications',
      'Crunchy Plum Notifications',
      description: 'Crunchy Plum push notifications',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// 获取 FCM token 并注册到 user_fcm_tokens 表
  Future<void> _getAndRegisterToken() async {
    try {
      // iOS 需要先获取 APNS token
      if (Platform.isIOS) {
        await _messaging.getAPNSToken();
      }
      final token = await _messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }
    } catch (e) {
      debugPrint('[FCM] getToken error: $e');
    }
  }

  /// token 刷新回调
  Future<void> _onTokenRefresh(String token) async {
    await _registerToken(token);
  }

  /// 将 FCM token 注册（upsert）到 user_fcm_tokens 表
  Future<void> _registerToken(String token) async {
    if (_currentUserId == null) return;
    try {
      final deviceType = Platform.isIOS ? 'ios' : 'android';
      await Supabase.instance.client.from('user_fcm_tokens').upsert(
        {
          'user_id': _currentUserId,
          'fcm_token': token,
          'device_type': deviceType,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,fcm_token',
      );
      debugPrint('[FCM] token registered: ${token.substring(0, 20)}...');
    } catch (e) {
      debugPrint('[FCM] registerToken error: $e');
    }
  }

  /// 前台收到消息 → 弹出本地通知
  void _onForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM] foreground message: ${message.messageId}');
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      message.hashCode,
      notification.title ?? 'Crunchy Plum',
      notification.body ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'crunchyplum_notifications',
          'Crunchy Plum Notifications',
          channelDescription: 'Crunchy Plum push notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      // 将 FCM data 序列化为 payload，供点击时解析
      payload: _encodePayload(message.data),
    );
  }

  /// FCM 通知点击（后台/终止状态唤醒）
  void _onNotificationTap(RemoteMessage message) {
    debugPrint('[FCM] notification tapped: ${message.data}');
    _navigateByData(message.data);
  }

  /// 本地通知点击回调
  void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final data = _decodePayload(payload);
    _navigateByData(data);
  }

  /// 根据通知 data 字段路由跳转（与 notification_screen.dart _handleTap 保持一致）
  void _navigateByData(Map<String, dynamic> data) {
    final router = rootNavigatorKey.currentContext;
    if (router == null) return;

    final type = data['type'] as String? ?? '';
    switch (type) {
      case 'transaction':
        final orderId = data['order_id'] as String?;
        if (orderId != null) {
          GoRouter.of(router).push('/order/$orderId');
        } else {
          GoRouter.of(router).push('/orders');
        }
      case 'friend_request':
        GoRouter.of(router).push('/chat/friend-requests');
      case 'friend_activity':
        final dealId = data['deal_id'] as String?;
        if (dealId != null) GoRouter.of(router).push('/deals/$dealId');
      case 'review_reply':
        final dealId = data['deal_id'] as String?;
        if (dealId != null) GoRouter.of(router).push('/deals/$dealId');
      case 'chat_message':
        final conversationId = data['conversation_id'] as String?;
        if (conversationId != null) {
          GoRouter.of(router).push('/chat/$conversationId');
        }
      case 'announcement':
        GoRouter.of(router).push('/chat/notifications');
      case 'promo':
        // 促销通知：优先跳 deal 详情，其次跳商家详情，兜底跳通知列表
        final dealId = data['deal_id'] as String?;
        final merchantId = data['merchant_id'] as String?;
        if (dealId != null) {
          GoRouter.of(router).push('/deals/$dealId');
        } else if (merchantId != null) {
          GoRouter.of(router).push('/merchant/$merchantId');
        } else {
          GoRouter.of(router).push('/chat/notifications');
        }
      default:
        GoRouter.of(router).push('/chat/notifications');
    }
  }

  /// 登出时删除当前设备的 FCM token
  Future<void> removeToken() async {
    if (_currentUserId == null) return;
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await Supabase.instance.client
            .from('user_fcm_tokens')
            .delete()
            .eq('user_id', _currentUserId!)
            .eq('fcm_token', token);
        debugPrint('[FCM] token removed');
      }
    } catch (e) {
      debugPrint('[FCM] removeToken error: $e');
    }
    _currentUserId = null;
  }

  // ---- payload 编解码工具（将 Map 序列化为简单字符串传递给本地通知）----

  String _encodePayload(Map<String, dynamic> data) {
    return data.entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  Map<String, dynamic> _decodePayload(String payload) {
    final map = <String, dynamic>{};
    for (final pair in payload.split('&')) {
      final idx = pair.indexOf('=');
      if (idx > 0) {
        map[pair.substring(0, idx)] = pair.substring(idx + 1);
      }
    }
    return map;
  }
}

/// Riverpod Provider
final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) {
  return PushNotificationService();
});
