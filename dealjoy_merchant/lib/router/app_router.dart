// 商家端 App 路由配置
// 使用 go_router + ShellRoute（底部导航4个 Tab）
// Tab 路由: /dashboard  /scan  /orders  /me
// 非 Shell 路由（全屏）: 认证、Deal 管理、门店、财务、评价、分析、通知、营销、Influencer

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/store/services/store_service.dart';

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
import '../features/settings/pages/email_preferences_page.dart';
import '../features/settings/pages/help_center_page.dart';
import '../features/settings/pages/account_security_page.dart';
import '../features/store/pages/staff_manage_page.dart';
import '../features/support/pages/support_chat_page.dart';

// ── 认证 ─────────────────────────────────────────────────────
import '../features/merchant_auth/pages/merchant_login_page.dart';
import '../features/merchant_auth/pages/merchant_register_page.dart';
import '../features/merchant_auth/pages/merchant_review_status_page.dart';
import '../features/merchant_auth/pages/staff_accept_page.dart';
import '../features/settings/pages/staff_profile_page.dart';

// ── 门店 ─────────────────────────────────────────────────────
import '../features/store/pages/store_profile_page.dart';
import '../features/store/pages/store_edit_page.dart';
import '../features/store/pages/business_hours_page.dart';
import '../features/store/pages/store_photos_page.dart';
import '../features/store/pages/store_tags_page.dart';
import '../features/store/pages/store_categories_page.dart';
import '../features/store/pages/store_facilities_page.dart';
import '../features/store/pages/store_selector_page.dart';
import '../features/store/pages/brand_manage_page.dart';
import '../features/store/pages/brand_info_page.dart';
import '../features/store/pages/brand_stores_page.dart';
import '../features/store/pages/brand_admins_page.dart';
import '../features/store/pages/brand_earnings_page.dart';
import '../features/store/pages/brand_withdrawal_page.dart';
import '../features/store/pages/brand_stripe_connect_page.dart';
import '../features/dashboard/pages/brand_overview_page.dart';

// ── 菜品管理 ─────────────────────────────────────────────────
import '../features/menu/pages/menu_list_page.dart';
import '../features/menu/pages/menu_edit_page.dart';
import '../features/menu/pages/category_manage_page.dart';
import '../features/menu/models/menu_item.dart' as menu_model;

// ── Deal 管理 ─────────────────────────────────────────────────
import '../features/deals/pages/deals_list_page.dart';
import '../features/deals/pages/deal_create_page.dart';
import '../features/deals/pages/deal_detail_page.dart';
import '../features/deals/pages/deal_templates_page.dart';
import '../features/deals/pages/deal_template_create_page.dart';
import '../features/deals/pages/store_deal_confirm_page.dart';

// ── 评价 / 分析 / 财务 / 通知 / 营销 ───────────────────────────
import '../features/reviews/pages/reviews_page.dart';
import '../features/analytics/pages/analytics_page.dart';
import '../features/earnings/pages/earnings_page.dart';
import '../features/earnings/pages/transactions_page.dart';
import '../features/earnings/pages/earnings_report_page.dart';
import '../features/earnings/pages/payment_account_page.dart';
import '../features/earnings/pages/withdrawal_page.dart';
import '../features/notifications/pages/notifications_page.dart';

// ── 广告投放 ──────────────────────────────────────────────────
import '../features/promotions/pages/promotions_page.dart';
import '../features/promotions/pages/campaign_create_page.dart';
import '../features/promotions/pages/campaign_edit_page.dart';
import '../features/promotions/pages/campaign_report_page.dart';
import '../features/promotions/pages/recharge_page.dart';

