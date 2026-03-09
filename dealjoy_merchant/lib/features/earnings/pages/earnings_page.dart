// 财务与结算主页面
// 包含: 月份选择器 / 收入概览4卡片 / 结算说明区 / 近10条交易预览 / 收款账户状态条

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/earnings_data.dart';
import '../providers/earnings_provider.dart';
import '../widgets/earnings_summary_card.dart';
import '../widgets/transaction_tile.dart';

// =============================================================
// EarningsPage — 财务与结算主页（ConsumerWidget）
// =============================================================
class EarningsPage extends ConsumerWidget {
  const EarningsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync        = ref.watch(earningsSummaryProvider);
    final settlementAsync     = ref.watch(settlementScheduleProvider);
    final stripeAsync         = ref.watch(stripeAccountProvider);
    final transactionsAsync   = ref.watch(transactionsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(context, ref),
      body: RefreshIndicator(
        color: const Color(0xFFFF6B35),
        onRefresh: () => ref.read(earningsSummaryProvider.notifier).refresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ------------------------------------------------
              // 区块 1: 月份选择器
              // ------------------------------------------------
              _MonthPicker(ref: ref),
              const SizedBox(height: 16),

              // ------------------------------------------------
              // 区块 2: 收入概览 4 卡片
              // ------------------------------------------------
              _SectionHeader(title: 'Earnings Overview'),
              const SizedBox(height: 12),
              _SummaryCardsGrid(summaryAsync: summaryAsync),
              const SizedBox(height: 24),

              // ------------------------------------------------
              // 区块 3: 结算规则与下次打款
              // ------------------------------------------------
              _SectionHeader(title: 'Settlement Info'),
              const SizedBox(height: 12),
              _SettlementInfoCard(settlementAsync: settlementAsync),
              const SizedBox(height: 24),

              // ------------------------------------------------
              // 区块 4: 近期交易预览（前 10 条）
              // ------------------------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SectionHeader(title: 'Recent Transactions'),
                  TextButton(
                    key: const ValueKey('earnings_view_all_transactions_btn'),
                    onPressed: () => context.push('/earnings/transactions'),
                    child: const Text(
                      'View All',
                      style: TextStyle(
                        color: Color(0xFFFF6B35),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _RecentTransactionsCard(transactionsAsync: transactionsAsync),
              const SizedBox(height: 24),

              // ------------------------------------------------
              // 区块 5: 提现入口
              // ------------------------------------------------
              _SectionHeader(title: 'Withdrawal'),
              const SizedBox(height: 12),
              // 提现快速入口卡片
              InkWell(
                key: const ValueKey('earnings_withdrawal_btn'),
                onTap: () => context.push('/earnings/withdrawal'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined,
                          color: Color(0xFFFF6B35), size: 24),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Withdraw Funds',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Transfer available balance to your bank',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF999999)),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Color(0xFFBDBDBD)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ------------------------------------------------
              // 区块 6: 收款账户状态条
              // ------------------------------------------------
              _SectionHeader(title: 'Payment Account'),
              const SizedBox(height: 12),
              _StripeAccountBanner(
                stripeAsync: stripeAsync,
                onManageTap: () => context.push('/earnings/payment-account'),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
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
      title: const Text(
        'Earnings',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A2E),
        ),
      ),
      // 报表入口按钮
      actions: [
        IconButton(
          key: const ValueKey('earnings_report_btn'),
          icon: const Icon(Icons.bar_chart_outlined, color: Color(0xFF1A1A2E)),
          tooltip: 'Reports',
          onPressed: () => context.push('/earnings/report'),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// =============================================================
// _MonthPicker — 月份选择器（上/下月切换）
// =============================================================
class _MonthPicker extends StatelessWidget {
  final WidgetRef ref;

  const _MonthPicker({required this.ref});

  @override
  Widget build(BuildContext context) {
    final selectedMonth = ref.watch(selectedMonthProvider);
    final monthLabel    = DateFormat('MMMM yyyy').format(selectedMonth);
    final now           = DateTime.now();
    final isCurrentMonth =
        selectedMonth.year == now.year && selectedMonth.month == now.month;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 上月按钮
          IconButton(
            onPressed: () => _changeMonth(ref, -1),
            icon: const Icon(Icons.chevron_left),
            color: const Color(0xFF1A1A2E),
            tooltip: 'Previous month',
          ),
          // 月份标签（可点击打开日期选择器）
          GestureDetector(
            onTap: () => _showMonthPicker(context, ref, selectedMonth),
            child: Column(
              children: [
                Text(
                  monthLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                if (isCurrentMonth)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withAlpha(26),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Current Month',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFFFF6B35),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 下月按钮（不能超过本月）
          IconButton(
            onPressed: isCurrentMonth ? null : () => _changeMonth(ref, 1),
            icon: const Icon(Icons.chevron_right),
            color: isCurrentMonth ? Colors.grey.shade300 : const Color(0xFF1A1A2E),
            tooltip: 'Next month',
          ),
        ],
      ),
    );
  }

  void _changeMonth(WidgetRef ref, int delta) {
    final current = ref.read(selectedMonthProvider);
    final newMonth = DateTime(current.year, current.month + delta, 1);
    ref.read(selectedMonthProvider.notifier).state = newMonth;
  }

  Future<void> _showMonthPicker(
    BuildContext context,
    WidgetRef ref,
    DateTime current,
  ) async {
    // 简单使用 showDatePicker，仅允许选年月
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2024, 1),
      lastDate: DateTime.now(),
      helpText: 'Select Month',
      fieldLabelText: 'Month',
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
      ref.read(selectedMonthProvider.notifier).state =
          DateTime(picked.year, picked.month, 1);
    }
  }
}

// =============================================================
// _SummaryCardsGrid — 收入概览 2x2 卡片网格
// =============================================================
class _SummaryCardsGrid extends StatelessWidget {
  final AsyncValue<EarningsSummary> summaryAsync;

  const _SummaryCardsGrid({required this.summaryAsync});

  @override
  Widget build(BuildContext context) {
    return summaryAsync.when(
      loading: () => _buildGrid(null),
      error:   (err, _) => _buildErrorState(context, err),
      data:    (summary) => _buildGrid(summary),
    );
  }

  Widget _buildGrid(EarningsSummary? summary) {
    final isLoading = summary == null;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        EarningsSummaryCard(
          title:     'This Month',
          amount:    isLoading ? '' : '\$${summary.totalRevenue.toStringAsFixed(2)}',
          icon:      Icons.attach_money,
          color:     const Color(0xFFFF6B35),
          isLoading: isLoading,
          subtitle:  'Gross revenue',
        ),
        EarningsSummaryCard(
          title:     'Pending',
          amount:    isLoading ? '' : '\$${summary.pendingSettlement.toStringAsFixed(2)}',
          icon:      Icons.hourglass_bottom_outlined,
          color:     const Color(0xFFFF9800),
          isLoading: isLoading,
          subtitle:  'Awaiting T+7',
        ),
        EarningsSummaryCard(
          title:     'Settled',
          amount:    isLoading ? '' : '\$${summary.settledAmount.toStringAsFixed(2)}',
          icon:      Icons.check_circle_outline,
          color:     const Color(0xFF4CAF50),
          isLoading: isLoading,
          subtitle:  'Net paid out',
        ),
        EarningsSummaryCard(
          title:     'Refunded',
          amount:    isLoading ? '' : '\$${summary.refundedAmount.toStringAsFixed(2)}',
          icon:      Icons.reply_outlined,
          color:     const Color(0xFFF44336),
          isLoading: isLoading,
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, Object err) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Failed to load earnings: ${err.toString().replaceFirst('EarningsException', '')}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _SettlementInfoCard — 结算规则说明卡片
// =============================================================
class _SettlementInfoCard extends StatelessWidget {
  final AsyncValue<SettlementSchedule> settlementAsync;

  const _SettlementInfoCard({required this.settlementAsync});

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: settlementAsync.when(
        loading: () => _buildLoading(),
        error:   (err, st) => _buildDefault(),
        data:    (schedule) => _buildContent(schedule),
      ),
    );
  }

  Widget _buildContent(SettlementSchedule schedule) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 规则说明行
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: Color(0xFF4CAF50),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Settlement Policy',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Settled T+${schedule.settlementDays} days after redemption via Stripe Connect',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (schedule.hasPendingSettlement) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 12),
            // 下次打款信息
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Next Payout',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        schedule.nextPayoutDate != null
                            ? DateFormat('MMM d, yyyy').format(schedule.nextPayoutDate!)
                            : '—',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Pending Amount',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '\$${schedule.pendingAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFF9800),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'No pending settlements',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          2,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefault() {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Settled T+7 days after redemption via Stripe Connect',
        style: TextStyle(fontSize: 13, color: Color(0xFF1A1A2E)),
      ),
    );
  }
}

// =============================================================
// _RecentTransactionsCard — 近期交易预览卡片（前 10 条）
// =============================================================
class _RecentTransactionsCard extends StatelessWidget {
  final AsyncValue<PagedTransactions> transactionsAsync;

  const _RecentTransactionsCard({required this.transactionsAsync});

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: transactionsAsync.when(
        loading: () => _buildLoading(),
        error:   (err, _) => _buildError(err),
        data:    (paged) => _buildContent(paged),
      ),
    );
  }

