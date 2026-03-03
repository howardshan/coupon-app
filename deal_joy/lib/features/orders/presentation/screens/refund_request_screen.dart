// 退款申请页 — 显示退款金额、退回方式、预计到账时间，确认后发起退款
// 需求 7.1.1: 弹窗+退款金额+退回方式+"Confirm Refund"/"Cancel"
// 需求 7.1.3: Processing→Refunded→Failed + 预计到账时间

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../data/models/order_model.dart';
import '../../domain/providers/coupons_provider.dart';
import '../../domain/providers/orders_provider.dart';

class RefundRequestScreen extends ConsumerStatefulWidget {
  final String orderId;

  const RefundRequestScreen({super.key, required this.orderId});

  @override
  ConsumerState<RefundRequestScreen> createState() =>
      _RefundRequestScreenState();
}

class _RefundRequestScreenState extends ConsumerState<RefundRequestScreen> {
  String? _selectedReason;
  bool _isSubmitting = false;

  static const _refundReasons = [
    'Changed my mind',
    'Found a better deal',
    'Bought by mistake',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Request Refund')),
      body: orderAsync.when(
        data: (order) => _buildBody(context, order),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildBody(BuildContext context, OrderModel order) {
    // 已退款或已申请退款的订单
    if (order.isRefunded) {
      return _RefundedStatus(order: order);
    }
    if (order.isRefundRequested) {
      return _ProcessingStatus(order: order);
    }
    // 不可退款
    if (!order.canRefund) {
      return _CannotRefund(order: order);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 订单摘要
          _OrderSummaryCard(order: order),
          const SizedBox(height: 24),

          // 退款金额
          _SectionTitle(title: 'Refund Amount'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    color: AppColors.success, size: 28),
                const SizedBox(width: 12),
                Text(
                  '\$${order.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Full Refund',
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 退回方式
          _SectionTitle(title: 'Refund To'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.credit_card, color: AppColors.textSecondary),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Original Payment Method',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Refund will be returned to the card or payment method used for this purchase.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 预计到账时间
          _SectionTitle(title: 'Estimated Arrival'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                _EstimateRow(
                  icon: Icons.phone_iphone,
                  method: 'Apple Pay / Google Pay',
                  time: '1-3 business days',
                ),
                Divider(height: 20),
                _EstimateRow(
                  icon: Icons.credit_card,
                  method: 'Credit / Debit Card',
                  time: '3-5 business days',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 退款原因（可选）
          _SectionTitle(title: 'Reason (optional)'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _refundReasons
                .map((reason) => ChoiceChip(
                      label: Text(reason),
                      selected: _selectedReason == reason,
                      onSelected: (selected) {
                        setState(
                            () => _selectedReason = selected ? reason : null);
                      },
                      selectedColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: _selectedReason == reason
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontWeight: _selectedReason == reason
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),

          // 退款规则
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.info.withValues(alpha: 0.2)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.info),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Only unused coupons can be refunded. Used, expired, or gifted coupons are not eligible for refund.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // 操作按钮
          AppButton(
            label: 'Confirm Refund',
            icon: Icons.undo_outlined,
            color: AppColors.error,
            isLoading: _isSubmitting,
            onPressed: _isSubmitting ? null : () => _submitRefund(order),
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Cancel',
            isOutlined: true,
            onPressed: () => context.pop(),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _submitRefund(OrderModel order) async {
    setState(() => _isSubmitting = true);

    final success = await ref
        .read(refundNotifierProvider.notifier)
        .requestRefundByOrderId(
          order.id,
          reason: _selectedReason,
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refund requested successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop();
    } else {
      final error = ref.read(refundNotifierProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Refund failed: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

// ── 订单摘要卡片 ────────────────────────────────
class _OrderSummaryCard extends StatelessWidget {
  final OrderModel order;

  const _OrderSummaryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.deal?.title ?? 'Order',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Qty: ${order.quantity}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '\$${order.totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 预计到账时间行 ────────────────────────────────
class _EstimateRow extends StatelessWidget {
  final IconData icon;
  final String method;
  final String time;

  const _EstimateRow({
    required this.icon,
    required this.method,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(method,
              style: const TextStyle(fontSize: 14)),
        ),
        Text(
          time,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Section 标题 ─────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(color: AppColors.textSecondary),
    );
  }
}

// ── 已退款状态 ───────────────────────────────────
class _RefundedStatus extends StatelessWidget {
  final OrderModel order;

  const _RefundedStatus({required this.order});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 80, color: AppColors.success),
            const SizedBox(height: 16),
            const Text(
              'Refund Completed',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '\$${order.totalAmount.toStringAsFixed(2)} has been refunded to your original payment method.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Back to Orders',
              onPressed: () => context.go('/orders'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 处理中状态 ───────────────────────────────────
class _ProcessingStatus extends StatelessWidget {
  final OrderModel order;

  const _ProcessingStatus({required this.order});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Refund Processing',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your refund of \$${order.totalAmount.toStringAsFixed(2)} is being processed. You will be notified once it is complete.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 16),
            const _EstimateRow(
              icon: Icons.phone_iphone,
              method: 'Apple Pay / Google Pay',
              time: '1-3 business days',
            ),
            const SizedBox(height: 8),
            const _EstimateRow(
              icon: Icons.credit_card,
              method: 'Credit / Debit Card',
              time: '3-5 business days',
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Back to Orders',
              onPressed: () => context.go('/orders'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 不可退款状态 ──────────────────────────────────
class _CannotRefund extends StatelessWidget {
  final OrderModel order;

  const _CannotRefund({required this.order});

  @override
  Widget build(BuildContext context) {
    String reason;
    if (order.isUsed) {
      reason = 'This coupon has already been used and cannot be refunded.';
    } else if (order.isExpired) {
      reason =
          'Expired coupons are automatically refunded within 24 hours. Please check your payment method.';
    } else {
      reason = 'This order is not eligible for a refund.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block, size: 80, color: AppColors.textHint),
            const SizedBox(height: 16),
            const Text(
              'Refund Not Available',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Back to Orders',
              onPressed: () => context.go('/orders'),
            ),
          ],
        ),
      ),
    );
  }
}