// ─────────────────────────────────────────────────────────────
// Auth 状态变化通知器：让 GoRouter 在 signIn/signOut 时自动重跑 redirect
// ─────────────────────────────────────────────────────────────
class _AuthChangeNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _sub;

  _AuthChangeNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      // 登出时清除审核状态缓存
      if (event.event == AuthChangeEvent.signedOut) {
        MerchantStatusCache.clear();
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────
// 商家审核状态缓存：避免每次路由跳转都查询数据库
// ─────────────────────────────────────────────────────────────
class MerchantStatusCache {
  static String? _cachedStatus; // 'approved', 'pending', 'rejected', 'none'
  static String? _cachedUserId;
  // 角色类型：用于登录后路由分流
  // 'store_owner' | 'brand_admin' | 'staff_cashier' | 'staff_service' | 'staff_manager'
  static String? _cachedRoleType;

  /// 获取角色类型（用于登录后路由分流）
  static String? get roleType => _cachedRoleType;

  /// 获取商家状态（有缓存直接返回，否则查 DB）
  static Future<String> getStatus() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return 'none';

    // 缓存命中（同一用户）
    if (_cachedStatus != null && _cachedUserId == user.id) {
      return _cachedStatus!;
    }

    // 查询数据库：依次检查 品牌管理员 → 门店 owner → 门店员工
    // 注意：品牌管理员必须先于门店 owner 检查，因为 brand_owner 同时也是门店 owner
    try {
      final supabase = Supabase.instance.client;

      // 1. 检查是否为品牌管理员（brand_admins 表，优先级最高）
      final brandAdmin = await supabase
          .from('brand_admins')
          .select('id, role')
          .eq('user_id', user.id)
          .maybeSingle();

      if (brandAdmin != null) {
        _cachedStatus = 'approved';
        _cachedUserId = user.id;
        _cachedRoleType = 'brand_admin';
        return _cachedStatus!;
      }

      // 2. 检查是否为门店 owner
      final merchantData = await supabase
          .from('merchants')
          .select('status')
          .eq('user_id', user.id)
          .maybeSingle();

      if (merchantData != null) {
        _cachedStatus = merchantData['status'] as String? ?? 'pending';
        _cachedUserId = user.id;
        _cachedRoleType = 'store_owner';
        return _cachedStatus!;
      }

      // 3a. 检查是否为在职员工（is_active = true）
      final activeStaff = await supabase
          .from('merchant_staff')
          .select('merchant_id, role')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .maybeSingle();

      if (activeStaff != null) {
        _cachedStatus = 'approved';
        _cachedUserId = user.id;
        final staffRole = activeStaff['role'] as String? ?? 'cashier';
        _cachedRoleType = 'staff_$staffRole';
        return _cachedStatus!;
      }

      // 3b. 检查是否为已禁用员工（is_active = false）— 独立查询避免 maybeSingle 多行报错
      final disabledStaff = await supabase
          .from('merchant_staff')
          .select('id')
          .eq('user_id', user.id)
          .eq('is_active', false)
          .limit(1)
          .maybeSingle();

      if (disabledStaff != null) {
        // ignore: avoid_print
        print('[MerchantStatusCache] disabled staff detected for ${user.email}');
        _cachedStatus = 'disabled';
        _cachedUserId = user.id;
        _cachedRoleType = null;
        return _cachedStatus!;
      }
      // ignore: avoid_print
      print('[MerchantStatusCache] no staff record found → none');

      _cachedStatus = 'none';
      _cachedUserId = user.id;
      _cachedRoleType = null;
    } catch (e, st) {
      // ignore: avoid_print
      print('[MerchantStatusCache] getStatus error: $e\n$st');
      return 'none';
    }

    return _cachedStatus!;
  }

  /// 清除缓存（登出、状态变更时调用）
  static void clear() {
    _cachedStatus = null;
    _cachedUserId = null;
    _cachedRoleType = null;
  }

  /// 手动设置状态（登录后已知状态时直接缓存，避免多余查询）
  /// [roleType] 可选，品牌管理员传 'brand_admin'，不传则不覆盖
  static void setStatus(String status, String userId, {String? roleType}) {
    _cachedStatus = status;
    _cachedUserId = userId;
    if (roleType != null) _cachedRoleType = roleType;
  }
}

final _authNotifier = _AuthChangeNotifier();

// 不需要登录的公开路由前缀
// 注意：/store-selector 需要登录（调用 Edge Function），不能放在公开路由里，
// 否则 session 过期后用户会停在 StoreSelectorPage 看到 "Failed to load stores"
const _publicRoutes = ['/auth/login', '/auth/register', '/auth/review', '/auth/disabled', '/staff/accept'];

