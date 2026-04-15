// 商家工作台主页面
// 包含: 欢迎语 + 在线状态 Switch / 4张数据卡片 / 6格快捷入口 /
//       待办提醒区块（P1）/ 近7天趋势列表（P1）

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/dashboard_stats.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/stats_card.dart';
import '../widgets/shortcut_grid.dart';
import '../../after_sales/pages/after_sales_list_page.dart';
import '../../orders/pages/refund_requests_page.dart';
import '../../store/widgets/store_selector.dart';
import '../../store/providers/store_provider.dart';
import '../../deals/providers/deals_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 直接查 brand_admins 表判断是否品牌管理员（不依赖 storeProvider）
final _isBrandAdminDirectProvider = FutureProvider<bool>((ref) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return false;
  try {
    final res = await client
        .from('brand_admins')
        .select('id')
        .eq('user_id', userId)
        .limit(1);
    return (res as List).isNotEmpty;
  } catch (e) {
    debugPrint('[_isBrandAdminDirectProvider] 查询失败: $e');
    return false;
  }
});

// ============================================================
// DashboardPage — 工作台主页（ConsumerWidget）
// ============================================================
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 监听工作台数据
    final dashboardAsync = ref.watch(dashboardProvider);
    // 监听门店在线状态（独立 Provider，乐观更新）
    final isOnline = ref.watch(storeOnlineProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(context, ref, dashboardAsync, isOnline),
      body: dashboardAsync.when(
        // 加载中：显示骨架屏
        loading: () => _buildLoadingBody(),
        // 错误：显示重试按钮
        error: (err, _) => _buildErrorBody(context, ref, err),
        // 数据正常：显示完整工作台
        data: (data) => _buildDataBody(context, ref, data),
      ),
    );
  }

  // ----------------------------------------------------------
  // AppBar：欢迎文案 + 门店名 + 在线状态开关
  // ----------------------------------------------------------
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<DashboardData> dashboardAsync,
    bool isOnline,
  ) {
    // 优先从 storeProvider 读门店名（准确），降级用 dashboard API 的名字
    final storeName = ref.watch(storeProvider).valueOrNull?.name;
    final merchantName = (storeName != null && storeName.isNotEmpty)
        ? storeName
        : (dashboardAsync.valueOrNull?.stats.merchantName ?? 'My Store');
    final isToggling = ref.watch(dashboardProvider).isLoading;

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 20,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Good ${_greeting()}, 👋',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w400,
            ),
          ),
          Text(
            merchantName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
      // 右侧：门店切换（品牌管理员）+ 在线/下线开关
      actions: [
        // 品牌管理员门店切换器
        const StoreSelector(),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 状态文字标签
              Text(
                isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isOnline
                      ? const Color(0xFF4CAF50)
                      : Colors.grey.shade500,
                ),
              ),
              const SizedBox(width: 8),
              // 切换开关（切换中禁用，防止重复点击）
              AbsorbPointer(
                absorbing: isToggling,
                child: Switch.adaptive(
                  value: isOnline,
                  activeThumbColor: Colors.white,
                  activeTrackColor: const Color(0xFF4CAF50),
                  onChanged: (value) => _handleToggleOnline(context, ref, value),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // 处理在线状态切换
  // ----------------------------------------------------------
  Future<void> _handleToggleOnline(
    BuildContext context,
    WidgetRef ref,
    bool newValue,
  ) async {
    try {
      await ref.read(dashboardProvider.notifier).toggleOnlineStatus(newValue);
      if (!context.mounted) return;
      // 成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newValue ? 'Store is now online' : 'Store is now offline',
          ),
          backgroundColor: newValue
              ? const Color(0xFF4CAF50)
              : Colors.grey.shade700,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      // 失败提示（乐观更新已回滚）
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to update store status. Please try again.'),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  // ----------------------------------------------------------
  // 正常数据 Body（含 pull-to-refresh）
  // ----------------------------------------------------------
  Widget _buildDataBody(
    BuildContext context,
    WidgetRef ref,
    DashboardData data,
  ) {
    return RefreshIndicator(
      color: const Color(0xFFFF6B35),
      onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ------------------------------------------------
            // 区块 1: 今日数据卡片（2x2 grid）
            // ------------------------------------------------
            _SectionHeader(title: "Today's Stats"),
            const SizedBox(height: 12),
            _StatsSection(stats: data.stats),

            const SizedBox(height: 24),

            // ------------------------------------------------
            // 区块 1.5: 待确认品牌 Deal 横幅（有待确认时才显示）
            // ------------------------------------------------
            _PendingBrandDealsBanner(ref: ref),

            // ------------------------------------------------
            // 区块 2: 快捷入口（3x2 grid）
            // ------------------------------------------------
            _SectionHeader(title: 'Quick Actions'),
            const SizedBox(height: 12),
            ShortcutGrid(
              onTap: (action) => _onShortcutTap(context, action),
              // 同时检查 storeProvider 和直接查 brand_admins 表
              isBrandAdmin: ref.watch(storeProvider).valueOrNull?.isBrandAdmin ??
                  ref.watch(_isBrandAdminDirectProvider).valueOrNull ??
                  false,
            ),

            // ------------------------------------------------
            // 区块 2.5: Earnings 快速入口（仅 store_owner 可见）
            // ------------------------------------------------
            // storeProvider 未加载时 currentRole 为 null，默认视为 store_owner 显示
            if (const {'store_owner', 'brand_owner', ''}.contains(
                ref.watch(storeProvider).valueOrNull?.currentRole ?? '')) ...[
              const SizedBox(height: 16),
              _EarningsShortcutCard(onTap: () => context.push('/earnings')),
            ],

            // ------------------------------------------------
            // 区块 3: 待办提醒（P1 — 有待办时才显示）
            // ------------------------------------------------
            if (data.todos.hasAnyTodos) ...[
              const SizedBox(height: 24),
              _SectionHeader(title: 'Action Required'),
              const SizedBox(height: 12),
              _TodoSection(todos: data.todos, context: context),
            ],

            // ------------------------------------------------
            // 区块 4: 近 7 天趋势（P1 — 文字列表 V1）
            // ------------------------------------------------
            const SizedBox(height: 24),
            _SectionHeader(title: '7-Day Trend'),
            const SizedBox(height: 12),
            _TrendSection(trend: data.weeklyTrend),

            // 底部安全区域
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // 骨架屏（加载中）
  // ----------------------------------------------------------
  Widget _buildLoadingBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: "Today's Stats"),
          const SizedBox(height: 12),
          // 4个骨架卡片
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.15,
            children: List.generate(
              4,
              (_) => const StatsCard(
                title: '',
                value: '',
                icon: Icons.circle,
                color: Colors.transparent,
                isLoading: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // 错误状态
  // ----------------------------------------------------------
  Widget _buildErrorBody(BuildContext context, WidgetRef ref, Object err) {
    final errMsg = err.toString();
    final isMerchantNotFound = errMsg.contains('Merchant profile not found');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isMerchantNotFound ? Icons.store_outlined : Icons.cloud_off_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              isMerchantNotFound ? 'No merchant account found' : 'Failed to load dashboard',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              isMerchantNotFound
                  ? 'Your account is not linked to a merchant profile. Please complete your registration.'
                  : errMsg.replaceFirst('DashboardException: ', ''),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
            const SizedBox(height: 24),
            if (isMerchantNotFound) ...[
              ElevatedButton.icon(
                onPressed: () => context.go('/auth/register'),
                icon: const Icon(Icons.app_registration),
                label: const Text('Register as Merchant'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: () => ref.read(dashboardProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // 快捷入口点击路由
  // ----------------------------------------------------------
  void _onShortcutTap(BuildContext context, ShortcutAction action) {
    switch (action) {
      case ShortcutAction.redeem:
        context.go('/scan');
      case ShortcutAction.deals:
        context.push('/deals');
      case ShortcutAction.orders:
        context.go('/orders');
      case ShortcutAction.reviews:
        context.push('/reviews');
      case ShortcutAction.analytics:
        context.push('/analytics');
      case ShortcutAction.store:
        context.push('/store');
      case ShortcutAction.menu:
        context.push('/store/menu');
      case ShortcutAction.brand:
        context.push('/brand-manage');
    }
  }

  // ----------------------------------------------------------
  // 问候语（根据时段）
  // ----------------------------------------------------------
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }
}

// ============================================================
// _SectionHeader — 区块标题
// ============================================================
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A1A2E),
      ),
    );
  }
}

// ============================================================
// _StatsSection — 今日数据 2x2 卡片网格
// ============================================================
class _StatsSection extends StatelessWidget {
  final DashboardStats stats;

  const _StatsSection({required this.stats});

  // 格式化收入（美元）
  String _formatRevenue(double amount) {
    return '\$${amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.15,
      children: [
        StatsCard(
          title: 'Today Orders',
          value: '${stats.todayOrders}',
          icon: Icons.shopping_bag_outlined,
          color: const Color(0xFF2196F3),
          onTap: () => context.push('/orders'),
        ),
        StatsCard(
          title: 'Redeemed',
          value: '${stats.todayRedemptions}',
          icon: Icons.check_circle_outline,
          color: const Color(0xFF4CAF50),
          // Tab 顺序见 OrdersListPage._tabs: 0 All, 1 Unused, 2 Redeemed, 3 Settled, 4 Refunded
          onTap: () => context.push('/orders?tab=2'),
        ),
        StatsCard(
          title: 'Revenue',
          value: _formatRevenue(stats.todayRevenue),
          icon: Icons.attach_money,
          color: const Color(0xFFFF6B35),
          onTap: () => context.push('/earnings'),
        ),
        StatsCard(
          title: 'Unused',
          value: '${stats.pendingCoupons}',
          icon: Icons.access_time_outlined,
          color: const Color(0xFF9C27B0),
          onTap: () => context.push('/orders?tab=1'),
        ),
      ],
    );
  }
}

// ============================================================
// _TodoSection — 待办提醒区块（P1）
// ============================================================
class _TodoSection extends StatelessWidget {
  final TodoCounts todos;
  final BuildContext context;

  const _TodoSection({required this.todos, required this.context});

  @override
  Widget build(BuildContext _) {
    void pushRefundRequests() {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const RefundRequestsPage(),
        ),
      );
    }

    void pushAfterSalesList() {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const AfterSalesListPage(),
        ),
      );
    }

    // 与订单页一致：历史争议退款 vs 售后工单（新单仅售后）
    final specs =
        <({
          IconData icon,
          Color iconColor,
          String label,
          int count,
          VoidCallback onTap,
        })>[];

    if (todos.pendingReviews > 0) {
      specs.add((
        icon: Icons.star_outline,
        iconColor: const Color(0xFFFF9800),
        label: 'Reviews to reply',
        count: todos.pendingReviews,
        onTap: () => context.go('/reviews'),
      ));
    }
    if (todos.pendingRefunds > 0) {
      specs.add((
        icon: Icons.reply_outlined,
        iconColor: const Color(0xFFF44336),
        label: 'Refund requests',
        count: todos.pendingRefunds,
        onTap: pushRefundRequests,
      ));
    }
    if (todos.pendingAfterSales > 0) {
      specs.add((
        icon: Icons.support_agent_outlined,
        iconColor: const Color(0xFF00897B),
        label: 'After-sales pending',
        count: todos.pendingAfterSales,
        onTap: pushAfterSalesList,
      ));
    }
    if (todos.influencerRequests > 0) {
      specs.add((
        icon: Icons.people_outline,
        iconColor: const Color(0xFF9C27B0),
        label: 'Influencer applications',
        count: todos.influencerRequests,
        onTap: () {}, // V1 暂无 influencer 路由
      ));
    }

    final children = <Widget>[];
    for (var i = 0; i < specs.length; i++) {
      final s = specs[i];
      if (i > 0) {
        children.add(Divider(height: 1, color: Colors.grey.shade100));
      }
      children.add(
        _TodoTile(
          icon: s.icon,
          iconColor: s.iconColor,
          label: s.label,
          count: s.count,
          onTap: s.onTap,
          isLast: i == specs.length - 1,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(children: children),
    );
  }
}

// 单条待办 tile
class _TodoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final int count;
  final VoidCallback onTap;
  final bool isLast;

  const _TodoTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.count,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: isLast
          ? const BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            )
          : BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 图标
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 12),
            // 标签
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ),
            // 数量徽章（红色）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF44336),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// _TrendSection — 近 7 天趋势文字列表（P1 V1 实现）
