// 对账报表页面（P2）
// 展示月度/周度对账报表数据，V1 不实现 PDF 下载
// 仅展示数据表格

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/earnings_data.dart';
import '../providers/earnings_provider.dart';

// =============================================================
// EarningsReportPage — 对账报表页（ConsumerWidget）
// =============================================================
class EarningsReportPage extends ConsumerWidget {
  const EarningsReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodType    = ref.watch(reportPeriodTypeProvider);
    final selectedMonth = ref.watch(reportSelectedMonthProvider);
    final reportAsync   = ref.watch(reportDataProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          // 顶部控制栏（周期类型切换 + 月份选择器）
          _ReportControls(
            periodType:    periodType,
            selectedMonth: selectedMonth,
            ref:           ref,
          ),
          // 报表数据区
          Expanded(
            child: reportAsync.when(
              loading: () => _buildLoading(),
              error:   (err, st) => _buildError(context, ref, err),
              data:    (report) => _buildReportTable(context, report),
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
        'Reports',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A2E),
        ),
      ),
      // V1 不实现 PDF 下载，显示灰色按钮提示
      actions: [
        IconButton(
          icon: Icon(Icons.download_outlined, color: Colors.grey.shade400),
          tooltip: 'Export (coming soon)',
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('PDF export coming soon!'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ----------------------------------------------------------
  // 报表数据表格
  // ----------------------------------------------------------
  Widget _buildReportTable(BuildContext context, ReportData report) {
    if (report.rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No data for this period',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            // 表头
            _TableHeader(),
            Divider(height: 1, color: Colors.grey.shade200),
            // 数据行
            ...report.rows.asMap().entries.map((entry) {
              final isEven = entry.key.isEven;
              return _TableRow(row: entry.value, isEven: isEven);
            }),
            Divider(height: 1, color: Colors.grey.shade300),
            // 合计行
            _TotalsRow(totals: report.totals),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Color(0xFFFF6B35)),
          const SizedBox(height: 16),
          Text(
            'Loading report...',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, Object err) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('Failed to load report'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ref.invalidate(reportDataProvider),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B35),
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _ReportControls — 报表控制栏
// =============================================================
class _ReportControls extends StatelessWidget {
  final ReportPeriodType periodType;
  final DateTime selectedMonth;
  final WidgetRef ref;

  const _ReportControls({
    required this.periodType,
    required this.selectedMonth,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          // 周期类型切换（Monthly / Weekly）
          Row(
            children: ReportPeriodType.values.map((type) {
              final isSelected = type == periodType;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: type == ReportPeriodType.monthly ? 6 : 0,
                    left:  type == ReportPeriodType.weekly  ? 6 : 0,
                  ),
                  child: OutlinedButton(
                    onPressed: () {
                      ref.read(reportPeriodTypeProvider.notifier).state = type;
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isSelected
                          ? const Color(0xFFFF6B35)
                          : Colors.transparent,
                      foregroundColor: isSelected
                          ? Colors.white
                          : Colors.grey.shade600,
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFFFF6B35)
                            : Colors.grey.shade300,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      type.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // 月份选择器（左右翻页）
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => _changeMonth(ref, -1),
                icon: const Icon(Icons.chevron_left),
                color: const Color(0xFF1A1A2E),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Text(
                DateFormat('MMMM yyyy').format(selectedMonth),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              IconButton(
                onPressed: _canGoNext(selectedMonth)
                    ? () => _changeMonth(ref, 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
                color: _canGoNext(selectedMonth)
                    ? const Color(0xFF1A1A2E)
                    : Colors.grey.shade300,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _changeMonth(WidgetRef ref, int delta) {
    final current = ref.read(reportSelectedMonthProvider);
    ref.read(reportSelectedMonthProvider.notifier).state =
        DateTime(current.year, current.month + delta, 1);
  }

  bool _canGoNext(DateTime current) {
    final now = DateTime.now();
    return current.year < now.year ||
        (current.year == now.year && current.month < now.month);
  }
}

// =============================================================
// _TableHeader — 报表表头
// =============================================================
class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Date',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Orders',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
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
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Net',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _TableRow — 报表数据行
// =============================================================
class _TableRow extends StatelessWidget {
  final ReportRow row;
  final bool isEven;

  const _TableRow({required this.row, required this.isEven});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isEven ? Colors.grey.shade50 : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              DateFormat('MMM d').format(row.date),
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${row.orderCount}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A2E)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '\$${row.grossAmount.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A2E)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '\$${row.netAmount.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4CAF50),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _TotalsRow — 合计行
// =============================================================
class _TotalsRow extends StatelessWidget {
  final ReportTotals totals;

  const _TotalsRow({required this.totals});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFF6B35).withAlpha(13),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Expanded(
            flex: 3,
            child: Text(
              'Total',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${totals.orderCount}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '\$${totals.grossAmount.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '\$${totals.netAmount.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4CAF50),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
