import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/merchant_after_sales_request.dart';
import '../providers/after_sales_providers.dart';
import 'after_sales_detail_page.dart';

class AfterSalesListPage extends ConsumerStatefulWidget {
  const AfterSalesListPage({super.key});

  @override
  ConsumerState<AfterSalesListPage> createState() => _AfterSalesListPageState();
}

class _AfterSalesListPageState extends ConsumerState<AfterSalesListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _scrollController = ScrollController();

  static const _tabs = [
    _AfterSalesTab(label: 'Action Required', filter: 'pending'),
    _AfterSalesTab(label: 'Escalated', filter: 'awaiting_platform'),
    // 商家/平台已同意退款但 Stripe 等尚未完成；避免仅 merchant_approved 时三栏都筛不到
    _AfterSalesTab(
      label: 'Refund pending',
      filter: 'merchant_approved,platform_approved',
    ),
    _AfterSalesTab(
      label: 'Closed',
      filter: 'merchant_rejected,platform_rejected,refunded,closed',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    // 与 TabBar 当前选中项对齐（默认 index 0 = Action Required）。
    // 全局 [afterSalesStatusFilterProvider] 会跨次进入页面保留；若上次停在 Closed 等 Tab，
    // 再次打开时 Tab 已回到第一项，但 filter 仍为旧值，会导致列表与 Tab 文案不一致。
    // 必须在首帧 build 之后再改 provider，否则 Riverpod 报「building 期间修改 provider」。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(afterSalesStatusFilterProvider.notifier).state =
          _tabs[_tabController.index].filter;
    });
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      final filter = _tabs[_tabController.index].filter;
      ref.read(afterSalesStatusFilterProvider.notifier).state = filter;
      ref.read(afterSalesListProvider.notifier).refresh();
    });
    _scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 120) {
      ref.read(afterSalesListProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(afterSalesListProvider);
    final isLoadingMore = ref.read(afterSalesListProvider.notifier).isLoadingMore;

    return Scaffold(
      appBar: AppBar(
        title: const Text('After-Sales Cases'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.read(afterSalesListProvider.notifier).refresh(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: const Color(0xFFFF6B35),
          labelColor: const Color(0xFFFF6B35),
          unselectedLabelColor: Colors.grey.shade500,
          tabs: _tabs.map((tab) => Tab(text: tab.label)).toList(),
        ),
      ),
      body: listAsync.when(
        data: (state) => RefreshIndicator(
          onRefresh: () => ref.read(afterSalesListProvider.notifier).refresh(),
          color: const Color(0xFFFF6B35),
          // AlwaysScrollableScrollPhysics：条目少或空列表时仍可下拉触发刷新
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (state.requests.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    statusLabel: _tabs[_tabController.index].label,
                    onReset: () =>
                        ref.read(afterSalesStatusFilterProvider.notifier).state = 'pending',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index >= state.requests.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        final request = state.requests[index];
                        return _AfterSalesCard(
                          request: request,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AfterSalesDetailPage(requestId: request.id),
                              ),
                            );
                            ref.read(afterSalesListProvider.notifier).refresh();
                          },
                        );
                      },
                      childCount: state.requests.length +
                          (state.hasMore || isLoadingMore ? 1 : 0),
                    ),
                  ),
                ),
            ],
          ),
        ),
        loading: () => RefreshIndicator(
          onRefresh: () => ref.read(afterSalesListProvider.notifier).refresh(),
          color: const Color(0xFFFF6B35),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: const _ListShimmer(),
              ),
            ],
          ),
        ),
        error: (error, _) => RefreshIndicator(
          onRefresh: () => ref.read(afterSalesListProvider.notifier).refresh(),
          color: const Color(0xFFFF6B35),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ErrorState(
                  message: error.toString(),
                  onRetry: () => ref.read(afterSalesListProvider.notifier).refresh(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AfterSalesCard extends StatelessWidget {
  const _AfterSalesCard({required this.request, required this.onTap});

  final MerchantAfterSalesRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final amountFmt = NumberFormat.simpleCurrency();
    final dateFmt = DateFormat('MMM d, HH:mm');
    final remainingLabel = _remainingText(request.remainingTime);
    final submittedLabel = request.createdAt != null
        ? dateFmt.format(request.createdAt!.toLocal())
        : '—';
    final expiresLabel = request.expiresAt != null
        ? dateFmt.format(request.expiresAt!.toLocal())
        : '—';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.userDisplayName,
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          request.reasonDetail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                        ),
                        if (request.merchantOrderContext?.orderNumber != null &&
                            request.merchantOrderContext!.orderNumber!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Order: ${request.merchantOrderContext!.orderNumber}',
                            style: textTheme.labelMedium?.copyWith(
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (request.merchantOrderContext?.dealTitle != null &&
                            request.merchantOrderContext!.dealTitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            request.merchantOrderContext!.dealTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                        if (request.merchantOrderContext?.couponCodeTail != null &&
                            request.merchantOrderContext!.couponCodeTail!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Voucher: ${request.merchantOrderContext!.couponCodeTail}',
                            style: textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _StatusPill(status: request.status),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _InfoChip(
                    icon: Icons.attach_money,
                    label: amountFmt.format(request.refundAmount),
                  ),
                  _InfoChip(
                    icon: Icons.flag_outlined,
                    label: request.reasonCode.replaceAll('_', ' '),
                  ),
                  if (request.merchantFeedback?.isNotEmpty == true)
                    const _InfoChip(
                      icon: Icons.comment_outlined,
                      label: 'Has notes',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Submitted', style: textTheme.labelSmall),
                        Text(submittedLabel, style: textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        Text('SLA deadline', style: textTheme.labelSmall),
                        Text(expiresLabel, style: textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  if (request.awaitingAction)
                    _CountdownBadge(label: remainingLabel ?? 'Expired'),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: onTap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _remainingText(Duration? remaining) {
    if (remaining == null) return null;
    if (remaining.isNegative) return 'Expired';
    if (remaining.inDays > 0) {
      return '${remaining.inDays}d ${remaining.inHours % 24}h left';
    }
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes % 60}m left';
    }
    return '${remaining.inMinutes}m left';
  }
}

class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE4DE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 16, color: Color(0xFFB42318)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFB42318),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    final bg = color.withOpacity(0.12);
    final label = status.replaceAll('_', ' ').toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFB45309);
      case 'awaiting_platform':
        return const Color(0xFF0F62FE);
      case 'merchant_approved':
      case 'platform_approved':
        return const Color(0xFF7C3AED);
      case 'merchant_rejected':
      case 'platform_rejected':
        return const Color(0xFFB42318);
      case 'refunded':
        return const Color(0xFF199473);
      default:
        return const Color(0xFF111827);
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.statusLabel, required this.onReset});

  final String statusLabel;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.support_agent_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text('No $statusLabel requests', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'After-sales cases routed to this bucket will appear here as soon as customers file them.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onReset,
              child: const Text('Return to pending'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text('Failed to load requests', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListShimmer extends StatelessWidget {
  const _ListShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 5,
      padding: const EdgeInsets.all(16),
      itemBuilder: (_, __) => Container(
        height: 120,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _AfterSalesTab {
  const _AfterSalesTab({required this.label, required this.filter});

  final String label;
  final String filter;
}
