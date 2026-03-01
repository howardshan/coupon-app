import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/domain/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/deals/presentation/screens/home_screen.dart';
import '../../features/deals/presentation/screens/deal_detail_screen.dart';
import '../../features/checkout/presentation/screens/checkout_screen.dart';
import '../../features/checkout/presentation/screens/order_success_screen.dart';
import '../../features/orders/presentation/screens/orders_screen.dart';
import '../../features/orders/presentation/screens/coupon_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/reviews/presentation/screens/write_review_screen.dart';
import '../../features/merchant/presentation/screens/merchant_dashboard_screen.dart';
import '../../features/merchant/presentation/screens/merchant_detail_screen.dart';
import '../../features/merchant/presentation/screens/qr_scanner_screen.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/cart/presentation/screens/cart_screen.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/splash_screen.dart';

/// Bridges Riverpod's authStateProvider → GoRouter's refreshListenable.
/// GoRouter calls redirect() whenever this notifier fires.
class _AuthChangeNotifier extends ChangeNotifier {
  late final ProviderSubscription _sub;

  _AuthChangeNotifier(Ref ref) {
    _sub = ref.listen(authStateProvider, (_, __) => notifyListeners());
  }

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthChangeNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
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
        return '/auth/login';
      }

      // Logged in — leave splash or auth routes
      if (isSplash || isAuthRoute) return '/home';

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

      // Main shell with 4-tab bottom nav
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          GoRoute(path: '/chat', builder: (_, _) => const ChatScreen()),
          GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
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

      // Merchant detail (parameterized — must be after static merchant routes)
      GoRoute(
        path: '/merchant/:id',
        builder: (_, state) =>
            MerchantDetailScreen(merchantId: state.pathParameters['id']!),
      ),

      // Deal detail
      GoRoute(
        path: '/deals/:id',
        builder: (_, state) =>
            DealDetailScreen(dealId: state.pathParameters['id']!),
      ),

      // Checkout flow
      GoRoute(
        path: '/checkout/:dealId',
        builder: (_, state) =>
            CheckoutScreen(dealId: state.pathParameters['dealId']!),
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
