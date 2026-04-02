// Campaign 数据报告页面
// 时间段选择：7d / 30d / All
// 汇总卡片：Total Spend / Total Clicks / CTR
// 每日趋势柱状图（CustomPaint）
// 每日明细表格

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/promotions_models.dart';
import '../providers/promotions_provider.dart';

// =============================================================
// CampaignReportPage — Campaign 报告页（ConsumerWidget）
// =============================================================
class CampaignReportPage extends ConsumerWidget {
  final String campaignId;

  const CampaignReportPage({super.key, required this.campaignId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period      = ref.watch(reportPeriodProvider);
    final reportAsync = ref.watch(campaignReportProvider(campaignId));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(context, ref),
      body: Column(
        children: [
          // 时间段选择器
          _PeriodSelector(
            selected: period,
            onChanged: (p) =>
                ref.read(reportPeriodProvider.notifier).state = p,
          ),
          // 报告内容
          Expanded(
            child: reportAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
              ),
              error: (err, _) => _ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(
                    campaignReportProvider(campaignId)),
              ),
              data: (report) => _ReportBody(report: report),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // AppBar
  // ----------------------------------------------------------
  PreferredSizeWidget _buildAppBar(BuildContext context, WidgetRef ref) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        color: const Color(0xFF1A1A2E),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text(
        'Campaign Report',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A2E),
        ),
      ),
      actions: [
        // 编辑按钮
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          color: const Color(0xFF1A1A2E),
          onPressed: () => context.push('/promotions/$campaignId/edit'),
          tooltip: 'Edit Campaign',
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// =============================================================
// _ReportBody — 报告主体（私有组件）
// =============================================================
class _ReportBody extends StatelessWidget {
  final AdCampaignReport report;

  const _ReportBody({required this.report});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFFFF6B35),
      onRefresh: () async {}, // 刷新由外部 ref.invalidate 控制
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ------------------------------------------------
            // 汇总卡片
            // ------------------------------------------------
            _SummaryCards(report: report),
            const SizedBox(height: 24),

            // ------------------------------------------------
            // 每日趋势柱状图
            // ------------------------------------------------
            _SectionTitle(title: 'Daily Trend'),
            const SizedBox(height: 12),
            report.dailyStats.isEmpty
                ? _EmptyChart()
                : _DailyBarChart(dailyStats: report.dailyStats),
            const SizedBox(height: 24),

            // ------------------------------------------------
            // 每日明细表格
            // ------------------------------------------------
            _SectionTitle(title: 'Daily Breakdown'),
            const SizedBox(height: 12),
            report.dailyStats.isEmpty
                ? _EmptyTable()
                : _DailyTable(dailyStats: report.dailyStats),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// _PeriodSelector — 时间段选择器（私有组件）
// =============================================================
class _PeriodSelector extends StatelessWidget {
  final ReportPeriod selected;
  final ValueChanged<ReportPeriod> onChanged;

  const _PeriodSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: ReportPeriod.values.map((period) {
          final isSelected = selected == period;
          final label = switch (period) {
            ReportPeriod.sevenDays  => '7 Days',
            ReportPeriod.thirtyDays => '30 Days',
            ReportPeriod.all        => 'All Time',
          };
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(period),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFF6B35)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color:
                        isSelected ? Colors.white : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// =============================================================
// _SummaryCards — 汇总指标卡片（私有组件）
// =============================================================
class _SummaryCards extends StatelessWidget {
  final AdCampaignReport report;

  const _SummaryCards({required this.report});

  @override
  Widget build(BuildContext context) {
    // 计算 CTR
    final ctr = report.totalClicks > 0 && report.totalImpressions > 0
        ? (report.totalClicks / report.totalImpressions * 100)
        : 0.0;

    return GridView.count(
      crossAxisCount: 3,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.9,
      children: [
        _MetricCard(
          label: 'Total Spend',
          value: '\$${report.totalSpend.toStringAsFixed(2)}',
          icon: Icons.payments_outlined,
          color: const Color(0xFFFF6B35),
        ),
        _MetricCard(
          label: 'Total Clicks',
          value: report.totalClicks.toString(),
          icon: Icons.ads_click_outlined,
          color: const Color(0xFF2196F3),
        ),
        _MetricCard(
          label: 'CTR',
          value: '${ctr.toStringAsFixed(1)}%',
          icon: Icons.show_chart,
          color: const Color(0xFF4CAF50),
        ),
      ],
    );
  }
}

// 单个指标卡片
class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(bottom: BorderSide(color: color, width: 3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _DailyBarChart — 每日趋势柱状图（CustomPaint）
// =============================================================
class _DailyBarChart extends StatelessWidget {
  final List<AdDailyStat> dailyStats;

  const _DailyBarChart({required this.dailyStats});

  @override
  Widget build(BuildContext context) {
    // 最多展示最近 14 天
    final data = dailyStats.length > 14
        ? dailyStats.sublist(dailyStats.length - 14)
        : dailyStats;

    if (data.isEmpty) return _EmptyChart();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图例
          Row(
            children: [
              _LegendDot(color: const Color(0xFFFF6B35), label: 'Spend'),
              const SizedBox(width: 16),
              _LegendDot(color: const Color(0xFF2196F3), label: 'Clicks'),
            ],
          ),
          const SizedBox(height: 16),
          // 柱状图
          SizedBox(
            height: 140,
            child: CustomPaint(
              size: const Size(double.infinity, 140),
              painter: _BarChartPainter(data: data),
            ),
          ),
          const SizedBox(height: 8),
          // X 轴日期标签（每隔几天显示一个）
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _buildDateLabels(data),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDateLabels(List<AdDailyStat> data) {
    final step = (data.length / 4).ceil().clamp(1, data.length);
    final labels = <Widget>[];
    for (int i = 0; i < data.length; i += step) {
      final d = data[i].date;
      labels.add(Text(
        '${d.month}/${d.day}',
        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
      ));
    }
    return labels;
  }
}

// CustomPainter 绘制双柱状图
class _BarChartPainter extends CustomPainter {
  final List<AdDailyStat> data;

  _BarChartPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // 计算最大值（用于归一化），用循环避免 fold 闭包类型推断问题
    double maxSpend  = 0.0;
    double maxClicks = 0.0;
    for (final d in data) {
      final s = (d.spend as num).toDouble();
      final c = (d.clicks as num).toDouble();
      if (s > maxSpend)  maxSpend  = s;
      if (c > maxClicks) maxClicks = c;
    }
    final maxVal = (maxSpend > maxClicks ? maxSpend : maxClicks).clamp(1.0, double.infinity);

    final barGroupWidth = size.width / data.length;
    final barWidth      = (barGroupWidth * 0.3).clamp(2.0, 12.0);
    final spendPaint    = Paint()..color = const Color(0xFFFF6B35);
    final clicksPaint   = Paint()..color = const Color(0xFF2196F3);

    for (int i = 0; i < data.length; i++) {
      final stat       = data[i];
      final groupLeft  = barGroupWidth * i + barGroupWidth * 0.1;
      final spendH     = (stat.spend / maxVal * size.height).clamp(2.0, size.height);
      final clicksH    = (stat.clicks / maxVal * size.height).clamp(
          stat.clicks > 0 ? 2.0 : 0.0, size.height);

      // 消费柱
      final spendRect = Rect.fromLTWH(
        groupLeft,
        size.height - spendH,
        barWidth,
        spendH,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(spendRect,
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3)),
        spendPaint,
      );

      // 点击数柱
      final clicksRect = Rect.fromLTWH(
        groupLeft + barWidth + 2,
        size.height - clicksH,
        barWidth,
        clicksH,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(clicksRect,
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3)),
        clicksPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// 图例点
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

// =============================================================
// _DailyTable — 每日明细表格（私有组件）
// =============================================================
class _DailyTable extends StatelessWidget {
  final List<AdDailyStat> dailyStats;

  const _DailyTable({required this.dailyStats});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 表头
          _TableHeader(),
          const Divider(height: 1),
          // 数据行
          ...dailyStats.reversed.map((stat) => _TableRow(stat: stat)),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text('Date',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade500)),
          ),
          Expanded(
            child: Text('Spend',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade500)),
          ),
          Expanded(
            child: Text('Clicks',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade500)),
          ),
          Expanded(
            child: Text('Impr.',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade500)),
          ),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final AdDailyStat stat;

  const _TableRow({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF5F5F5))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '${stat.date.year}-${stat.date.month.toString().padLeft(2, '0')}-${stat.date.day.toString().padLeft(2, '0')}',
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF1A1A2E)),
            ),
          ),
          Expanded(
            child: Text(
              '\$${stat.spend.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFF6B35),
              ),
            ),
          ),
          Expanded(
            child: Text(
              stat.clicks.toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF1A1A2E)),
            ),
          ),
          Expanded(
            child: Text(
              stat.impressions.toString(),
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// 辅助私有组件
// =============================================================

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

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

class _EmptyChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          'No data for this period',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
        ),
      ),
    );
  }
}

class _EmptyTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          'No daily records found',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
