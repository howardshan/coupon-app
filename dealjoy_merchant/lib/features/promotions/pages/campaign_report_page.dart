// Campaign 详情 + 报告页
// 顶部：配置信息（广告位、目标、出价、预算、日期、时段）
// 中部：今日实时统计 + Pause / Resume / Delete 操作
// 底部：时间段选择 + 历史报告（消费/点击/趋势图/每日明细）

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/promotions_models.dart';
import '../providers/promotions_provider.dart';

// =============================================================
// CampaignReportPage — Campaign 详情 + 报告页
// =============================================================
class CampaignReportPage extends ConsumerStatefulWidget {
  final String campaignId;

  const CampaignReportPage({super.key, required this.campaignId});

  @override
  ConsumerState<CampaignReportPage> createState() =>
      _CampaignReportPageState();
}

class _CampaignReportPageState extends ConsumerState<CampaignReportPage> {
  bool _isActionProcessing = false;

  // ----------------------------------------------------------
  // 操作：暂停 / 恢复 / 删除
  // ----------------------------------------------------------
  Future<void> _pause() async {
    setState(() => _isActionProcessing = true);
    try {
      await ref
          .read(campaignsProvider.notifier)
          .pauseCampaign(widget.campaignId);
    } catch (e) {
      _showError('Failed to pause: $e');
    } finally {
      if (mounted) setState(() => _isActionProcessing = false);
    }
  }

