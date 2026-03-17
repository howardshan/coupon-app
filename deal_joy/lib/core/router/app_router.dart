import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/domain/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/deals/presentation/screens/home_screen.dart';
import '../../features/deals/presentation/screens/deal_detail_screen.dart';
import '../../features/deals/presentation/screens/search_screen.dart';
import '../../features/checkout/presentation/screens/checkout_screen.dart';
import '../../features/checkout/presentation/screens/order_success_screen.dart';
import '../../features/deals/presentation/screens/history_screen.dart';
import '../../features/deals/presentation/screens/saved_deals_screen.dart';
import '../../features/orders/presentation/screens/orders_screen.dart';
import '../../features/orders/presentation/screens/coupon_screen.dart';
import '../../features/orders/presentation/screens/coupons_screen.dart';
import '../../features/orders/presentation/screens/order_detail_screen.dart';
import '../../features/orders/presentation/screens/refund_request_screen.dart';
import '../../features/orders/presentation/screens/post_use_refund_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/reviews/presentation/screens/write_review_screen.dart';
import '../../features/merchant/presentation/screens/merchant_dashboard_screen.dart';
import '../../features/merchant/presentation/screens/merchant_detail_screen.dart';
import '../../features/merchant/presentation/screens/photo_gallery_screen.dart';
import '../../features/merchant/presentation/screens/qr_scanner_screen.dart';
import '../../features/merchant/presentation/screens/brand_detail_screen.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/cart/presentation/screens/cart_screen.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/splash_screen.dart';

/// Bridges Riverpod's authStateProvider → GoRouter's refreshListenable.
/// GoRouter calls redirect() whenever this notifier fires.
class _AuthChangeNotifier extends ChangeNotifier {
  late final ProviderSubscription _sub;

  _AuthChangeNotifier(Ref ref) {
    _sub = ref.listen(authStateProvider, (_, _) => notifyListeners());
  }

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

// 分离 root navigator 和 shell navigator，避免 page key 冲突
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthChangeNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isLoading = authState.isLoading;
      final isLoggedIn = authState.valueOrNull?.session != null;
      final currentPath = state.matchedLocation;
      final isAuthRoute = currentPath.startsWith('/auth');
      final isSplash = currentPath == '/splash';

      // Still resolving auth — stay on (or go to) splash
      if (isLoading) return isSplash ? null : '/splash';

      // Auth resolved, not logged in
      if (!isLoggedIn) {
        if (isAuthRoute) return null; // already on login/register
        // 保存用户想去的页面，登录后跳回
        return '/auth/login?redirect=${Uri.encodeComponent(currentPath)}';
      }

      // 已登录但在重置密码页面 — 允许留在该页面（recovery session）
      if (currentPath == '/auth/reset-password') return null;

      // Logged in — leave splash or auth routes
      if (isSplash || isAuthRoute) {
        // 登录后跳回之前的页面
        final redirect = state.uri.queryParameters['redirect'];
        if (redirect != null &&
            redirect.isNotEmpty &&
            !redirect.startsWith('/auth')) {
          return redirect;
        }
        return '/home';
      }

      return null; // no redirect needed
    },
    routes: [
      // Splash (shown while auth state resolves)
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),

      // Auth routes
      GoRoute(path: '/auth/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/auth/register',
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/auth/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/auth/reset-password',
        builder: (_, _) => const ResetPasswordScreen(),
      ),

      // Main shell with 4-tab bottom nav
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (_, state) => const NoTransitionPage(
              key: ValueKey('tab-home'),
              child: HomeScreen(),
            ),
          ),
          GoRoute(
            path: '/chat',
            pageBuilder: (_, state) => const NoTransitionPage(
              key: ValueKey('tab-chat'),
              child: ChatScreen(),
            ),
          ),
          GoRoute(
            path: '/cart',
            pageBuilder: (_, state) => const NoTransitionPage(
              key: ValueKey('tab-cart'),
              child: CartScreen(),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, state) => const NoTransitionPage(
              key: ValueKey('tab-profile'),
              child: ProfileScreen(),
            ),
          ),
        ],
      ),

      // Merchant static routes must come before parameterized /merchant/:id
      GoRoute(
        path: '/merchant/dashboard',
        builder: (_, _) => const MerchantDashboardScreen(),
      ),
      GoRoute(
        path: '/merchant/scan',
        builder: (_, _) => const QrScannerScreen(),
      ),

      // V2.4 品牌聚合页
      GoRoute(
        path: '/brand/:brandId',
        builder: (_, state) =>
            BrandDetailScreen(brandId: state.pathParameters['brandId']!),
      ),

      // Merchant detail (parameterized — must be after static merchant routes)
      GoRoute(
        path: '/merchant/:id',
        builder: (_, state) =>
            MerchantDetailScreen(merchantId: state.pathParameters['id']!),
      ),

      // 商家相册页
      GoRoute(
        path: '/merchant/:id/photos',
        builder: (_, state) =>
            PhotoGalleryScreen(merchantId: state.pathParameters['id']!),
      ),

      // Search
      GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),

      // Deal detail
      GoRoute(
        path: '/deals/:id',
        builder: (_, state) =>
            DealDetailScreen(dealId: state.pathParameters['id']!),
      ),

      // Checkout flow
      GoRoute(
        path: '/checkout/:dealId',
        builder: (_, state) => CheckoutScreen(
          dealId: state.pathParameters['dealId']!,
          purchasedMerchantId: state.uri.queryParameters['merchantId'],
        ),
      ),
      GoRoute(
        path: '/order-success/:orderId',
        builder: (_, state) =>
            OrderSuccessScreen(orderId: state.pathParameters['orderId']!),
      ),

      // Coupon QR code
      GoRoute(
        path: '/coupon/:couponId',
        builder: (_, state) =>
            CouponScreen(couponId: state.pathParameters['couponId']!),
      ),

      // Orders (standalone, accessible from profile)
      GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen()),

      // Order detail (single order)
      GoRoute(
        path: '/order/:orderId',
        builder: (_, state) =>
            OrderDetailScreen(orderId: state.pathParameters['orderId']!),
      ),

      // Saved deals (collection)
      GoRoute(path: '/collection', builder: (_, _) => const SavedDealsScreen()),
      GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),

      // Refund request
      GoRoute(
        path: '/refund/:orderId',
        builder: (_, state) =>
            RefundRequestScreen(orderId: state.pathParameters['orderId']!),
      ),

      // 核销后退款申请（需商家审批）
      GoRoute(
        path: '/post-use-refund/:orderId',
        builder: (_, state) => PostUseRefundScreen(
            orderId: state.pathParameters['orderId']!),
      ),

      // My Coupons list (tabbed by status)
      GoRoute(path: '/coupons', builder: (_, _) => const CouponsScreen()),

      // Reviews
      GoRoute(
        path: '/review/:dealId',
        builder: (_, state) =>
            WriteReviewScreen(dealId: state.pathParameters['dealId']!),
      ),
    ],
    errorBuilder: (context, state) =>
        Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
  );
});
