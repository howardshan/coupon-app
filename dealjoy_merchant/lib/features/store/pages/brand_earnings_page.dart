// 品牌佣金收益页面
// 展示: 月份选择器 / 4 概览卡片 / 佣金费率卡片 / 近期交易 / Stripe 状态 / 提现入口

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/brand_earnings_data.dart';
import '../models/brand_info.dart';
import '../providers/brand_earnings_provider.dart';
import '../providers/store_provider.dart';

// =============================================================
// BrandEarningsPage — 品牌收益主页
// =============================================================
class BrandEarningsPage extends ConsumerWidget {
  const BrandEarningsPage({super.key});

  static const _orange = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(brandEarningsSummaryProvider);
    final transactionsAsync = ref.watch(brandTransactionsProvider);
    final stripeAsync = ref.watch(brandStripeAccountProvider);
    // 从 storeProvider 获取品牌信息（含 commissionRate）
    final storeAsync = ref.watch(storeProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: const Color(0xFF1A1A2E),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Brand Earnings',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: _orange,
        onRefresh: () async {
          await ref.read(brandEarningsSummaryProvider.notifier).refresh();
          await ref.read(brandTransactionsProvider.notifier).refresh();
          ref.invalidate(brandStripeAccountProvider);
          ref.invalidate(brandBalanceProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 月份选择器
              _BrandMonthPicker(ref: ref),
              const SizedBox(height: 16),

              // 收益概览 4 卡片
              _sectionHeader('Earnings Overview'),
              const SizedBox(height: 12),
              _SummaryGrid(summaryAsync: summaryAsync),
              const SizedBox(height: 24),

              // 佣金费率卡片（从 brand 获取 commissionRate）
              _sectionHeader('Commission Rate'),
              const SizedBox(height: 12),
              _CommissionRateCard(storeAsync: storeAsync),
              const SizedBox(height: 24),

              // 近期交易预览
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _sectionHeader('Recent Transactions'),
                ],
              ),
              const SizedBox(height: 8),
              _RecentTransactionsCard(transactionsAsync: transactionsAsync),
              const SizedBox(height: 24),

              // 提现入口
              _sectionHeader('Withdrawal'),
              const SizedBox(height: 12),
              _WithdrawEntryCard(
                onTap: () => context.push('/brand-manage/withdrawal'),
              ),
              const SizedBox(height: 24),

              // Stripe 账户状态
              _sectionHeader('Stripe Account'),
              const SizedBox(height: 12),
              _StripeStatusBanner(
                stripeAsync: stripeAsync,
                onManageTap: () => context.push('/brand-manage/stripe-connect'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
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

// =============================================================
// _BrandMonthPicker — 月份选择器
// =============================================================
class _BrandMonthPicker extends StatelessWidget {
  final WidgetRef ref;

  const _BrandMonthPicker({required this.ref});

  @override
  Widget build(BuildContext context) {
    final selectedMonth = ref.watch(brandSelectedMonthProvider);
    final monthLabel = DateFormat('MMMM yyyy').format(selectedMonth);
    final now = DateTime.now();
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
          IconButton(
            onPressed: () => _changeMonth(ref, -1),
            icon: const Icon(Icons.chevron_left),
            color: const Color(0xFF1A1A2E),
          ),
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
          IconButton(
            onPressed: isCurrentMonth ? null : () => _changeMonth(ref, 1),
            icon: const Icon(Icons.chevron_right),
            color: isCurrentMonth ? Colors.grey.shade300 : const Color(0xFF1A1A2E),
          ),
        ],
      ),
    );
  }

  void _changeMonth(WidgetRef ref, int delta) {
    final current = ref.read(brandSelectedMonthProvider);
    ref.read(brandSelectedMonthProvider.notifier).state =
        DateTime(current.year, current.month + delta, 1);
  }

  Future<void> _showMonthPicker(
    BuildContext context,
    WidgetRef ref,
    DateTime current,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2024, 1),
      lastDate: DateTime.now(),
      helpText: 'Select Month',
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
      ref.read(brandSelectedMonthProvider.notifier).state =
          DateTime(picked.year, picked.month, 1);
    }
  }
}

// =============================================================
// _SummaryGrid — 收益概览 2x2 卡片网格
// =============================================================
class _SummaryGrid extends StatelessWidget {
  final AsyncValue<BrandEarningsSummary> summaryAsync;

  const _SummaryGrid({required this.summaryAsync});

  @override
  Widget build(BuildContext context) {
    return summaryAsync.when(
      loading: () => _buildGrid(null),
      error: (e, _) => _buildErrorState(context, e),
      data: (s) => _buildGrid(s),
    );
  }

