// 交易明细页面
// 包含: 顶部日期范围筛选 / 完整交易列表 / 列表底部合计行

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/earnings_data.dart';
import '../providers/earnings_provider.dart';
import '../widgets/transaction_tile.dart';

// =============================================================
// TransactionsPage — 完整交易明细页（ConsumerWidget）
// =============================================================
class TransactionsPage extends ConsumerWidget {
  const TransactionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsProvider);
    final filter            = ref.watch(transactionsFilterProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(context, ref, filter),
      body: transactionsAsync.when(
        loading: () => _buildLoading(),
        error:   (err, st) => _buildError(context, ref, err),
        data:    (paged) => _buildContent(context, ref, paged, filter),
      ),
    );
  }

  // ----------------------------------------------------------
  // AppBar：标题 + 清除筛选按钮
  // ----------------------------------------------------------
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    TransactionsFilter filter,
  ) {
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
        'Transactions',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A2E),
        ),
      ),
      // 有筛选条件时显示清除按钮
      actions: [
        if (filter.hasFilter)
          TextButton(
            onPressed: () =>
                ref.read(transactionsProvider.notifier).clearFilter(),
            child: const Text(
              'Clear Filter',
              style: TextStyle(
                color: Color(0xFFFF6B35),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ----------------------------------------------------------
  // 完整内容（包含筛选器 + 列表 + 合计）
  // ----------------------------------------------------------
  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    PagedTransactions paged,
    TransactionsFilter filter,
  ) {
    return Column(
      children: [
        // 顶部日期筛选器
        _DateRangeFilter(
          filter: filter,
          onApply: (from, to) =>
              ref.read(transactionsProvider.notifier).applyFilter(from: from, to: to),
        ),

        // 交易列表（可滚动）
        Expanded(
          child: paged.data.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: const Color(0xFFFF6B35),
                  onRefresh: () =>
                      ref.read(transactionsProvider.notifier).refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 100),
                    itemCount: paged.data.length + 1, // +1 for totals row
                    itemBuilder: (context, index) {
                      // 最后一项：合计行
                      if (index == paged.data.length) {
                        return TransactionTotalsRow(
                          totalAmount:      paged.totals.amount,
                          totalTaxAmount:   paged.totals.taxAmount,
                          totalPlatformFee: paged.totals.platformFee,
                          totalStripeFee:   paged.totals.stripeFee,
                          totalNetAmount:   paged.totals.netAmount,
                          orderCount:       paged.total,
                        );
                      }
                      final tx     = paged.data[index];
                      final isLast = index == paged.data.length - 1;
                      return TransactionTile(
                        transaction: tx,
                        showDivider: !isLast,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // 加载中骨架屏
  // ----------------------------------------------------------
  Widget _buildLoading() {
    return Column(
      children: [
        // 筛选器占位
        Container(
          height: 64,
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        // 列表骨架
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 8,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 12,
                          width: 100,
                          color: Colors.grey.shade200,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 10,
                          width: 70,
                          color: Colors.grey.shade100,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 40,
                    width: 72,
                    color: Colors.grey.shade100,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // 空状态（无交易记录）
  // ----------------------------------------------------------
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting the date filter',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // 错误状态
  // ----------------------------------------------------------
  Widget _buildError(BuildContext context, WidgetRef ref, Object err) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Failed to load transactions',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              err.toString().replaceFirst('EarningsException', '').trim(),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () =>
                  ref.read(transactionsProvider.notifier).refresh(),
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
        ),
      ),
    );
  }
}

// =============================================================
// _DateRangeFilter — 顶部日期范围筛选器
// =============================================================
class _DateRangeFilter extends StatefulWidget {
  final TransactionsFilter filter;
  final void Function(DateTime? from, DateTime? to) onApply;

  const _DateRangeFilter({required this.filter, required this.onApply});

  @override
  State<_DateRangeFilter> createState() => _DateRangeFilterState();
}

class _DateRangeFilterState extends State<_DateRangeFilter> {
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _from = widget.filter.dateFrom;
    _to   = widget.filter.dateTo;
  }

  @override
  void didUpdateWidget(_DateRangeFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部清除筛选时同步重置
    if (!widget.filter.hasFilter) {
      _from = null;
      _to   = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFilter = _from != null || _to != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // From 日期选择
          Expanded(
            child: _DateButton(
              label: 'From',
              date: _from,
              onTap: () => _pickDate(context, isFrom: true),
            ),
          ),
          Container(
            width: 1,
            height: 32,
            color: Colors.grey.shade200,
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
          // To 日期选择
          Expanded(
            child: _DateButton(
              label: 'To',
              date: _to,
              onTap: () => _pickDate(context, isFrom: false),
            ),
          ),
          const SizedBox(width: 12),
          // 应用按钮
          SizedBox(
            height: 36,
            child: ElevatedButton(
              key: const ValueKey('transactions_apply_filter_btn'),
              onPressed: hasFilter
                  ? () => widget.onApply(_from, _to)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                disabledBackgroundColor: Colors.grey.shade200,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Apply',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(BuildContext context, {required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom
        ? (_from ?? DateTime(now.year, now.month, 1))
        : (_to   ?? now);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024, 1),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: const Color(0xFFFF6B35),
              ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        if (isFrom) {
          _from = picked;
          // 若 to 早于 from，自动调整
          if (_to != null && _to!.isBefore(_from!)) _to = null;
        } else {
          _to = picked;
          // 若 from 晚于 to，自动调整
          if (_from != null && _from!.isAfter(_to!)) _from = null;
        }
      });
    }
  }
}

// 日期选择按钮（显示已选日期或占位文字）
class _DateButton extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const _DateButton({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasDate   = date != null;
    final dateLabel = hasDate
        ? DateFormat('MMM d').format(date!)
        : label;

    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 14,
            color: hasDate
                ? const Color(0xFFFF6B35)
                : Colors.grey.shade400,
          ),
          const SizedBox(width: 6),
          Text(
            dateLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: hasDate ? FontWeight.w600 : FontWeight.w400,
              color: hasDate
                  ? const Color(0xFF1A1A2E)
                  : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}
