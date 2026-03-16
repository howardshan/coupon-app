// 订单列表页面
// 顶部 4-Tab: All / Paid / Redeemed / Refunded
// 筛选行: OrderFilterBar（日期范围 + Deal 筛选）
// 列表: OrderTile 卡片，支持下拉刷新 + 上拉加载更多
// 右上角: 导出 CSV 按钮（P2）

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/merchant_order.dart';
import '../providers/orders_provider.dart';
import '../widgets/order_filter_bar.dart';
import '../widgets/order_tile.dart';
import 'order_detail_page.dart';
import 'admin_refund_requests_page.dart';
import 'refund_requests_page.dart';

/// 订单列表主页
class OrdersListPage extends ConsumerStatefulWidget {
  const OrdersListPage({super.key});

  @override
  ConsumerState<OrdersListPage> createState() => _OrdersListPageState();
}

class _OrdersListPageState extends ConsumerState<OrdersListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Tab 配置（null = All）
  static const List<OrderStatus?> _tabs = [
    null,
    OrderStatus.paid,
    OrderStatus.redeemed,
    OrderStatus.refunded,
  ];

  // 滚动控制器（用于检测上拉加载更多）
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);

    // Tab 切换时更新 filter 的 status
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      final newStatus = _tabs[_tabController.index];
      ref.read(orderFilterProvider.notifier).update(
            (f) => f.copyWith(
              status: newStatus,
              clearStatus: newStatus == null,
            ),
          );
    });

    // 滚动到底部时触发加载更多
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(ordersNotifierProvider.notifier).loadMore();
    }
  }

  // 导出 CSV
  Future<void> _exportCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    final csvContent =
        await ref.read(orderExportProvider.notifier).export();

    if (!mounted) return;

    if (csvContent == null || csvContent.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Export failed. Please try again.'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // V1 简单实现：显示成功提示
    // TODO: 接入 share_plus 包实现文件分享
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'CSV ready — ${csvContent.split('\n').length - 1} orders exported.',
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
    ref.read(orderExportProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersNotifierProvider);
    final notifier = ref.read(ordersNotifierProvider.notifier);
    final exportAsync = ref.watch(orderExportProvider);
    final isExporting = exportAsync.isLoading;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Orders',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
          ),
        ),
        centerTitle: false,
        actions: [
          // 退款申请审批入口（商家审核用户的核销后退款申请）
          IconButton(
            icon: const Icon(Icons.policy_outlined),
            tooltip: 'Refund Requests',
            onPressed: () async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => const RefundRequestsPage(),
                ),
              );
            },
          ),
          // 管理员仲裁入口按钮
          IconButton(
            icon: const Icon(Icons.admin_panel_settings_outlined),
            tooltip: 'Admin Arbitration',
            onPressed: () async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminRefundRequestsPage(),
                ),
              );
            },
          ),
          // 导出按钮（P2）
          IconButton(
            onPressed: isExporting ? null : _exportCsv,
            tooltip: 'Export CSV',
            icon: isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFF6B35),
                    ),
                  )
                : const Icon(
                    Icons.download_outlined,
                    color: Color(0xFF1A1A1A),
                  ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFFF6B35),
            indicatorWeight: 2.5,
            labelColor: const Color(0xFFFF6B35),
            unselectedLabelColor: Colors.grey.shade500,
            labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            tabs: _tabs.map((s) {
              return Tab(text: OrderStatus.tabLabel(s));
            }).toList(),
          ),
        ),
      ),

      body: Column(
        children: [
          // 筛选行
          const OrderFilterBar(),
          Divider(color: Colors.grey.shade100, height: 1),

          // 订单列表
          Expanded(
            child: ordersAsync.when(
              data: (orders) => _buildList(orders, notifier),
              loading: () => _buildShimmer(),
              error: (e, _) => _buildError(e, notifier),
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // 订单列表
  // =============================================================
  Widget _buildList(
      List<MerchantOrder> orders, OrdersNotifier notifier) {
    if (orders.isEmpty) {
      return _buildEmpty();
    }

    return RefreshIndicator(
      color: const Color(0xFFFF6B35),
      onRefresh: notifier.refresh,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: orders.length + (notifier.hasMore ? 1 : 0),
        itemBuilder: (ctx, index) {
          // 底部加载更多指示器
          if (index == orders.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFFF6B35),
                  ),
                ),
              ),
            );
          }

          final order = orders[index];
          return OrderTile(
            order: order,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OrderDetailPage(orderId: order.id),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // =============================================================
  // 空状态
  // =============================================================
  Widget _buildEmpty() {
    final filter = ref.read(orderFilterProvider);
    final hasFilter = filter.hasExtraFilter || filter.status != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilter
                  ? Icons.filter_list_off_rounded
                  : Icons.receipt_long_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              hasFilter ? 'No matching orders' : 'No orders yet',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? 'Try adjusting your filters.'
                  : 'Orders will appear here once\ncustomers purchase your deals.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
            if (hasFilter) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () {
                  ref
                      .read(orderFilterProvider.notifier)
                      .update((f) => f.clearExtra());
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6B35),
                  side: const BorderSide(color: Color(0xFFFF6B35)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Clear Filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =============================================================
  // 错误状态
  // =============================================================
  Widget _buildError(Object error, OrdersNotifier notifier) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 56,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to load orders',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString().contains('network')
                  ? 'Please check your connection.'
                  : 'Something went wrong. Please try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: notifier.refresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =============================================================
  // Skeleton 加载状态（shimmer 效果）
  // =============================================================
  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: 6,
      itemBuilder: (ctx, index) {
        return _ShimmerOrderTile();
      },
    );
  }
}

// =============================================================
// Skeleton 占位卡片（无 shimmer 包依赖，使用动画渐变）
// =============================================================
class _ShimmerOrderTile extends StatefulWidget {
  @override
  State<_ShimmerOrderTile> createState() => _ShimmerOrderTileState();
}

class _ShimmerOrderTileState extends State<_ShimmerOrderTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (ctx, child) {
        return Opacity(
          opacity: _animation.value,
          child: child,
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Block(width: 120, height: 14),
                const Spacer(),
                _Block(width: 70, height: 22, radius: 20),
              ],
            ),
            const SizedBox(height: 10),
            _Block(width: double.infinity, height: 16),
            const SizedBox(height: 8),
            _Block(width: 100, height: 13),
            const SizedBox(height: 12),
            Row(
              children: [
                _Block(width: 130, height: 12),
                const Spacer(),
                _Block(width: 60, height: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.width,
    required this.height,
    this.radius = 6,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// 扩展：添加 tabLabel 静态方法
extension OrderStatusTabLabel on OrderStatus {
  static String label(OrderStatus? status) => OrderStatus.tabLabel(status);
}

// NumberFormat 需要 intl 包（已在 pubspec.yaml 中声明）
// 此处仅做格式化使用
final _amountFmt = NumberFormat.currency(symbol: '\$');
String formatAmount(double amount) => _amountFmt.format(amount);
