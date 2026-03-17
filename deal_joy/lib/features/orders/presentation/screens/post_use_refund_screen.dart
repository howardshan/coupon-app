// 核销后退款申请页（Task 13）
// 用户核销后 24h 内可发起退款申请，走商家审批流程
// 调用 submit-refund-request Edge Function

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../domain/providers/coupons_provider.dart';
import '../../domain/providers/orders_provider.dart';

class PostUseRefundScreen extends ConsumerStatefulWidget {
  final String orderId;

  const PostUseRefundScreen({super.key, required this.orderId});

  @override
  ConsumerState<PostUseRefundScreen> createState() => _PostUseRefundScreenState();
}

class _PostUseRefundScreenState extends ConsumerState<PostUseRefundScreen> {
  final _reasonController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(userOrderDetailProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Request Refund')),
      body: detailAsync.when(
        data: (detail) {
          // 已在审批中或已完成退款，展示只读状态页
          if (detail.status == 'refund_pending_merchant' ||
              detail.status == 'refund_pending_admin') {
            return _PendingApprovalStatus(totalAmount: detail.totalAmount);
          }
          if (detail.status == 'refunded') {
            return _RefundedStatus(totalAmount: detail.totalAmount);
          }
          if (detail.status == 'refund_rejected') {
            return _RejectedStatus(onBack: () => context.go('/orders'));
          }
          // 非 used 状态不允许走此流程
          if (detail.status != 'used') {
            return _NotEligible(status: detail.status);
          }
          return _buildForm(context, detail.dealTitle, detail.totalAmount, detail.merchantName);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    String dealTitle,
    double totalAmount,
    String? merchantName,
  ) {
    final amountFmt = NumberFormat.currency(symbol: '\$');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 订单摘要卡片
            Container(
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
                          dealTitle,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (merchantName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            merchantName,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    amountFmt.format(totalAmount),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 审批说明横幅
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppColors.info),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Post-Use Refund Requires Approval',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.info,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Since this coupon has been redeemed, your refund request will be reviewed by the merchant. '
                          'If the merchant rejects it, DealJoy admin will arbitrate. '
                          'This option is available within 24 hours of redemption.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 退款金额
            Text(
              'Refund Amount',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      color: AppColors.success, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    amountFmt.format(totalAmount),
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

            // 退款原因（必填）
            Text(
              'Reason for Refund',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _reasonController,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText:
                    'Please describe the issue in detail (e.g., food was unsatisfactory, service was poor)',
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: AppColors.textHint.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.error, width: 1.5),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.error, width: 1.5),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please provide a reason for your refund request';
                }
                if (v.trim().length < 10) {
                  return 'Reason must be at least 10 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),

            // 提交按钮
            AppButton(
              label: 'Submit Refund Request',
              icon: Icons.send_outlined,
              color: AppColors.error,
              isLoading: _isSubmitting,
              onPressed: _isSubmitting ? null : _submit,
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
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final success = await ref
        .read(refundNotifierProvider.notifier)
        .submitPostUseRefundRequest(
          orderId: widget.orderId,
          reason: _reasonController.text.trim(),
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Refund request submitted. The merchant will review it within 24 hours.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop();
    } else {
      final error = ref.read(refundNotifierProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

// ── 审批中状态 ──────────────────────────────────
class _PendingApprovalStatus extends StatelessWidget {
  final double totalAmount;

  const _PendingApprovalStatus({required this.totalAmount});

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
              'Refund Under Review',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your refund request has been submitted and is awaiting merchant review. '
              'You will be notified of the outcome.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
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

// ── 已退款状态 ──────────────────────────────────
class _RefundedStatus extends StatelessWidget {
  final double totalAmount;

  const _RefundedStatus({required this.totalAmount});

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
              'Refund Approved',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '\$${totalAmount.toStringAsFixed(2)} will be refunded to your original payment method.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 15),
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

// ── 被拒绝状态 ──────────────────────────────────
class _RejectedStatus extends StatelessWidget {
  final VoidCallback onBack;

  const _RejectedStatus({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cancel_outlined, size: 80, color: AppColors.error),
            const SizedBox(height: 16),
            const Text(
              'Refund Rejected',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your refund request was not approved by DealJoy. '
              'Please contact support if you have questions.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Back to Orders',
              onPressed: onBack,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 不符合条件状态 ─────────────────────────────
class _NotEligible extends StatelessWidget {
  final String status;

  const _NotEligible({required this.status});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block, size: 80, color: AppColors.textHint),
            const SizedBox(height: 16),
            const Text(
              'Not Eligible',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              status == 'unused'
                  ? 'This coupon has not been redeemed yet. Use the standard refund option.'
                  : 'This order is not eligible for a post-use refund.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 15),
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
