import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import '../../features/auth/domain/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/verify_otp_screen.dart';
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
import '../../features/orders/presentation/screens/gift_claim_screen.dart';
import '../../features/orders/presentation/screens/order_detail_screen.dart';
import '../../features/orders/presentation/screens/voucher_detail_screen.dart';
import '../../features/orders/presentation/screens/refund_request_screen.dart';
import '../../features/after_sales/presentation/pages/after_sales_request_form_page.dart';
import '../../features/after_sales/presentation/pages/after_sales_timeline_page.dart';
import '../../features/after_sales/presentation/pages/my_after_sales_list_page.dart';
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
import '../../features/reviews/presentation/screens/my_reviews_screen.dart';
import '../../features/merchant/presentation/screens/merchant_detail_screen.dart';
import '../../features/merchant/presentation/screens/photo_gallery_screen.dart';
import '../../features/merchant/presentation/screens/qr_scanner_screen.dart';
import '../../features/merchant/presentation/screens/brand_detail_screen.dart';
import '../../features/chat/presentation/screens/chat_list_screen.dart';
import '../../features/chat/presentation/screens/chat_detail_screen.dart';
import '../../features/chat/presentation/screens/friend_list_screen.dart';
import '../../features/chat/presentation/screens/friend_requests_screen.dart';
import '../../features/chat/presentation/screens/notification_screen.dart';
import '../../features/chat/presentation/screens/chat_search_screen.dart';
import '../../features/support/presentation/screens/customer_support_screen.dart';
import '../../features/support/presentation/screens/support_chat_screen.dart';
import '../../features/cart/data/models/cart_item_model.dart';
import '../../features/cart/presentation/screens/cart_screen.dart';
import '../../features/welcome/presentation/screens/welcome_splash_screen.dart';
import '../../features/welcome/presentation/screens/onboarding_screen.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/splash_screen.dart';
import 'app_route_observer.dart';
import '../../shared/widgets/legal_document_screen.dart';

/// Bridges Riverpod's authStateProvider → GoRouter's refreshListenable.
/// GoRouter calls redirect() whenever this notifier fires.
class _AuthChangeNotifier extends ChangeNotifier {
  late final ProviderSubscription _sub;

  _AuthChangeNotifier(Ref ref) {
    _sub = ref.listen(authStateProvider, (_, _) => notifyListeners());
    // 注意：不再监听 currentUserProvider，因为 redirect 只依赖 authStateProvider。
    // currentUserProvider 是 FutureProvider，频繁触发会导致 GoRouter 在导航动画中
    // 重建路由栈，产生 Navigator key reservation 冲突。
  }

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

// 分离 root navigator 和 shell navigator，避免 page key 冲突
// rootNavigatorKey 公开给 PushNotificationService 用于后台通知点击跳转
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthChangeNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    observers: [appRouteObserver],
    // 启动时先进入 /splash（auth loading），再由 redirect 根据登录状态分发
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

      final isWelcome = currentPath == '/welcome';
      final isOnboarding = currentPath == '/onboarding';

      // 认证状态解析中 — 停在 /splash 等待
      if (isLoading) {
        if (isSplash) return null;
        return '/splash';
      }

      // 密码重置 recovery session — 强制跳转重置密码页（最高优先级）
      if (authValue?.event == AuthChangeEvent.passwordRecovery) {
        return currentPath == '/auth/reset-password' ? null : '/auth/reset-password';
      }

      // 未登录 — 强制登录，只允许 /auth/* 路由
      if (!isLoggedIn) {
        if (isAuthRoute) return null;
        // 保留原路径作为 redirect 参数，登录后跳回
        if (currentPath != '/' && currentPath != '/splash') {
          return '/auth/login?redirect=${Uri.encodeComponent(currentPath)}';
        }
        return '/auth/login';
      }

      // 已登录但在重置密码页面 — 允许留在该页面
      if (currentPath == '/auth/reset-password') return null;

      // Welcome splash 和 Onboarding 自己控制退出，不被 redirect 干扰
      if (isWelcome || isOnboarding) return null;

      // 已登录且在 /splash 或 /auth/* 路由 — 跳转到 /welcome（开屏广告 + onboarding 分发）
      if (isSplash || isAuthRoute) {
        final redirect = state.uri.queryParameters['redirect'];
        if (redirect != null &&
            redirect.isNotEmpty &&
            !redirect.startsWith('/auth') &&
            redirect != '/splash') {
          return redirect;
        }
        return '/welcome';
      }