final appRouter = GoRouter(
  initialLocation: '/dashboard',
  debugLogDiagnostics: false,
  // auth 状态变化时自动重新执行 redirect
  refreshListenable: _authNotifier,
  redirect: (context, state) async {
    final session = Supabase.instance.client.auth.currentSession;
    final loc = state.matchedLocation;
    final isPublic = _publicRoutes.any((r) => loc.startsWith(r));
    // ignore: avoid_print
    print('[REDIRECT] loc=$loc session=${session != null}');

    // 未登录 → 跳登录页
    if (session == null && !isPublic) return '/auth/login';

    // 未登录且在公开页面 → 放行
    if (session == null) return null;

    // ── 已登录：检查商家审核状态 ──
    if (loc.startsWith('/auth/register') || loc.startsWith('/auth/review') || loc.startsWith('/auth/disabled')) {
      // ignore: avoid_print
      print('[REDIRECT] bypass → null');
      return null;
    }

    final merchantStatus = await MerchantStatusCache.getStatus();
    // ignore: avoid_print
    print('[REDIRECT] status=$merchantStatus loc=$loc');

    if (loc.startsWith('/auth/login')) {
      // 已登录在登录页 → 根据角色和状态跳转
      switch (merchantStatus) {
        case 'approved':
          final roleType = MerchantStatusCache.roleType;
          if (roleType == 'brand_admin') return '/store-selector';
          if (roleType == 'staff_regional_manager') return '/store-selector';
          if (roleType == 'staff_cashier' || roleType == 'staff_trainee') return '/scan';
          if (roleType == 'staff_finance') return '/earnings';
          return '/dashboard';
        case 'pending':
        case 'rejected':
          return '/auth/review';
        case 'disabled':
          return '/auth/disabled';
        default:
          return '/auth/register';
      }
    }

    // 非公开路由：只有 approved 才能进入
    if (merchantStatus != 'approved') {
      switch (merchantStatus) {
        case 'pending':
        case 'rejected':
          return '/auth/review';
        case 'disabled':
          return '/auth/disabled';
        default:
          return '/auth/register';
      }
    }

    // 品牌管理员重启时：恢复上次选中的门店 ID，若无则跳 store-selector
    final roleType = MerchantStatusCache.roleType;
    if ((roleType == 'brand_admin' || roleType == 'staff_regional_manager') &&
        StoreService.globalActiveMerchantId == null &&
        !loc.startsWith('/store-selector')) {
      final restored = await StoreService.restoreActiveMerchantId();
      if (!restored) {
        // 没有保存过门店 ID → 跳转选店页
        return '/store-selector';
      }
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
                final redeemedRaw = extra['redeemed_at'];
                final redeemedAt = redeemedRaw is DateTime
                    ? redeemedRaw
                    : DateTime.parse(redeemedRaw as String);
                return RedemptionSuccessPage(
                  redeemedAt: redeemedAt,
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
          builder: (context, state) {
            final tab = int.tryParse(
                state.uri.queryParameters['tab'] ?? '') ?? 0;
            return OrdersListPage(initialTab: tab);
          },
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

        // Tab 3: Reviews（评价管理）— 客服/店长/老板可见
        GoRoute(
          path: '/reviews',
          builder: (context, state) => const ReviewsPage(),
        ),

        // Staff Profile（cashier/trainee 专用 Tab）
        GoRoute(
          path: '/staff/profile',
          builder: (context, state) => const StaffProfilePage(),
        ),

        // Tab 4: Me（设置）+ 子页面
        GoRoute(
          path: '/me',
          builder: (context, state) => const SettingsPage(),
          routes: [
            GoRoute(
              path: 'notifications',
              builder: (context, state) => const NotificationPreferencesPage(),
            ),
            GoRoute(
              path: 'email-notifications',
              builder: (context, state) => const EmailPreferencesPage(),
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
              builder: (context, state) => const StaffManagePage(),
            ),
            GoRoute(
              path: 'support',
              builder: (context, state) => const SupportChatPage(),
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
      builder: (context, state) {
        final invitationId = state.uri.queryParameters['invitation_id'];
        return MerchantLoginPage(invitationId: invitationId);
      },
    ),
    GoRoute(
      path: '/auth/register',
      builder: (context, state) {
        final isResubmit = state.extra as bool? ?? false;
        return MerchantRegisterPage(isResubmit: isResubmit);
      },
    ),
    GoRoute(
      path: '/auth/review',
      builder: (context, state) => const MerchantReviewStatusPage(),
    ),
    GoRoute(
      path: '/auth/disabled',
      builder: (context, state) => const _StaffDisabledPage(),
    ),
    GoRoute(
      path: '/staff/accept',
      builder: (context, state) {
        final invitationId = state.uri.queryParameters['invitation_id'];
        return StaffAcceptPage(invitationId: invitationId);
      },
    ),
    // 品牌管理员门店选择页
    GoRoute(
      path: '/store-selector',
      builder: (context, state) => const StoreSelectorPage(),
    ),

    // 品牌管理页 + 子页面
    GoRoute(
      path: '/brand-manage',
      builder: (context, state) => const BrandManagePage(),
      routes: [
        GoRoute(
          path: 'info',
          builder: (context, state) => const BrandInfoPage(),
        ),
        GoRoute(
          path: 'stores',
          builder: (context, state) => const BrandStoresPage(),
        ),
        GoRoute(
          path: 'admins',
          builder: (context, state) => const BrandAdminsPage(),
        ),
        // 品牌 Deal 列表（只显示多店 Deal）
        GoRoute(
          path: 'deals',
          builder: (context, state) => const DealsListPage(brandOnly: true),
        ),
        // 品牌财务（品牌佣金收入）
        GoRoute(
          path: 'earnings',
          builder: (context, state) => const BrandEarningsPage(),
        ),
        // 品牌提现
        GoRoute(
          path: 'withdrawal',
          builder: (context, state) => const BrandWithdrawalPage(),
        ),
        // 品牌 Stripe Connect 绑定
        GoRoute(
          path: 'stripe-connect',
          builder: (context, state) => const BrandStripeConnectPage(),
        ),
      ],
    ),

    // V2.1 品牌总览 Dashboard
    GoRoute(
      path: '/brand-overview',
      builder: (context, state) => const BrandOverviewPage(),
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
        GoRoute(
          path: 'categories',
          builder: (context, state) => const StoreCategoriesPage(),
        ),
        GoRoute(
          path: 'facilities',
          builder: (context, state) => const StoreFacilitiesPage(),
        ),
        // 菜品管理
        GoRoute(
          path: 'menu',
          builder: (context, state) => const MenuListPage(),
          routes: [
            // 分类管理
            GoRoute(
              path: 'categories',
              builder: (context, state) => const CategoryManagePage(),
            ),
            GoRoute(
              path: 'create',
              builder: (context, state) {
                final initialName = state.extra as String?;
                return MenuEditPage(initialName: initialName);
              },
            ),
            GoRoute(
              path: ':itemId',
              builder: (context, state) {
                final item = state.extra as menu_model.MenuItem?;
                return MenuEditPage(editItem: item);
              },
            ),
          ],
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
        // V2.2 Deal 模板管理
        GoRoute(
          path: 'templates',
          builder: (context, state) => const DealTemplatesPage(),
          routes: [
            GoRoute(
              path: 'create',
              builder: (context, state) => const DealTemplateCreatePage(),
            ),
          ],
        ),
        // 门店确认品牌 Deal（store_deal_confirm_page）
        GoRoute(
          path: 'confirm/:dealId',
          builder: (context, state) {
            final dealId = state.pathParameters['dealId']!;
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return StoreDealConfirmPage(
              dealId: dealId,
              dealTitle: extra['title'] as String? ?? '',
              dealPrice: (extra['price'] as num?)?.toDouble() ?? 0,
              brandName: extra['brand_name'] as String? ?? '',
            );
          },
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
        GoRoute(
          path: 'withdrawal',
          builder: (context, state) => const WithdrawalPage(),
        ),
      ],
    ),

    // 消息通知
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsPage(),
    ),

    // 广告投放
    GoRoute(
      path: '/promotions',
      builder: (context, state) => const PromotionsPage(),
      routes: [
        GoRoute(
          path: 'create',
          // 通过 state.extra 传入 campaignType（'splash' / 'store_booster' / 'deal_booster'）
          builder: (context, state) => CampaignCreatePage(
            campaignType: state.extra as String?,
          ),
        ),
        GoRoute(
          path: 'recharge',
          builder: (context, state) => const RechargePage(),
        ),
        GoRoute(
          path: ':id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return CampaignReportPage(campaignId: id);
          },
          routes: [
            GoRoute(
              path: 'edit',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return CampaignEditPage(campaignId: id);
              },
            ),
          ],
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

// ─── 员工账户已禁用提示页 ──────────────────────────────────────────
class _StaffDisabledPage extends StatelessWidget {
  const _StaffDisabledPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.block_outlined, size: 40, color: Colors.orange),
              ),
              const SizedBox(height: 24),
              const Text(
                'Account Disabled',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
              ),
              const SizedBox(height: 12),
              Text(
                'Your staff account has been deactivated.\nPlease contact your manager for assistance.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey[600], height: 1.5),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                    MerchantStatusCache.clear();
                    if (context.mounted) context.go('/auth/login');
                  },
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
