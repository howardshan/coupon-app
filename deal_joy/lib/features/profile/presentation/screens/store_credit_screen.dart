import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/store_credit_model.dart';
import '../../domain/providers/store_credit_provider.dart';

// Store Credit 页面：余额卡片 + 流水记录列表
class StoreCreditScreen extends ConsumerWidget {
  const StoreCreditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(storeCreditBalanceProvider);
    final transactionsAsync = ref.watch(storeCreditTransactionsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Store Credit'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          // 下拉刷新余额和流水
          ref.invalidate(storeCreditBalanceProvider);
          ref.invalidate(storeCreditTransactionsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 余额卡片 ───────────────────────────────────────────────────
            balanceAsync.when(
              data: (credit) => _BalanceCard(amount: credit.amount),
              loading: () => const _BalanceCardSkeleton(),
              error: (e, _) => _BalanceCard(amount: 0, hasError: true),
            ),

            const SizedBox(height: 24),

            // ── 流水标题 ───────────────────────────────────────────────────
            const Text(
              'Transaction History',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),

            const SizedBox(height: 12),

            // ── 流水列表 ───────────────────────────────────────────────────
            transactionsAsync.when(
              data: (transactions) {
                if (transactions.isEmpty) {
                  return const _EmptyTransactions();
                }
                return Column(
                  children: transactions
                      .map((tx) => _TransactionTile(transaction: tx))
                      .toList(),
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Failed to load transactions.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 余额卡片 ──────────────────────────────────────────────────────────────────
class _BalanceCard extends StatelessWidget {
  final double amount;
  final bool hasError;

  const _BalanceCard({required this.amount, this.hasError = false});

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available Balance',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasError ? '--' : formatter.format(amount),
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Use at checkout',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ],
      ),
    );
  }
}

// ── 余额卡片骨架屏（加载中）────────────────────────────────────────────────────
class _BalanceCardSkeleton extends StatelessWidget {
  const _BalanceCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 140,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}

// ── 空态提示 ──────────────────────────────────────────────────────────────────
class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 56,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 12),
          const Text(
            'No transactions yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Credits earned from refunds will appear here.',
            style: TextStyle(fontSize: 13, color: AppColors.textHint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── 单条流水记录 ───────────────────────────────────────────────────────────────
class _TransactionTile extends StatelessWidget {
  final StoreCreditTransaction transaction;

  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.isCredit;
    final amountColor = isCredit ? AppColors.success : AppColors.error;
    final iconData =
        isCredit ? Icons.add_circle_outline : Icons.remove_circle_outline;
    final amountText =
        '${isCredit ? '+' : ''}\$${transaction.amount.abs().toStringAsFixed(2)}';
    final dateText = DateFormat('MMM d, yyyy').format(transaction.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 图标
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: amountColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(iconData, color: amountColor, size: 18),
          ),

          const SizedBox(width: 12),

          // 描述 + 日期
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.displayLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  dateText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),

          // 金额
          Text(
            amountText,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }
}
