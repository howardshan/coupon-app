import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import '../../features/auth/domain/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/auth/presentation/screens/phone_number_screen.dart';
import '../../features/deals/presentation/screens/home_screen.dart';
import '../../features/deals/presentation/screens/deal_detail_screen.dart';
import '../../features/deals/presentation/screens/search_screen.dart';
import '../../features/checkout/presentation/screens/checkout_screen.dart';
import '../../features/checkout/presentation/screens/order_success_screen.dart';
import '../../features/deals/presentation/screens/history_screen.dart';
import '../../features/deals/presentation/screens/saved_deals_screen.dart';
import '../../features/orders/presentation/screens/orders_screen.dart';
import '../../features/orders/presentation/screens/to_review_screen.dart';
import '../../features/orders/presentation/screens/coupon_screen.dart';
import '../../features/orders/presentation/screens/coupons_screen.dart';
import '../../features/orders/presentation/screens/order_detail_screen.dart';
import '../../features/orders/presentation/screens/voucher_detail_screen.dart';
import '../../features/orders/presentation/screens/refund_request_screen.dart';
import '../../features/after_sales/presentation/pages/after_sales_request_form_page.dart';
import '../../features/after_sales/presentation/pages/after_sales_timeline_page.dart';
import '../../features/after_sales/presentation/pages/after_sales_screen_args.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/profile/presentation/screens/store_credit_screen.dart';
import '../../features/profile/presentation/screens/payment_methods_screen.dart';
import '../../features/profile/presentation/screens/change_email_screen.dart';
import '../../features/profile/presentation/screens/change_password_screen.dart';
import '../../features/profile/presentation/screens/change_phone_screen.dart';
import '../../features/profile/presentation/screens/billing_address_screen.dart';
import '../../features/reviews/presentation/screens/write_review_screen.dart';
import '../../features/merchant/presentation/screens/merchant_dashboard_screen.dart';
import '../../features/merchant/presentation/screens/merchant_detail_screen.dart';
import '../../features/merchant/presentation/screens/photo_gallery_screen.dart';
import '../../features/merchant/presentation/screens/qr_scanner_screen.dart';
import '../../features/merchant/presentation/screens/brand_detail_screen.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/cart/data/models/cart_item_model.dart';
import '../../features/cart/presentation/screens/cart_screen.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/splash_screen.dart';

/// Bridges Riverpod's authStateProvider → GoRouter's refreshListenable.
/// GoRouter calls redirect() whenever this notifier fires.
class _AuthChangeNotifier extends ChangeNotifier {
  late final ProviderSubscription _sub;
  late final ProviderSubscription _userSub;

  _AuthChangeNotifier(Ref ref) {
    _sub = ref.listen(authStateProvider, (_, _) => notifyListeners());
    // 监听用户 profile 变化（手机号填写后触发路由重检查）
    _userSub = ref.listen(currentUserProvider, (_, _) => notifyListeners());
  }

  @override
  void dispose() {
    _sub.close();
    _userSub.close();
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
      final authValue = authState.valueOrNull;
      final isLoggedIn = authValue?.session != null;
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

      // 密码重置 recovery session — 强制跳转重置密码页，忽略其他跳转逻辑
      if (authValue?.event == AuthChangeEvent.passwordRecovery) {
        return currentPath == '/auth/reset-password' ? null : '/auth/reset-password';
      }

      // 已登录但在重置密码页面 — 允许留在该页面（用户手动导航过来的场景）
      if (currentPath == '/auth/reset-password') return null;

      // 已登录 — 检查是否需要填写手机号
      if (currentPath == '/auth/phone') return null; // 已在手机号页面，不跳转
      final userAsync = ref.read(currentUserProvider);
      final userProfile = userAsync.valueOrNull;
      if (userProfile != null &&
          (userProfile.phone == null || userProfile.phone!.isEmpty)) {
        return '/auth/phone';
      }

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
      GoRoute(
        path: '/auth/phone',
        builder: (_, _) => const PhoneNumberScreen(),
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

      // Profile 编辑页
      GoRoute(
        path: '/profile/edit',
        builder: (_, _) => const EditProfileScreen(),
      ),

      // Store Credit 余额与流水页
      GoRoute(
        path: '/profile/store-credit',
        builder: (_, _) => const StoreCreditScreen(),
      ),

      // Payment Methods 已保存卡片管理页
      GoRoute(
        path: '/profile/payment-methods',
        builder: (_, _) => const PaymentMethodsScreen(),
      ),

      // Change Email 修改邮箱页
      GoRoute(
        path: '/profile/change-email',
        builder: (_, _) => const ChangeEmailScreen(),
      ),

      // Change Password 修改密码页
      GoRoute(
        path: '/profile/change-password',
        builder: (_, _) => const ChangePasswordScreen(),
      ),

      // Change Phone 修改手机号页
      GoRoute(
        path: '/profile/change-phone',
        builder: (_, _) => const ChangePhoneScreen(),
      ),

      // Billing Address 账单地址页
      GoRoute(
        path: '/profile/billing-address',
        builder: (_, _) => const BillingAddressScreen(),
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

      // Checkout flow — 单 deal 快速购买
      GoRoute(
        path: '/checkout/:dealId',
        builder: (_, state) => CheckoutScreen(
          dealId: state.pathParameters['dealId']!,
          purchasedMerchantId: state.uri.queryParameters['merchantId'],
        ),
      ),
      // Checkout flow — 购物车多 deal 结账（通过 extra 传递 cartItems）
      GoRoute(
        path: '/checkout-cart',
        builder: (_, state) {
          final items = state.extra as List<CartItemModel>?;
          return CheckoutScreen(cartItems: items ?? const []);
        },
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
      GoRoute(
        path: '/after-sales/:orderId',
        builder: (_, state) => AfterSalesTimelinePage(args: _resolveAfterSalesArgs(state)),
      ),
      GoRoute(
        path: '/after-sales/:orderId/request',
        builder: (_, state) => AfterSalesRequestFormPage(args: _resolveAfterSalesArgs(state)),
      ),

      // Orders (standalone, accessible from profile)
      GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen()),

      // 待评价页面
      GoRoute(path: '/to-review', builder: (_, _) => const ToReviewScreen()),

      // Order detail
      GoRoute(
        path: '/order/:orderId',
        builder: (_, state) => OrderDetailScreen(
          orderId: state.pathParameters['orderId']!,
        ),
      ),

      // Voucher detail（从 Coupons/Orders 列表点击单个 deal 进入）
      GoRoute(
        path: '/voucher/:orderId',
        builder: (_, state) => VoucherDetailScreen(
          orderId: state.pathParameters['orderId']!,
          dealId: state.uri.queryParameters['dealId'] ?? '',
        ),
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

AfterSalesScreenArgs _resolveAfterSalesArgs(GoRouterState state) {
  final extra = state.extra;
  if (extra is AfterSalesScreenArgs) {
    return extra;
  }
  final orderId = state.pathParameters['orderId'] ?? '';
  return AfterSalesScreenArgs(
    orderId: orderId,
    couponId: state.uri.queryParameters['couponId'] ?? '',
    dealTitle: state.uri.queryParameters['dealTitle'] ?? 'After-Sales Support',
    totalAmount: double.tryParse(state.uri.queryParameters['amount'] ?? '0') ?? 0,
    merchantName: state.uri.queryParameters['merchantName'],
    couponCode: state.uri.queryParameters['couponCode'],
  );
}
