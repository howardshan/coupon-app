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
import '../../store/widgets/store_selector.dart';
import '../../store/providers/store_provider.dart';

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
    final merchantName = dashboardAsync.valueOrNull?.stats.merchantName ?? 'My Store';
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
            // 区块 2: 快捷入口（3x2 grid）
            // ------------------------------------------------
            _SectionHeader(title: 'Quick Actions'),
            const SizedBox(height: 12),
            ShortcutGrid(
              onTap: (action) => _onShortcutTap(context, action),
            ),

            // ------------------------------------------------
            // V2.1 品牌总览入口（仅品牌管理员可见）
            // ------------------------------------------------
            const _BrandOverviewEntry(),

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
          color: const Color(0xFF2196F3), // 蓝色
        ),
        StatsCard(
          title: 'Redeemed',
          value: '${stats.todayRedemptions}',
          icon: Icons.check_circle_outline,
          color: const Color(0xFF4CAF50), // 绿色
        ),
        StatsCard(
          title: 'Revenue',
          value: _formatRevenue(stats.todayRevenue),
          icon: Icons.attach_money,
          color: const Color(0xFFFF6B35), // 品牌橙
        ),
        StatsCard(
          title: 'Pending',
          value: '${stats.pendingCoupons}',
          icon: Icons.access_time_outlined,
          color: const Color(0xFF9C27B0), // 紫色
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          // 待回复评价
          if (todos.pendingReviews > 0)
            _TodoTile(
              icon: Icons.star_outline,
              iconColor: const Color(0xFFFF9800),
              label: 'Reviews to reply',
              count: todos.pendingReviews,
              onTap: () => context.go('/reviews'),
            ),
          // 待审核退款
          if (todos.pendingRefunds > 0) ...[
            if (todos.pendingReviews > 0)
              Divider(height: 1, color: Colors.grey.shade100),
            _TodoTile(
              icon: Icons.reply_outlined,
              iconColor: const Color(0xFFF44336),
              label: 'Pending refunds',
              count: todos.pendingRefunds,
              onTap: () => context.go('/orders'),
            ),
          ],
          // Influencer 申请
          if (todos.influencerRequests > 0) ...[
            if (todos.pendingReviews > 0 || todos.pendingRefunds > 0)
              Divider(height: 1, color: Colors.grey.shade100),
            _TodoTile(
              icon: Icons.people_outline,
              iconColor: const Color(0xFF9C27B0),
              label: 'Influencer applications',
              count: todos.influencerRequests,
              onTap: () {}, // V1 暂无 influencer 路由
              isLast: true,
            ),
          ],
        ],
      ),
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
// V2.1 品牌总览入口卡片（仅品牌管理员可见）
// ============================================================
class _BrandOverviewEntry extends ConsumerWidget {
  const _BrandOverviewEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(storeProvider);
    final isBrandAdmin = storeAsync.valueOrNull?.isBrandAdmin ?? false;

    if (!isBrandAdmin) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: InkWell(
        onTap: () => context.push('/brand-overview'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6B35), Color(0xFFFF8F65)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.dashboard_customize,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Brand Overview',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 2),
                    Text('View all stores performance',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
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
