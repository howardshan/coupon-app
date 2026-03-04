// =============================================================
// AnalyticsPage — 数据分析主页面
// 布局（从上到下）:
//   1. AppBar
//   2. 时间范围切换（7 Days / 30 Days）SegmentedButton
//   3. 经营概览：4 张数据卡片（2x2 Grid）
//   4. Deal 转化漏斗区：每个 Deal 一条 FunnelBarWidget
//   5. 客群分析区（P2）：CustomerPieWidget
// =============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/analytics_data.dart';
import '../providers/analytics_provider.dart';
import '../services/analytics_service.dart';
import '../widgets/metric_card.dart';
import '../widgets/funnel_bar_widget.dart';
import '../widgets/customer_pie_widget.dart';

// =============================================================
// AnalyticsPage
// =============================================================
class AnalyticsPage extends ConsumerWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 监听时间范围状态
    final daysRange = ref.watch(daysRangeProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Analytics',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        color: const Color(0xFFFF6B35),
        onRefresh: () async {
          // 下拉刷新：重新加载所有数据
          ref.read(overviewProvider.notifier).refresh();
          ref.invalidate(dealFunnelProvider);
          ref.invalidate(customerAnalysisProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ─────────────────────────────────────────────────
            // 1. 时间范围切换按钮
            // ─────────────────────────────────────────────────
            _TimeRangeSwitcher(
              selectedDays: daysRange,
              onChanged: (days) {
                ref.read(daysRangeProvider.notifier).state = days;
              },
            ),
            const SizedBox(height: 20),

            // ─────────────────────────────────────────────────
            // 2. 经营概览区域
            // ─────────────────────────────────────────────────
            _SectionHeader(
              title: 'Business Overview',
              subtitle: 'Last $daysRange days',
            ),
            const SizedBox(height: 12),
            _OverviewSection(daysRange: daysRange),
            const SizedBox(height: 24),

            // ─────────────────────────────────────────────────
            // 3. Deal 转化漏斗区域
            // ─────────────────────────────────────────────────
            const _SectionHeader(
              title: 'Deal Performance',
              subtitle: 'Views → Orders → Redemptions',
            ),
            const SizedBox(height: 12),
            const _DealFunnelSection(),
            const SizedBox(height: 24),

            // ─────────────────────────────────────────────────
            // 4. 客群分析区域（P2）
            // ─────────────────────────────────────────────────
            const _SectionHeader(
              title: 'Customer Insights',
              subtitle: 'New vs. returning customers',
            ),
            const SizedBox(height: 12),
            const _CustomerSection(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// _TimeRangeSwitcher — 7天 / 30天 切换按钮
// =============================================================
class _TimeRangeSwitcher extends StatelessWidget {
  final int selectedDays;
  final ValueChanged<int> onChanged;

  const _TimeRangeSwitcher({
    required this.selectedDays,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment<int>(
          value: 7,
          label: Text('7 Days'),
          icon: Icon(Icons.calendar_view_week, size: 16),
        ),
        ButtonSegment<int>(
          value: 30,
          label: Text('30 Days'),
          icon: Icon(Icons.calendar_month, size: 16),
        ),
      ],
      selected: {selectedDays},
      onSelectionChanged: (selected) {
        if (selected.isNotEmpty) onChanged(selected.first);
      },
      style: ButtonStyle(
        // 选中态：橙色填充
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFFFF6B35);
          }
          return Colors.white;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return const Color(0xFF666666);
        }),
      ),
    );
  }
}

// =============================================================
// _SectionHeader — 区域标题行
// =============================================================
class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
      ],
    );
  }
}

// =============================================================
// _OverviewSection — 经营概览 4 张卡片区域
// =============================================================
class _OverviewSection extends ConsumerWidget {
  final int daysRange;

  const _OverviewSection({required this.daysRange});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(overviewProvider);