  Future<void> _resume() async {
    setState(() => _isActionProcessing = true);
    try {
      await ref
          .read(campaignsProvider.notifier)
          .resumeCampaign(widget.campaignId);
    } catch (e) {
      _showError('Failed to resume: $e');
    } finally {
      if (mounted) setState(() => _isActionProcessing = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Campaign'),
        content: const Text(
            'This campaign and all its data will be permanently deleted. '
            'Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isActionProcessing = true);
    try {
      await ref
          .read(campaignsProvider.notifier)
          .deleteCampaign(widget.campaignId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _showError('Failed to delete: $e');
      if (mounted) setState(() => _isActionProcessing = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 从缓存列表中查找当前 campaign
    final campaigns = ref.watch(campaignsProvider).valueOrNull ?? [];
    AdCampaign? campaign;
    for (final c in campaigns) {
      if (c.id == widget.campaignId) {
        campaign = c;
        break;
      }
    }

    final period      = ref.watch(reportPeriodProvider);
    final reportAsync = ref.watch(campaignReportProvider(widget.campaignId));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ------------------------------------------------
                  // Campaign 配置信息卡片
                  // ------------------------------------------------
                  if (campaign != null)
                    _CampaignInfoCard(campaign: campaign),

                  // ------------------------------------------------
                  // 今日实时统计
                  // ------------------------------------------------
                  if (campaign != null) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _TodayStatsRow(campaign: campaign),
                    ),
                  ],

                  // ------------------------------------------------
                  // 操作按钮：Pause / Resume + Delete
                  // ------------------------------------------------
                  if (campaign != null &&
                      campaign.status != CampaignStatus.adminPaused &&
                      campaign.status != CampaignStatus.ended) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ActionRow(
                        campaign: campaign,
                        isProcessing: _isActionProcessing,
                        onPause: _pause,
                        onResume: _resume,
                        onDelete: _delete,
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  const Divider(height: 1, color: Color(0xFFE0E0E0)),

                  // ------------------------------------------------
                  // 时间段选择器
                  // ------------------------------------------------
                  _PeriodSelector(
                    selected: period,
                    onChanged: (p) =>
                        ref.read(reportPeriodProvider.notifier).state = p,
                  ),

                  // ------------------------------------------------
                  // 报告数据区
                  // ------------------------------------------------
                  reportAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFFFF6B35)),
                      ),
                    ),
                    error: (err, _) => _ErrorView(
                      message: err.toString(),
                      onRetry: () => ref.invalidate(
                          campaignReportProvider(widget.campaignId)),
                    ),
                    data: (report) => _ReportBody(report: report),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
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
        'Campaign Detail',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A2E),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          color: const Color(0xFF1A1A2E),
          onPressed: () =>
              context.push('/promotions/${widget.campaignId}/edit'),
          tooltip: 'Edit Campaign',
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// =============================================================
// _CampaignInfoCard — 广告配置信息卡片
// =============================================================
class _CampaignInfoCard extends StatelessWidget {
  final AdCampaign campaign;

  const _CampaignInfoCard({required this.campaign});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
          // 广告位 + 状态
          Row(
            children: [
              _PlacementIcon(placement: campaign.placement),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  campaign.placementDisplayName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
              _StatusBadge(status: campaign.status),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 14),

          // 目标类型 + ID
          _InfoRow(
            icon: campaign.targetType == TargetType.deal
                ? Icons.local_offer_outlined
                : Icons.store_outlined,
            label: 'Target',
            value:
                '${campaign.targetType == TargetType.deal ? "Deal" : "Store"}  •  ${campaign.targetId.length > 12 ? campaign.targetId.substring(0, 12) + "..." : campaign.targetId}',
          ),
          const SizedBox(height: 10),

          // 出价 + 日预算
          _InfoRow(
            icon: Icons.payments_outlined,
            label: 'Bid / Budget',
            value:
                '\$${campaign.bidPrice.toStringAsFixed(2)}/click  ·  \$${campaign.dailyBudget.toStringAsFixed(2)}/day',
          ),
          const SizedBox(height: 10),

          // 投放日期
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Date',
            value: _formatDateRange(campaign.startAt, campaign.endAt),
          ),
          const SizedBox(height: 10),

          // 投放时段
          _InfoRow(
            icon: Icons.access_time_outlined,
            label: 'Schedule',
            value: _formatSchedule(campaign.scheduleHours),
          ),

          // Admin 暂停备注
          if (campaign.status == CampaignStatus.adminPaused &&
              campaign.adminNote != null &&
              campaign.adminNote!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: Color(0xFFE53935)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      campaign.adminNote!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFE53935),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Exhausted 提示
          if (campaign.status == CampaignStatus.exhausted) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 14, color: Color(0xFFE65100)),
                  SizedBox(width: 6),
                  Text(
                    'Daily budget exhausted — recharge to resume',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFE65100),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDateRange(DateTime start, DateTime? end) {
    final s = _fmtDate(start);
    if (end == null) return '$s  →  No end date';
    return '$s  →  ${_fmtDate(end)}';
  }

  String _fmtDate(DateTime d) =>
      '${_monthAbbr(d.month)} ${d.day}, ${d.year}';

  String _monthAbbr(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];

  String _formatSchedule(List<int>? hours) {
    if (hours == null || hours.isEmpty) return 'All day';
    final sorted = [...hours]..sort();
    if (sorted.length >= 2) {
      final first = sorted.first;
      final last  = sorted.last;
      if (last - first == sorted.length - 1) {
        return '${_hr(first)} – ${_hr(last + 1)}';
      }
    }
    return sorted.map(_hr).join(', ');
  }

  String _hr(int h) {
    if (h == 0 || h == 24) return '12 AM';
    if (h == 12) return '12 PM';
    return h < 12 ? '$h AM' : '${h - 12} PM';
  }
}

// 单行信息条目
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Text(
          '$label  ',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF1A1A2E),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================
// _TodayStatsRow — 今日实时统计（3 mini 卡片）
// =============================================================
class _TodayStatsRow extends StatelessWidget {
  final AdCampaign campaign;

  const _TodayStatsRow({required this.campaign});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TodayMiniCard(
            label: 'Today Spend',
            value: '\$${campaign.todaySpend.toStringAsFixed(2)}',
            icon: Icons.payments_outlined,
            color: const Color(0xFFFF6B35),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TodayMiniCard(
            label: 'Impressions',
            value: campaign.todayImpressions.toString(),
            icon: Icons.visibility_outlined,
            color: const Color(0xFF9C27B0),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TodayMiniCard(
            label: 'Clicks',
            value: campaign.todayClicks.toString(),
            icon: Icons.ads_click_outlined,
            color: const Color(0xFF2196F3),
          ),
        ),
      ],
    );
  }
}

