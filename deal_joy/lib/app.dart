import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/domain/providers/auth_provider.dart';
import 'features/merchant/domain/providers/merchant_provider.dart';
import 'features/orders/domain/providers/pending_reviews_provider.dart';
import 'features/profile/domain/providers/payment_methods_provider.dart';
import 'features/reviews/domain/providers/my_reviews_provider.dart';
import 'shared/providers/legal_provider.dart';
import 'shared/services/push_notification_service.dart';
import 'shared/services/realtime_service.dart';

/// 禁用 Android Material 3 "stretch" 过度滚动效果，避免图片和文字变形
class _NoStretchScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class CrunchyPlumApp extends ConsumerWidget {
  const CrunchyPlumApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // 监听用户登录/登出状态，自动启停 Realtime 订阅和推送通知
    ref.listen(currentUserProvider, (previous, next) {
      final user = next.valueOrNull;
      final realtime = ref.read(realtimeServiceProvider);
      final push = ref.read(pushNotificationServiceProvider);
      if (user != null) {
        // 用户登录 → 开始监听该用户的订单/券变化 + 注册推送
        realtime.startListening(user.id);
        push.init(user.id);
      } else {
        // 用户登出 → 停止监听，释放 channel + 注销推送 token
        realtime.stopListening();
        push.removeToken();
      }
    });

    // 监听账号切换：对那些未通过 ref.watch(currentUserProvider) 绑定的 Provider，
    // 切号后手动 invalidate，避免新账号看到旧账号缓存数据
    ref.listen(authStateProvider, (previous, next) {
      final event = next.valueOrNull?.event;
      if (event == AuthChangeEvent.signedIn) {
        ref.invalidate(toReviewProvider);           // Reviews → Pending
        ref.invalidate(myWrittenReviewsProvider);     // Reviews → Submitted
        ref.invalidate(savedMerchantIdsProvider);    // 收藏商家 ID 集合
        ref.invalidate(savedMerchantsProvider);      // 收藏商家列表
        ref.invalidate(paymentMethodsProvider);      // 已保存支付方式
        ref.invalidate(pendingConsentsProvider);     // 待签法律文档（版本升级后需重签）
      }
    });

    return MaterialApp.router(
      title: 'Crunchy Plum',
      theme: AppTheme.light,
      routerConfig: router,
      scrollBehavior: _NoStretchScrollBehavior(),
      debugShowCheckedModeBanner: false,
    );
  }
}