    return overviewAsync.when(
      // 加载中：骨架屏
      loading: () => _buildSkeleton(),

      // 错误：重试按钮
      error: (err, _) => _buildError(
        message: err is AnalyticsException
            ? err.message
            : 'Failed to load data. Please try again.',
        onRetry: () => ref.read(overviewProvider.notifier).refresh(),
      ),

      // 成功：4 张卡片
      data: (stats) => _buildCards(stats),
    );
  }

  /// 格式化收入：$1,234.56
  String _formatRevenue(double amount) {
    final formatter = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    return formatter.format(amount);
  }

  /// 格式化数量：1,234
  String _formatCount(int count) {
    final formatter = NumberFormat('#,###');
    return formatter.format(count);
  }

  Widget _buildCards(OverviewStats stats) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        MetricCard(
          icon:  Icons.visibility_outlined,
          value: _formatCount(stats.viewsCount),
          label: 'Views',
          color: const Color(0xFF2196F3),
        ),
        MetricCard(
          icon:  Icons.shopping_bag_outlined,
          value: _formatCount(stats.ordersCount),
          label: 'Orders',
          color: const Color(0xFF9C27B0),
        ),
        MetricCard(
          icon:  Icons.qr_code_scanner,
          value: _formatCount(stats.redemptionsCount),
          label: 'Redemptions',
          color: const Color(0xFF4CAF50),
        ),
        MetricCard(
          icon:  Icons.attach_money,
          value: _formatRevenue(stats.revenue),
          label: 'Revenue',
          color: const Color(0xFFFF6B35),
        ),
      ],
    );
  }

  /// 骨架屏（4 个灰色占位卡片）
  Widget _buildSkeleton() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: List.generate(4, (_) => _SkeletonCard()),
    );
  }

  Widget _buildError({required String message, required VoidCallback onRetry}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.red[400], size: 36),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF6B35),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _DealFunnelSection — Deal 转化漏斗列表区域
// =============================================================
class _DealFunnelSection extends ConsumerWidget {
  const _DealFunnelSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final funnelAsync = ref.watch(dealFunnelProvider);

    return funnelAsync.when(
      loading: () => Column(
        children: List.generate(2, (_) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SkeletonCard(height: 110),
        )),
      ),

      error: (err, _) => _buildError(
        message: 'Failed to load deal performance.',
        onRetry: () => ref.invalidate(dealFunnelProvider),
      ),

      data: (funnels) {
        if (funnels.isEmpty) {
          return _buildEmpty(
            icon:    Icons.bar_chart_outlined,
            message: 'No deals found.\nCreate your first deal to see performance data.',
          );
        }
        return Column(
          children: funnels.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FunnelBarWidget(data: f),
          )).toList(),
        );
      },
    );
  }

  Widget _buildEmpty({required IconData icon, required String message}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildError({required String message, required VoidCallback onRetry}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.red[400], size: 32),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF6B35),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _CustomerSection — 客群分析区域（P2）
// =============================================================
class _CustomerSection extends ConsumerWidget {
  const _CustomerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerAnalysisProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: customerAsync.when(
        loading: () => const SizedBox(
          height: 100,
          child: Center(
            child: CircularProgressIndicator(
              color: Color(0xFFFF6B35),
              strokeWidth: 2,
            ),
          ),
        ),

        error: (err, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red[400], size: 28),
            const SizedBox(height: 8),
            Text(
              'Failed to load customer data.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            TextButton.icon(
              onPressed: () => ref.invalidate(customerAnalysisProvider),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF6B35),
              ),
            ),
          ],
        ),

        data: (analysis) => CustomerPieWidget(data: analysis),
      ),
    );
  }
}

// =============================================================
// _SkeletonCard — 加载中骨架占位卡片
// =============================================================
class _SkeletonCard extends StatelessWidget {
  final double height;

  const _SkeletonCard({this.height = 80});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        // 浅灰色模拟骨架屏
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
