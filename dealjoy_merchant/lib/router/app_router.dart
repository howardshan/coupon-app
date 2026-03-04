// 商家端 App 路由配置
// 使用 go_router + ShellRoute（底部导航4个 Tab）
// Tab 路由: /dashboard  /scan  /orders  /me
// 非 Shell 路由（全屏）: 认证、Deal 管理、门店、财务、评价、分析、通知、营销、Influencer

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_shell.dart';

// ── Tab 页面 ─────────────────────────────────────────────────
import '../features/dashboard/pages/dashboard_page.dart';
import '../features/scan/pages/scan_page.dart';
import '../features/scan/pages/coupon_verify_page.dart';
import '../features/scan/pages/redemption_success_page.dart';
import '../features/scan/pages/redemption_history_page.dart';
import '../features/scan/models/coupon_info.dart';
import '../features/orders/pages/orders_list_page.dart';
import '../features/orders/pages/order_detail_page.dart';
import '../features/settings/pages/settings_page.dart';
import '../features/settings/pages/notification_preferences_page.dart';
import '../features/settings/pages/help_center_page.dart';
import '../features/settings/pages/account_security_page.dart';
import '../features/settings/pages/staff_accounts_page.dart';

// ── 认证 ─────────────────────────────────────────────────────
import '../features/merchant_auth/pages/merchant_login_page.dart';
import '../features/merchant_auth/pages/merchant_register_page.dart';
import '../features/merchant_auth/pages/merchant_review_status_page.dart';

// ── 门店 ─────────────────────────────────────────────────────
import '../features/store/pages/store_profile_page.dart';
import '../features/store/pages/store_edit_page.dart';
import '../features/store/pages/business_hours_page.dart';
import '../features/store/pages/store_photos_page.dart';
import '../features/store/pages/store_tags_page.dart';

// ── Deal 管理 ─────────────────────────────────────────────────
import '../features/deals/pages/deals_list_page.dart';
import '../features/deals/pages/deal_create_page.dart';
import '../features/deals/pages/deal_detail_page.dart';

// ── 评价 / 分析 / 财务 / 通知 / 营销 ───────────────────────────
import '../features/reviews/pages/reviews_page.dart';
import '../features/analytics/pages/analytics_page.dart';
import '../features/earnings/pages/earnings_page.dart';
import '../features/earnings/pages/transactions_page.dart';
import '../features/earnings/pages/earnings_report_page.dart';
import '../features/earnings/pages/payment_account_page.dart';
import '../features/notifications/pages/notifications_page.dart';
import '../features/marketing/pages/marketing_page.dart';
import '../features/marketing/pages/flash_deals_page.dart';
import '../features/marketing/pages/promotions_page.dart';

// ─────────────────────────────────────────────────────────────
// Auth 状态变化通知器：让 GoRouter 在 signIn/signOut 时自动重跑 redirect
// ─────────────────────────────────────────────────────────────
class _AuthChangeNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _sub;

  _AuthChangeNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final _authNotifier = _AuthChangeNotifier();

// 不需要登录的公开路由前缀
const _publicRoutes = ['/auth/login', '/auth/register', '/auth/review'];