  Widget _buildGrid(BrandEarningsSummary? s) {
    final isLoading = s == null;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        _SummaryCard(
          title: 'Brand Revenue',
          amount: isLoading ? '' : '\$${s.totalBrandRevenue.toStringAsFixed(2)}',
          icon: Icons.account_balance_wallet_outlined,
          color: const Color(0xFFFF6B35),
          isLoading: isLoading,
          subtitle: 'This month',
        ),
        _SummaryCard(
          title: 'Pending',
          amount: isLoading ? '' : '\$${s.pendingSettlement.toStringAsFixed(2)}',
          icon: Icons.hourglass_bottom_outlined,
          color: const Color(0xFFFF9800),
          isLoading: isLoading,
          subtitle: 'Awaiting settlement',
        ),
        _SummaryCard(
          title: 'Settled',
          amount: isLoading ? '' : '\$${s.settledAmount.toStringAsFixed(2)}',
          icon: Icons.check_circle_outline,
          color: const Color(0xFF4CAF50),
          isLoading: isLoading,
          subtitle: 'Paid out',
        ),
        _SummaryCard(
          title: 'Refunded',
          amount: isLoading ? '' : '\$${s.refundedAmount.toStringAsFixed(2)}',
          icon: Icons.reply_outlined,
          color: const Color(0xFFF44336),
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
              'Failed to load earnings data',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// 单个概览卡片
class _SummaryCard extends StatelessWidget {
  final String title;
  final String amount;
  final IconData icon;
  final Color color;
  final bool isLoading;
  final String? subtitle;

  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
    required this.isLoading,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(height: 8),
          isLoading
              ? Container(
                  height: 16,
                  width: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                )
              : Text(
                  amount,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
          const SizedBox(height: 2),
          Text(
            subtitle ?? title,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _CommissionRateCard — 品牌佣金费率卡片
// =============================================================
class _CommissionRateCard extends StatelessWidget {
  final AsyncValue storeAsync;

  const _CommissionRateCard({required this.storeAsync});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: storeAsync.when(
        loading: () => const SizedBox(
          height: 40,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Text(
          'Commission rate unavailable',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
        data: (storeInfo) {
          final brand = storeInfo?.brand as BrandInfo?;
          final rate = brand?.commissionRate ?? 0.0;
          final rateLabel = rate > 0
              ? '${(rate * 100).toStringAsFixed(0)}%'
              : 'Not set';

          return Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.percent_outlined,
                  color: Color(0xFFFF6B35),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Brand Commission Rate',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Applied to each redeemed voucher from brand deals',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  rateLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF6B35),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================
// _RecentTransactionsCard — 近期交易预览卡片
// =============================================================
class _RecentTransactionsCard extends StatelessWidget {
  final AsyncValue transactionsAsync;

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
        error: (e, _) => _buildError(),
        data: (result) {
          final items = (result as ({
            List<BrandTransaction> items,
            int total,
            Map<String, double> totals
          }))
              .items;
          if (items.isEmpty) return _buildEmpty();
          return _buildList(items);
        },
      ),
    );
  }

  Widget _buildList(List<BrandTransaction> items) {
    return Column(
      children: items.asMap().entries.map((entry) {
        final isLast = entry.key == items.length - 1;
        return _TransactionTile(
          tx: entry.value,
          showDivider: !isLast,
        );
      }).toList(),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(
            'No transactions this month',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
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
              Container(height: 40, width: 60, color: Colors.grey.shade100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Failed to load transactions',
        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
      ),
    );
  }
}

// 单条交易记录行
class _TransactionTile extends StatelessWidget {
  final BrandTransaction tx;
  final bool showDivider;

  const _TransactionTile({required this.tx, required this.showDivider});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(tx.status);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(_statusIcon(tx.status), color: statusColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.dealTitle,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tx.storeName,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '+\$${tx.brandFee.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tx.statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 64,
            endIndent: 16,
            color: Colors.grey.shade100,
          ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'settled':
        return const Color(0xFF4CAF50);
      case 'refunded':
        return const Color(0xFFF44336);
      default:
        return const Color(0xFFFF9800);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'settled':
        return Icons.check_circle_outline;
      case 'refunded':
        return Icons.reply_outlined;
      default:
        return Icons.hourglass_empty;
    }
  }
}

// =============================================================
// _WithdrawEntryCard — 提现入口卡片
// =============================================================
class _WithdrawEntryCard extends StatelessWidget {
  final VoidCallback onTap;

  const _WithdrawEntryCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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
            Icon(
              Icons.account_balance_wallet_outlined,
              color: Color(0xFFFF6B35),
              size: 24,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Withdraw Brand Earnings',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Transfer available balance to your bank',
                    style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Color(0xFFBDBDBD)),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// _StripeStatusBanner — Stripe 账户状态横幅
// =============================================================
class _StripeStatusBanner extends StatelessWidget {
  final AsyncValue<BrandStripeAccount> stripeAsync;
  final VoidCallback onManageTap;

  const _StripeStatusBanner({
    required this.stripeAsync,
    required this.onManageTap,
  });

  @override
  Widget build(BuildContext context) {
    return stripeAsync.when(
      loading: () => Container(
        height: 68,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      error: (_, __) => _buildNotConnected(context),
      data: (info) => info.isConnected
          ? _buildConnected(context, info)
          : _buildNotConnected(context),
    );
  }

  Widget _buildConnected(BuildContext context, BrandStripeAccount info) {
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
                if (info.accountEmail != null)
                  Text(
                    info.accountEmail!,
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stripe Not Connected',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  'Connect Stripe to receive brand earnings',
                  style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {},
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
}