      return null; // no redirect needed
    },
    routes: [
      // 开屏广告 Splash（每次启动显示，无配置时自动跳过）
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeSplashScreen()),

      // 首次安装引导页
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),

      // Auth loading（认证状态解析中显示）
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),

      // Auth routes
      GoRoute(path: '/auth/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/auth/register',
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/auth/verify-otp',
        builder: (_, state) => VerifyOtpScreen(
          email: state.uri.queryParameters['email'] ?? '',
        ),
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
              child: ChatListScreen(),
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
      GoRoute(
        path: '/my-after-sales',
        builder: (context, _) => const MyAfterSalesListPage(),
      ),

      // Orders (standalone, accessible from profile)
      GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen()),

      // 待评价页面
      GoRoute(path: '/to-review', builder: (_, _) => const ToReviewScreen()),

      // 我的评价（已提交列表）
      GoRoute(path: '/my-reviews', builder: (_, _) => const MyReviewsScreen()),

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
        builder: (_, state) {
          final itemIdsRaw = state.uri.queryParameters['itemIds'];
          final aggregate = state.uri.queryParameters['aggregate'] == '1';
          final aggregatedIds = itemIdsRaw == null || itemIdsRaw.isEmpty
              ? const <String>{}
              : itemIdsRaw
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toSet();
          final useAggregate = aggregate && aggregatedIds.isNotEmpty;
          return VoucherDetailScreen(
            orderId: state.pathParameters['orderId']!,
            dealId: state.uri.queryParameters['dealId'] ?? '',
            aggregateByDeal: useAggregate,
            aggregatedOrderItemIds: aggregatedIds,
          );
        },
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

      // My Coupons list（?tab= 与 coupons_screen _tabs 顺序一致；reviews 可配 sub=）
      GoRoute(
        path: '/coupons',
        builder: (_, state) {
          final tab = state.uri.queryParameters['tab'];
          final sub = state.uri.queryParameters['sub'];
          // 与 deal_joy/.../coupons_screen.dart _tabs 下标一致
          var initialTab = switch (tab) {
            'unused' => 0,
            'used' => 1,
            'reviews' => 2,
            'expired' => 3,
            'refunded' => 4,
            'gifted' => 5,
            _ => 0,
          };
          var initialSub = 0;
          if (sub == 'submitted') {
            initialSub = 1;
          } else if (sub == 'pending') {
            initialSub = 0;
          }
          return CouponsScreen(
            key: ValueKey('coupons-$initialTab-$initialSub'),
            initialTabIndex: initialTab,
            initialReviewsSubIndex: initialSub,
          );
        },
      ),

      // Gift claim — 受赠方通过 deep link 领取礼品券
      GoRoute(
        path: '/gift/claim',
        builder: (_, state) => GiftClaimScreen(
          claimToken: state.uri.queryParameters['token'] ?? '',
        ),
      ),

      // Customer Support
      GoRoute(
        path: '/support',
        builder: (_, _) => const CustomerSupportScreen(),
      ),
      GoRoute(
        path: '/support/chat',
        builder: (_, _) => const SupportChatScreen(),
      ),

      // 搜索用户页
      GoRoute(
        path: '/chat/search',
        builder: (_, _) => const ChatSearchScreen(),
      ),
      // 好友管理页（必须在 /chat/:conversationId 之前，避免被参数路由拦截）
      GoRoute(
        path: '/chat/friends',
        builder: (_, _) => const FriendListScreen(),
      ),
      GoRoute(
        path: '/chat/friend-requests',
        builder: (_, _) => const FriendRequestsScreen(),
      ),
      GoRoute(
        path: '/chat/notifications',
        builder: (_, _) => const NotificationScreen(),
      ),

      // Chat detail — 聊天详情页
      GoRoute(
        path: '/chat/:conversationId',
        builder: (_, state) => ChatDetailScreen(
          conversationId: state.pathParameters['conversationId']!,
        ),
      ),

      // Reviews
      GoRoute(
        path: '/review/:dealId',
        builder: (_, state) => WriteReviewScreen(
          dealId: state.pathParameters['dealId']!,
          merchantId: state.uri.queryParameters['merchantId'] ?? '',
          orderItemId: state.uri.queryParameters['orderItemId'] ?? '',
          existingReviewId: state.uri.queryParameters['reviewId'],
        ),
      ),

      // 法律文档页面（服务条款、隐私政策等）
      GoRoute(
        path: '/legal/:slug',
        name: 'legal',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final slug = state.pathParameters['slug'] ?? '';
          final title = state.uri.queryParameters['title'] ?? 'Legal Document';
          return LegalDocumentScreen(slug: slug, title: title);
        },
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
