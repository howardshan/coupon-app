// DealJoy 商家端 App 入口
// 初始化: Supabase + flutter_dotenv + Riverpod + go_router

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'router/app_router.dart';
import 'features/dashboard/providers/dashboard_provider.dart';
import 'features/orders/providers/orders_provider.dart';
import 'features/store/providers/store_provider.dart';
import 'features/deals/providers/deals_provider.dart';
import 'features/reviews/providers/reviews_provider.dart';
import 'features/notifications/providers/notifications_provider.dart';
import 'features/earnings/providers/earnings_provider.dart';
import 'features/analytics/providers/analytics_provider.dart';
import 'features/scan/providers/scan_provider.dart';
import 'features/menu/providers/menu_provider.dart';
import 'features/menu/providers/category_provider.dart';
import 'features/influencer/providers/influencer_provider.dart';
import 'shared/providers/legal_provider.dart';

// 全局禁用 overscroll 拉伸效果（Android 默认有 stretch/glow）
class _NoOverscrollBehavior extends ScrollBehavior {
  const _NoOverscrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child; // 不添加任何 overscroll 效果
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 加载 .env 配置
  await dotenv.load(fileName: '.env');

  // 初始化 Supabase（与用户端共享同一个 project）
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // 初始化 Stripe（商家端广告充值 PaymentSheet）
  try {
    final stripeKey = dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? '';
    if (stripeKey.startsWith('pk_')) {
      Stripe.publishableKey = stripeKey;
      await Stripe.instance.applySettings();
    }
  } catch (e) {
    debugPrint('[DealJoyMerchant] Stripe init failed: $e');
  }

  runApp(
    // Riverpod 全局 Provider 容器
    const ProviderScope(
      child: DealJoyMerchantApp(),
    ),
  );
}

class DealJoyMerchantApp extends ConsumerStatefulWidget {
  const DealJoyMerchantApp({super.key});

  @override
  ConsumerState<DealJoyMerchantApp> createState() => _DealJoyMerchantAppState();
}

class _DealJoyMerchantAppState extends ConsumerState<DealJoyMerchantApp> {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    // 监听账号切换：登录新账号后，invalidate 所有业务数据 Provider，
    // 避免新账号看到旧账号缓存数据（需要手动下拉刷新的问题）
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn) {
        _invalidateAllBusinessProviders();
      }
    });
  }

  /// 切换账号后强制清空所有业务 Provider 缓存，触发重新拉取
  void _invalidateAllBusinessProviders() {
    ref.invalidate(dashboardProvider);
    ref.invalidate(ordersNotifierProvider);
    ref.invalidate(orderFilterProvider);
    ref.invalidate(merchantDealsForFilterProvider);
    ref.invalidate(storeProvider);
    ref.invalidate(dealsProvider);
    ref.invalidate(reviewsProvider);
    ref.invalidate(notificationsNotifierProvider);
    ref.invalidate(unreadCountProvider);
    ref.invalidate(earningsSummaryProvider);
    ref.invalidate(transactionsProvider);
    ref.invalidate(overviewProvider);
    ref.invalidate(redemptionHistoryProvider);
    ref.invalidate(menuProvider);
    ref.invalidate(categoryProvider);
    ref.invalidate(influencerProvider);
    ref.invalidate(pendingConsentsProvider); // 待签法律文档（版本升级后需重签）
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'DealJoy Merchant',
      debugShowCheckedModeBanner: false,
      // 全局禁用 overscroll 拉伸/glow 效果
      scrollBehavior: const _NoOverscrollBehavior(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B35), // 品牌橙色
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'SF Pro Display', // iOS 系统字体，Android 降级到 Roboto
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1A1A2E),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFFF6B35).withValues(alpha: 0.12),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFF6B35),
              );
            }
            return TextStyle(fontSize: 12, color: Colors.grey.shade600);
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Color(0xFFFF6B35));
            }
            return IconThemeData(color: Colors.grey.shade600);
          }),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B35),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
      routerConfig: appRouter,
    );
  }
}