  Widget _buildContent(PagedTransactions paged) {
    if (paged.data.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.receipt_long_outlined, size: 40, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text(
                'No transactions yet',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    // 取前 10 条预览
    final preview = paged.data.take(10).toList();

    return Column(
      children: preview.asMap().entries.map((entry) {
        final isLast = entry.key == preview.length - 1;
        return TransactionTile(
          transaction: entry.value,
          showDivider: !isLast,
        );
      }).toList(),
    );
  }

  Widget _buildLoading() {
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                    Container(height: 12, width: 100, color: Colors.grey.shade200),
                    const SizedBox(height: 6),
                    Container(height: 10, width: 72, color: Colors.grey.shade100),
                  ],
                ),
              ),
              Container(height: 40, width: 70, color: Colors.grey.shade100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(Object err) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Failed to load transactions',
        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
      ),
    );
  }
}

// =============================================================
// _StripeAccountBanner — Stripe 账户状态横幅
// =============================================================
class _StripeAccountBanner extends StatelessWidget {
  final AsyncValue<StripeAccountInfo> stripeAsync;
  final VoidCallback onManageTap;

  const _StripeAccountBanner({
    required this.stripeAsync,
    required this.onManageTap,
  });

  @override
  Widget build(BuildContext context) {
    return stripeAsync.when(
      loading: () => _buildLoading(),
      error:   (err, st) => _buildNotConnected(context),
      data:    (info) => info.isConnected
          ? _buildConnected(context, info)
          : _buildNotConnected(context),
    );
  }

  Widget _buildConnected(BuildContext context, StripeAccountInfo info) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withAlpha(13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4CAF50).withAlpha(51)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.check_circle_outline,
              size: 20,
              color: Color(0xFF4CAF50),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stripe Connected',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                if (info.accountEmail != null || info.accountDisplayId != null)
                  Text(
                    info.accountEmail ?? info.accountDisplayId ?? '',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onManageTap,
            child: const Text(
              'Manage',
              style: TextStyle(
                color: Color(0xFF4CAF50),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotConnected(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF44336).withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF44336).withAlpha(38)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF44336).withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.warning_amber_outlined,
              size: 20,
              color: Color(0xFFF44336),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Payment Account Not Connected',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  'Connect Stripe to receive payouts',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _showConnectTip(context),
            child: const Text(
              'Setup',
              style: TextStyle(
                color: Color(0xFFFF6B35),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  void _showConnectTip(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Stripe Connect integration coming soon!'),
        backgroundColor: const Color(0xFFFF6B35),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

// =============================================================
// _SectionHeader — 区块标题（复用）
// =============================================================
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