class _TodayMiniCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _TodayMiniCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(bottom: BorderSide(color: color, width: 2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _ActionRow — 操作按钮（Pause / Resume + Delete）
// =============================================================
class _ActionRow extends StatelessWidget {
  final AdCampaign campaign;
  final bool isProcessing;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onDelete;

  const _ActionRow({
    required this.campaign,
    required this.isProcessing,
    required this.onPause,
    required this.onResume,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final canPause = campaign.status == CampaignStatus.active ||
        campaign.status == CampaignStatus.exhausted;
    final canResume = campaign.status == CampaignStatus.paused;

    return Row(
      children: [
        // Pause / Resume 按钮
        if (canPause || canResume)
          Expanded(
            child: _OutlineActionButton(
              icon: canPause
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              label: canPause ? 'Pause' : 'Resume',
              color: canPause
                  ? const Color(0xFFFF9800)
                  : const Color(0xFF4CAF50),
              isLoading: isProcessing,
              onTap: canPause ? onPause : onResume,
            ),
          ),
        if (canPause || canResume) const SizedBox(width: 10),

        // Delete 按钮
        SizedBox(
          width: 110,
          child: _OutlineActionButton(
            icon: Icons.delete_outline,
            label: 'Delete',
            color: const Color(0xFFE53935),
            isLoading: isProcessing,
            onTap: onDelete,
          ),
        ),
      ],
    );
  }
}

class _OutlineActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isLoading;
  final VoidCallback onTap;

  const _OutlineActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(100)),
          color: color.withAlpha(15),
        ),
        child: isLoading
            ? Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: color,
                    strokeWidth: 2,
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// =============================================================
// _PeriodSelector — 时间段选择器
// =============================================================
class _PeriodSelector extends StatelessWidget {
  final ReportPeriod selected;
  final ValueChanged<ReportPeriod> onChanged;

  const _PeriodSelector({required this.selected, required this.onChanged});

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
                    color: isSelected ? Colors.white : Colors.grey.shade600,
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
// _ReportBody — 报告主体（汇总 + 图表 + 明细）
// =============================================================
class _ReportBody extends StatelessWidget {
  final AdCampaignReport report;

  const _ReportBody({required this.report});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryCards(report: report),
          const SizedBox(height: 24),
          _SectionTitle(title: 'Daily Trend'),
          const SizedBox(height: 12),
          report.dailyStats.isEmpty
              ? _EmptyChart()
              : _DailyBarChart(dailyStats: report.dailyStats),
          const SizedBox(height: 24),
          _SectionTitle(title: 'Daily Breakdown'),
          const SizedBox(height: 12),
          report.dailyStats.isEmpty
              ? _EmptyTable()
              : _DailyTable(dailyStats: report.dailyStats),
        ],
      ),
    );
  }
}

// =============================================================
// _SummaryCards — 汇总指标卡片（3 列）
// =============================================================
class _SummaryCards extends StatelessWidget {
  final AdCampaignReport report;

  const _SummaryCards({required this.report});

