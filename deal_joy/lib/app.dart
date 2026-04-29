import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/domain/providers/auth_provider.dart';
import 'features/merchant/domain/providers/merchant_provider.dart';
import 'features/orders/domain/providers/pending_reviews_provider.dart';
import 'features/profile/data/repositories/referral_repository.dart';
import 'features/profile/domain/providers/payment_methods_provider.dart';
import 'features/profile/presentation/widgets/referral_welcome_dialog.dart';
import 'features/reviews/domain/providers/my_reviews_provider.dart';
import 'shared/providers/legal_provider.dart';
import 'shared/services/location_sync_service.dart';
import 'shared/services/push_notification_service.dart';
import 'shared/services/realtime_service.dart';
import 'shared/services/referral_link_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

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
        LocationSyncService().syncUserLocation(user.id);
      } else {
        // 用户登出 → 停止监听，释放 channel + 注销推送 token
        realtime.stopListening();
        push.removeToken();
      }
    });

    // 监听账号切换：对那些未通过 ref.watch(currentUserProvider) 绑定的 Provider，
    // 切号后手动 invalidate，避免新账号看到旧账号缓存数据
    ref.listen(authStateProvider, (previous, next) async {
      final event = next.valueOrNull?.event;
      if (event == AuthChangeEvent.signedIn) {
        ref.invalidate(toReviewProvider);           // Reviews → Pending
        ref.invalidate(myWrittenReviewsProvider);     // Reviews → Submitted
        ref.invalidate(savedMerchantIdsProvider);    // 收藏商家 ID 集合
        ref.invalidate(savedMerchantsProvider);      // 收藏商家列表
        ref.invalidate(paymentMethodsProvider);      // 已保存支付方式
        ref.invalidate(pendingConsentsProvider);     // 待签法律文档（版本升级后需重签）

        // 检查 deep link 带来的 pending referral code，自动绑定并显示欢迎弹窗
        _handlePendingReferral(router);
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

  /// 注册成功后检查是否有待应用的 referral code，有则绑定并弹出欢迎弹窗
  Future<void> _handlePendingReferral(dynamic router) async {
    try {
      final code = await ReferralLinkService.instance.consumePendingCode();
      if (code == null || code.isEmpty) return;

      final repo = ReferralRepository(Supabase.instance.client);
      final result = await repo.applyCode(code);

      if (!result.startsWith('ok:')) return;

      final parts = result.split(':');
      final amount = parts.length > 1 ? double.tryParse(parts[1]) ?? 0.0 : 0.0;
      if (amount <= 0) return;

      // 延迟一帧确保 UI 已渲染完成
      await Future.delayed(const Duration(milliseconds: 500));

      final ctx = router.routerDelegate.navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        showReferralWelcomeDialog(ctx, amount);
      }
    } catch (e) {
      // 绑定失败不影响用户体验，静默处理
      debugPrint('[Referral] handlePendingReferral error: $e');
    }
  }
}