// ============================================================
class _TrendSection extends StatelessWidget {
  final List<WeeklyTrendEntry> trend;

  const _TrendSection({required this.trend});

  @override
  Widget build(BuildContext context) {
    if (trend.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Center(
          child: Text(
            'No trend data available',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          // 表头
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Date',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Orders',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Revenue',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade100),
          // 数据行列表
          ...trend.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final isLast = i == trend.length - 1;
            return Column(
              children: [
                _TrendRow(entry: item),
                if (!isLast) Divider(height: 1, color: Colors.grey.shade50),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ============================================================
// _PendingBrandDealsBanner — 待确认品牌 Deal 橙色提示横幅
// 查询当前门店在 deal_applicable_stores 中 pending_store_confirmation 的记录
// ============================================================
class _PendingBrandDealsBanner extends ConsumerWidget {
  final WidgetRef ref;

  const _PendingBrandDealsBanner({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final pendingAsync = widgetRef.watch(pendingStoreDealsProvider);

    return pendingAsync.when(
      // 加载中不显示任何内容
      loading: () => const SizedBox.shrink(),
      // 出错不显示（静默失败，不影响主界面）
      error: (_, _) => const SizedBox.shrink(),
      data: (deals) {
        if (deals.isEmpty) return const SizedBox.shrink();

        final count = deals.length;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GestureDetector(
            onTap: () => _showPendingDealsSheet(context, deals),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFF6B35)),
              ),
              child: Row(
                children: [
                  // 通知图标
                  const Icon(
                    Icons.notifications_active_outlined,
                    size: 20,
                    color: Color(0xFFFF6B35),
                  ),
                  const SizedBox(width: 10),
                  // 提示文字
                  Expanded(
                    child: Text(
                      'You have $count pending brand deal${count > 1 ? 's' : ''} to confirm',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE64A00),
                      ),
                    ),
                  ),
                  // 箭头
                  const Text(
                    'Tap to view →',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFFF6B35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ----------------------------------------------------------
  // 展示待确认 Deal 列表 BottomSheet
  // ----------------------------------------------------------
  void _showPendingDealsSheet(
    BuildContext context,
    List<Map<String, dynamic>> deals,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, scrollController) => Column(
          children: [
            // 拖动手柄
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    size: 18,
                    color: Color(0xFFFF6B35),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Pending Brand Deals',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Deal 列表
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: deals.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (_, index) {
                  final row = deals[index];
                  final dealId = row['deal_id'] as String? ?? '';

                  // 解析嵌套的 deals join 结果
                  final dealData = row['deals'] as Map<String, dynamic>? ?? {};
                  final title = dealData['title'] as String? ?? 'Untitled Deal';
                  final price =
                      (dealData['discount_price'] as num?)?.toDouble() ?? 0.0;

                  // 解析品牌名称（双重嵌套）
                  final merchantData =
                      dealData['merchants'] as Map<String, dynamic>? ?? {};
                  final brandName =
                      merchantData['name'] as String? ?? 'Brand';

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.local_offer_outlined,
                        size: 20,
                        color: Color(0xFFFF6B35),
                      ),
                    ),
                    title: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '$brandName · \$${price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF666666),
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Color(0xFFFF6B35),
                    ),
                    onTap: () {
                      // 关闭 BottomSheet 后跳转到确认页
                      Navigator.of(ctx).pop();
                      context.push(
                        '/deals/confirm/$dealId',
                        extra: {
                          'title': title,
                          'price': price,
                          'brand_name': brandName,
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// _EarningsShortcutCard — Earnings 快速入口卡片（仅 owner 可见）
// ============================================================
class _EarningsShortcutCard extends StatelessWidget {
  final VoidCallback onTap;

  const _EarningsShortcutCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(6),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            // 左侧图标
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withAlpha(26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                size: 20,
                color: Color(0xFF4CAF50),
              ),
            ),
            const SizedBox(width: 14),
            // 中间文字
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Earnings & Settlement',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'View revenue, transactions & payouts',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF999999),
                    ),
                  ),
                ],
              ),
            ),
            // 右箭头
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// 单行趋势数据
class _TrendRow extends StatelessWidget {
  final WeeklyTrendEntry entry;

  const _TrendRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final dateLabel = entry.isToday
        ? 'Today'
        : DateFormat('MMM d').format(entry.date); // 如 "Mar 1"

    return Container(
      // 今日行用浅橙色高亮
      color: entry.isToday
          ? const Color(0xFFFF6B35).withAlpha(13) // ~5%
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // 日期列
          Expanded(
            flex: 3,
            child: Text(
              dateLabel,
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    entry.isToday ? FontWeight.w700 : FontWeight.w400,
                color: entry.isToday
                    ? const Color(0xFFFF6B35)
                    : const Color(0xFF1A1A2E),
              ),
            ),
          ),
          // 订单数列
          Expanded(
            child: Text(
              '${entry.orders}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    entry.isToday ? FontWeight.w700 : FontWeight.w400,
                color: entry.isToday
                    ? const Color(0xFFFF6B35)
                    : const Color(0xFF1A1A2E),
              ),
            ),
          ),
          // 收入列
          Expanded(
            flex: 2,
            child: Text(
              '\$${entry.revenue.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    entry.isToday ? FontWeight.w700 : FontWeight.w400,
                color: entry.isToday
                    ? const Color(0xFFFF6B35)
                    : const Color(0xFF1A1A2E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
