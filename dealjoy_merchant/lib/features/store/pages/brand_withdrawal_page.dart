// 品牌提现页面
// 展示: 可提现余额 / 提现操作 / 提现记录列表

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/brand_earnings_data.dart';
import '../providers/brand_earnings_provider.dart';

// =============================================================
// BrandWithdrawalPage — 品牌提现页面
// =============================================================
class BrandWithdrawalPage extends ConsumerWidget {
  const BrandWithdrawalPage({super.key});

  static const _orange = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(brandBalanceProvider);
    final historyAsync = ref.watch(brandWithdrawalHistoryProvider);

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
          'Brand Withdrawal',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: _orange,
        onRefresh: () async {
          ref.invalidate(brandBalanceProvider);
          ref.invalidate(brandWithdrawalHistoryProvider);
          await Future.wait([
            ref.read(brandBalanceProvider.future),
            ref.read(brandWithdrawalHistoryProvider.future),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 余额卡片
            _BalanceCard(balanceAsync: balanceAsync),
            const SizedBox(height: 16),

            // 提现按钮
            _WithdrawButton(balanceAsync: balanceAsync),
            const SizedBox(height: 24),

            // 提现记录标题
            const Text(
              'Withdrawal History',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 12),

            // 提现记录列表
            _WithdrawalHistoryList(historyAsync: historyAsync),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// 余额卡片
// =============================================================
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balanceAsync});
  final AsyncValue<BrandBalance> balanceAsync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B35), Color(0xFFFF8F5E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6B35).withAlpha(40),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: balanceAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
        error: (e, _) => Text(
          'Failed to load balance',
          style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 14),
        ),
        data: (balance) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available Balance',
              style: TextStyle(
                color: Colors.white.withAlpha(220),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '\$${balance.availableBalance.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _balanceItem(
                  'Pending',
                  '\$${balance.pendingSettlement.toStringAsFixed(2)}',
                ),
                const SizedBox(width: 32),
                _balanceItem(
                  'Total Withdrawn',
                  '\$${balance.totalWithdrawn.toStringAsFixed(2)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _balanceItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// =============================================================
// 提现按钮
// =============================================================
class _WithdrawButton extends ConsumerWidget {
  const _WithdrawButton({required this.balanceAsync});
  final AsyncValue<BrandBalance> balanceAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = balanceAsync.valueOrNull;
    final canWithdraw = balance != null && balance.availableBalance >= 10;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: canWithdraw
            ? () => _showWithdrawDialog(context, ref, balance)
            : null,
        icon: const Icon(Icons.account_balance_wallet_outlined, size: 20),
        label: Text(
          canWithdraw
              ? 'Withdraw Funds'
              : (balance != null
                  ? 'Minimum \$10.00 required'
                  : 'Loading...'),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: BrandWithdrawalPage._orange,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE0E0E0),
          disabledForegroundColor: const Color(0xFF999999),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Future<void> _showWithdrawDialog(
    BuildContext context,
    WidgetRef ref,
    BrandBalance balance,
  ) async {
    final amountCtrl = TextEditingController(
      text: balance.availableBalance.toStringAsFixed(2),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Withdrawal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available: \$${balance.availableBalance.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 14, color: Color(0xFF757575)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Funds will be transferred to your linked bank account within 2-3 business days.',
              style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: BrandWithdrawalPage._orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final amount = double.tryParse(amountCtrl.text);
      if (amount == null || amount < 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Minimum withdrawal amount is \$10.00'),
            backgroundColor: Colors.red,
          ),
        );
        amountCtrl.dispose();
        return;
      }
      if (amount > balance.availableBalance) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Amount exceeds available balance'),
            backgroundColor: Colors.red,
          ),
        );
        amountCtrl.dispose();
        return;
      }

      try {
        final service = ref.read(brandEarningsServiceProvider);
        await service.requestWithdrawal(amount);
        ref.invalidate(brandBalanceProvider);
        ref.invalidate(brandWithdrawalHistoryProvider);
        await ref.read(brandBalanceProvider.future);
        await ref.read(brandWithdrawalHistoryProvider.future);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Withdrawal requested successfully!'),
              backgroundColor: Color(0xFF2E7D32),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Withdrawal failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
    amountCtrl.dispose();
  }
}

// =============================================================
// 提现记录列表
// =============================================================
class _WithdrawalHistoryList extends StatelessWidget {
  const _WithdrawalHistoryList({required this.historyAsync});
  final AsyncValue<List<BrandWithdrawalRecord>> historyAsync;

  @override
  Widget build(BuildContext context) {
    return historyAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => Center(
        child: Text(
          'Failed to load history',
          style: TextStyle(color: Colors.red[400]),
        ),
      ),
      data: (records) {
        if (records.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: const Column(
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 40, color: Color(0xFFBDBDBD)),
                SizedBox(height: 8),
                Text(
                  'No withdrawal records yet',
                  style: TextStyle(fontSize: 14, color: Color(0xFF999999)),
                ),
              ],
            ),
          );
        }
        return Column(
          children:
              records.map((r) => _WithdrawalTile(record: r)).toList(),
        );
      },
    );
  }
}

// 单条提现记录
class _WithdrawalTile extends StatelessWidget {
  const _WithdrawalTile({required this.record});
  final BrandWithdrawalRecord record;

  @override
  Widget build(BuildContext context) {
    final statusColor = Color(record.statusColorValue);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              record.status == 'completed'
                  ? Icons.check_circle_outline
                  : record.status == 'failed'
                      ? Icons.error_outline
                      : Icons.hourglass_empty,
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '\$${record.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${record.requestedAt.month}/${record.requestedAt.day}/${record.requestedAt.year}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF999999),
                  ),
                ),
                if (record.failureReason != null &&
                    record.failureReason!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    record.failureReason!,
                    style: TextStyle(fontSize: 11, color: Colors.red.shade400),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              record.statusLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