  @override
  Widget build(BuildContext context) {
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
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
          Row(
            children: [
              _LegendDot(color: const Color(0xFFFF6B35), label: 'Spend'),
              const SizedBox(width: 16),
              _LegendDot(color: const Color(0xFF2196F3), label: 'Clicks'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: CustomPaint(
              size: const Size(double.infinity, 140),
              painter: _BarChartPainter(data: data),
            ),
          ),
          const SizedBox(height: 8),
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

class _BarChartPainter extends CustomPainter {
  final List<AdDailyStat> data;

  _BarChartPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    double maxSpend = 0.0, maxClicks = 0.0;
    for (final d in data) {
      final s = (d.spend as num).toDouble();
      final c = (d.clicks as num).toDouble();
      if (s > maxSpend)  maxSpend  = s;
      if (c > maxClicks) maxClicks = c;
    }
    final maxVal = (maxSpend > maxClicks ? maxSpend : maxClicks)
        .clamp(1.0, double.infinity);

    final barGroupWidth = size.width / data.length;
    final barWidth      = (barGroupWidth * 0.3).clamp(2.0, 12.0);
    final spendPaint    = Paint()..color = const Color(0xFFFF6B35);
    final clicksPaint   = Paint()..color = const Color(0xFF2196F3);

    for (int i = 0; i < data.length; i++) {
      final stat      = data[i];
      final groupLeft = barGroupWidth * i + barGroupWidth * 0.1;
      final spendH    = (stat.spend / maxVal * size.height).clamp(2.0, size.height);
      final clicksH   = (stat.clicks / maxVal * size.height).clamp(
          stat.clicks > 0 ? 2.0 : 0.0, size.height);

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(groupLeft, size.height - spendH, barWidth, spendH),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        spendPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(groupLeft + barWidth + 2, size.height - clicksH,
              barWidth, clicksH),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        clicksPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

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
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }
}

// =============================================================
// _DailyTable — 每日明细表格
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
          _TableHeader(),
          const Divider(height: 1),
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
                      color: Colors.grey.shade500))),
          Expanded(
              child: Text('Spend',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500))),
          Expanded(
              child: Text('Clicks',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500))),
          Expanded(
              child: Text('Impr.',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500))),
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
          border: Border(top: BorderSide(color: Color(0xFFF5F5F5)))),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '${stat.date.year}-${stat.date.month.toString().padLeft(2, '0')}-${stat.date.day.toString().padLeft(2, '0')}',
              style:
                  const TextStyle(fontSize: 13, color: Color(0xFF1A1A2E)),
            ),
          ),
          Expanded(
            child: Text(
              '\$${stat.spend.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFF6B35)),
            ),
          ),
          Expanded(
            child: Text(
              stat.clicks.toString(),
              textAlign: TextAlign.right,
              style:
                  const TextStyle(fontSize: 13, color: Color(0xFF1A1A2E)),
            ),
          ),
          Expanded(
            child: Text(
              stat.impressions.toString(),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
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
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Center(
        child: Text('No data for this period',
            style:
                TextStyle(fontSize: 14, color: Colors.grey.shade400)),
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
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Center(
        child: Text('No daily records found',
            style:
                TextStyle(fontSize: 14, color: Colors.grey.shade400)),
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
    return Padding(
      padding: const EdgeInsets.all(40),
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
                foregroundColor: Colors.white),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _PlacementIcon / _StatusBadge — 复用自 campaign_card.dart
// =============================================================

class _PlacementIcon extends StatelessWidget {
  final String placement;

  const _PlacementIcon({required this.placement});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _resolve(placement);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  (IconData, Color) _resolve(String p) {
    switch (p) {
      case 'home_deal_top':
      case 'home_featured':
        return (Icons.home_outlined, const Color(0xFFFF6B35));
      case 'search_top':
        return (Icons.search, const Color(0xFF2196F3));
      case 'category_deal_top':
      case 'category_banner':
        return (Icons.category_outlined, const Color(0xFF9C27B0));
      case 'splash':
        return (Icons.fullscreen, const Color(0xFF00BCD4));
      default:
        return (Icons.campaign_outlined, const Color(0xFF607D8B));
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final CampaignStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _resolve(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(77)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  (String, Color) _resolve(CampaignStatus s) {
    switch (s) {
      case CampaignStatus.active:
        return ('Active', const Color(0xFF4CAF50));
      case CampaignStatus.paused:
        return ('Paused', const Color(0xFFFF9800));
      case CampaignStatus.exhausted:
        return ('Exhausted', const Color(0xFFFF7043));
      case CampaignStatus.ended:
        return ('Ended', const Color(0xFF2196F3));
      case CampaignStatus.adminPaused:
        return ('Admin Paused', const Color(0xFFE53935));
    }
  }
}
