// 交易明细行组件
// 展示单笔交易：订单号 / 金额 / 平台手续费 / 商家实收 / 状态 / 时间

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/earnings_data.dart';

// =============================================================
// TransactionTile — 单笔交易明细行
// =============================================================
class TransactionTile extends StatelessWidget {
  final EarningsTransaction transaction;

  /// 是否显示底部分割线（列表中间的条目使用）
  final bool showDivider;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧：状态图标
              _StatusIcon(status: transaction.status),
              const SizedBox(width: 12),
              // 中间：订单号 + 时间
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.shortOrderId,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMM d, yyyy · HH:mm').format(transaction.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              // 右侧：金额明细列
              _AmountColumn(transaction: transaction),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 16 + 32 + 12, // 与内容对齐
            color: Colors.grey.shade100,
          ),
      ],
    );
  }
}

// =============================================================
// _StatusIcon — 订单状态图标（彩色圆形）
// =============================================================
class _StatusIcon extends StatelessWidget {
  final String status;

  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _resolveStyle(status);

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withAlpha(26), // ~10% 背景
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }

  /// 根据状态返回颜色和图标
  (Color, IconData) _resolveStyle(String status) {
    switch (status) {
      case 'used':
        return (const Color(0xFF4CAF50), Icons.check_circle_outline); // 绿色：已核销
      case 'unused':
        return (const Color(0xFFFF9800), Icons.access_time_outlined);  // 橙色：持有中
      case 'refunded':
        return (const Color(0xFFF44336), Icons.reply_outlined);         // 红色：已退款
      case 'refund_requested':
        return (const Color(0xFFFF5722), Icons.hourglass_empty);        // 深橙：退款中
      case 'expired':
        return (Colors.grey, Icons.timer_off_outlined);                  // 灰色：已过期
      default:
        return (Colors.grey, Icons.help_outline);
    }
  }
}

// =============================================================
// _AmountColumn — 右侧金额明细（三行）
// =============================================================
class _AmountColumn extends StatelessWidget {
  final EarningsTransaction transaction;

  const _AmountColumn({required this.transaction});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 原始金额（较大字体）
        Text(
          '\$${transaction.amount.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 2),
        // 平台抽成 + 费率标签
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Platform: \$${transaction.platformFee.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(width: 4),
            // 费率标签："Free" 或 "10%"
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: transaction.platformFeeRate == 0
                    ? const Color(0xFF4CAF50).withAlpha(26)
                    : Colors.grey.withAlpha(26),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                transaction.rateLabel,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: transaction.platformFeeRate == 0
                      ? const Color(0xFF4CAF50)
                      : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
        // 品牌佣金（仅 brandFee > 0 时显示）
        if (transaction.brandFee > 0) ...[
          const SizedBox(height: 1),
          Text(
            'Brand: \$${transaction.brandFee.toStringAsFixed(2)}  ${(transaction.brandFeeRate * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade400,
            ),
          ),
        ],
        // Stripe 手续费（免费期内不显示）
        if (transaction.stripeFee > 0) ...[
          const SizedBox(height: 1),
          Text(
            'Stripe: \$${transaction.stripeFee.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade400,
            ),
          ),
        ],
        // Tax 代收（仅 tax > 0 时显示，老订单隐藏）
        if (transaction.taxAmount > 0) ...[
          const SizedBox(height: 1),
          Text(
            'Tax: \$${transaction.taxAmount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade400,
            ),
          ),
        ],
        const SizedBox(height: 2),
        // 商家实收（绿色）
        Text(
          'Net: \$${transaction.netAmount.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF4CAF50),
          ),
        ),
        const SizedBox(height: 4),
        // 状态标签
        _StatusBadge(status: transaction.status, displayStatus: transaction.displayStatus),
      ],
    );
  }
}

// =============================================================
// _StatusBadge — 状态标签（小圆角 badge）
// =============================================================
class _StatusBadge extends StatelessWidget {
  final String status;
  final String displayStatus;

  const _StatusBadge({required this.status, required this.displayStatus});

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(26), // ~10% 背景
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(77), width: 0.5), // ~30%
      ),
      child: Text(
        displayStatus,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Color _resolveColor(String status) {
    switch (status) {
      case 'used':              return const Color(0xFF4CAF50);
      case 'unused':            return const Color(0xFFFF9800);
      case 'refunded':          return const Color(0xFFF44336);
      case 'refund_requested':  return const Color(0xFFFF5722);
      case 'expired':           return Colors.grey;
      default:                  return Colors.grey;
    }
  }
}

// =============================================================
// TransactionTotalsRow — 合计行（列表底部）
// =============================================================
class TransactionTotalsRow extends StatelessWidget {
  final double totalAmount;
  final double totalTaxAmount;
  final double totalPlatformFee;
  final double totalStripeFee;
  final double totalNetAmount;
  final int orderCount;

  const TransactionTotalsRow({
    super.key,
    required this.totalAmount,
    this.totalTaxAmount = 0.0,
    required this.totalPlatformFee,
    required this.totalStripeFee,
    required this.totalNetAmount,
    required this.orderCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B35).withAlpha(13), // 品牌橙浅色背景
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFFF6B35).withAlpha(51), // ~20%
        ),
      ),
      child: Row(
        children: [
          // 左侧：汇总文案
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Summary ($orderCount orders)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Platform: \$${totalPlatformFee.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                if (totalStripeFee > 0)
                  Text(
                    'Stripe fee: \$${totalStripeFee.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                if (totalTaxAmount > 0)
                  Text(
                    'Tax: \$${totalTaxAmount.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          // 右侧：总金额 + 实收
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Net: \$${totalNetAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4CAF50),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
