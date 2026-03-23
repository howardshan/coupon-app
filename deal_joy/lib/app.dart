import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/domain/providers/auth_provider.dart';
import 'shared/services/realtime_service.dart';

/// 禁用 Android Material 3 "stretch" 过度滚动效果，避免图片和文字变形
class _NoStretchScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class DealJoyApp extends ConsumerWidget {
  const DealJoyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // 监听用户登录/登出状态，自动启停 Realtime 订阅
    ref.listen(currentUserProvider, (previous, next) {
      final user = next.valueOrNull;
      final realtime = ref.read(realtimeServiceProvider);
      if (user != null) {
        // 用户登录 → 开始监听该用户的订单/券变化
        realtime.startListening(user.id);
      } else {
        // 用户登出 → 停止监听，释放 channel
        realtime.stopListening();
      }
    });

    return MaterialApp.router(
      title: 'DealJoy',
      theme: AppTheme.light,
      routerConfig: router,
      scrollBehavior: _NoStretchScrollBehavior(),
      debugShowCheckedModeBanner: false,
    );
  }
}