final appRouter = GoRouter(
  initialLocation: '/dashboard',
  debugLogDiagnostics: false,
  // auth 状态变化时自动重新执行 redirect
  refreshListenable: _authNotifier,
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    final loc = state.matchedLocation;
    final isPublic = _publicRoutes.any((r) => loc.startsWith(r));

    // 未登录 → 跳登录页
    if (session == null && !isPublic) return '/auth/login';

    // 已登录但在认证页（login/register）→ 跳 dashboard
    // review 页允许已登录用户停留（等待审核状态）
    if (session != null &&
        (loc.startsWith('/auth/login') || loc.startsWith('/auth/register'))) {
      return '/dashboard';
    }

    return null;
  },
  routes: [
    // ──────────────────────────────────────────────────────────
    // Shell 路由（带底部导航的 4 个 Tab）
    // ──────────────────────────────────────────────────────────
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        // Tab 0: Dashboard
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardPage(),
        ),

        // Tab 1: Scan（扫码核销）+ 子页面
        GoRoute(
          path: '/scan',
          builder: (context, state) => const ScanPage(),
          routes: [
            GoRoute(
              path: 'verify',
              builder: (context, state) {
                final couponInfo = state.extra as CouponInfo;
                return CouponVerifyPage(couponInfo: couponInfo);
              },
            ),
            GoRoute(
              path: 'success',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>;
                return RedemptionSuccessPage(
                  redeemedAt: extra['redeemed_at'] as DateTime,
                  dealTitle: extra['deal_title'] as String,
                  couponId: extra['coupon_id'] as String,
                );
              },
            ),
            GoRoute(
              path: 'history',
              builder: (context, state) => const RedemptionHistoryPage(),
            ),
          ],
        ),

        // Tab 2: Orders（订单列表）+ 订单详情
        GoRoute(
          path: '/orders',
          builder: (context, state) => const OrdersListPage(),
          routes: [
            GoRoute(
              path: ':orderId',
              builder: (context, state) {
                final orderId = state.pathParameters['orderId']!;
                return OrderDetailPage(orderId: orderId);
              },
            ),
          ],
        ),

        // Tab 3: Me（设置）+ 子页面
        GoRoute(
          path: '/me',
          builder: (context, state) => const SettingsPage(),
          routes: [
            GoRoute(
              path: 'notifications',
              builder: (context, state) => const NotificationPreferencesPage(),
            ),
            GoRoute(
              path: 'help',
              builder: (context, state) => const HelpCenterPage(),
            ),
            GoRoute(
              path: 'account-security',
              builder: (context, state) => const AccountSecurityPage(),
            ),
            GoRoute(
              path: 'staff',
              builder: (context, state) => const StaffAccountsPage(),
            ),
          ],
        ),
      ],
    ),

    // ──────────────────────────────────────────────────────────
    // 全屏路由（无底部导航）
    // ──────────────────────────────────────────────────────────

    // 认证流程
    GoRoute(
      path: '/auth/login',
      builder: (context, state) => const MerchantLoginPage(),
    ),
    GoRoute(
      path: '/auth/register',
      builder: (context, state) => const MerchantRegisterPage(),
    ),
    GoRoute(
      path: '/auth/review',
      builder: (context, state) => const MerchantReviewStatusPage(),
    ),

    // 门店信息管理
    GoRoute(
      path: '/store',
      builder: (context, state) => const StoreProfilePage(),
      routes: [
        GoRoute(
          path: 'edit',
          builder: (context, state) => const StoreEditPage(),
        ),
        GoRoute(
          path: 'hours',
          builder: (context, state) => const BusinessHoursPage(),
        ),
        GoRoute(
          path: 'photos',
          builder: (context, state) => const StorePhotosPage(),
        ),
        GoRoute(
          path: 'tags',
          builder: (context, state) => const StoreTagsPage(),
        ),
      ],
    ),

    // Deal 管理
    GoRoute(
      path: '/deals',
      builder: (context, state) => const DealsListPage(),
      routes: [
        GoRoute(
          path: 'create',
          builder: (context, state) => const DealCreatePage(),
        ),
        GoRoute(
          path: ':dealId',
          builder: (context, state) {
            final dealId = state.pathParameters['dealId']!;
            return DealDetailPage(dealId: dealId);
          },
        ),
      ],
    ),

    // 评价管理
    GoRoute(
      path: '/reviews',
      builder: (context, state) => const ReviewsPage(),
    ),

    // 数据分析
    GoRoute(
      path: '/analytics',
      builder: (context, state) => const AnalyticsPage(),
    ),

    // 财务与结算
    GoRoute(
      path: '/earnings',
      builder: (context, state) => const EarningsPage(),
      routes: [
        GoRoute(
          path: 'transactions',
          builder: (context, state) => const TransactionsPage(),
        ),
        GoRoute(
          path: 'report',
          builder: (context, state) => const EarningsReportPage(),
        ),
        GoRoute(
          path: 'payment-account',
          builder: (context, state) => const PaymentAccountPage(),
        ),
      ],
    ),

    // 消息通知
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsPage(),
    ),

    // 营销工具
    GoRoute(
      path: '/marketing',
      builder: (context, state) => const MarketingPage(),
      routes: [
        GoRoute(
          path: 'flash-deals',
          builder: (context, state) => const FlashDealsPage(),
        ),
        GoRoute(
          path: 'promotions',
          builder: (context, state) => const PromotionsPage(),
        ),
      ],
    ),
  ],

  // 错误页面（路由找不到时）
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('Page Not Found')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            '404 — ${state.uri.path}',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => context.go('/dashboard'),
            child: const Text('Go to Dashboard'),
          ),
        ],
      ),
    ),
  ),
);
