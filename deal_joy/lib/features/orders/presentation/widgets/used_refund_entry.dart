// 已核销券退款入口：24h 争议 / 7d After-sales / 超窗提示

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../after_sales/presentation/pages/after_sales_screen_args.dart';
import '../../data/models/order_item_model.dart';
import '../../domain/providers/coupons_provider.dart';

/// 从订单/券详情对「已使用」券打开退款相关流程（不再对 used 调 create-refund）
void showUsedRefundEntry(
  BuildContext context,
  WidgetRef ref,
  OrderItemModel item, {
  required VoidCallback onRefresh,
}) {
  if (!item.showRefundRequest) return;

  if (item.redeemedAt == null) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refund unavailable'),
        content: const Text(
          'We could not find the redemption time for this voucher. Please contact support.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    return;
  }

  if (item.isInDisputeRefundWindow) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _DisputeRefundSheet(
        parentContext: context,
        item: item,
        onRefresh: onRefresh,
      ),
    );
    return;
  }

  if (item.isInAfterSalesRefundWindow) {
    final couponId = item.couponId;
    if (couponId == null || couponId.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('After-sales unavailable'),
          content: const Text(
            'This voucher is not linked to a coupon record yet. Please pull to refresh or contact support.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'After-sales refund',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'The 24-hour dispute window has passed. You can still submit an after-sales '
              'request within 7 days of redemption.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push(
                  '/after-sales/${item.orderId}/request',
                  extra: AfterSalesScreenArgs(
                    orderId: item.orderId,
                    couponId: couponId,
                    dealTitle: item.dealTitle,
                    totalAmount: item.unitPrice + item.serviceFee,
                    merchantName: item.merchantName ?? item.redeemedMerchantName,
                    couponCode: item.formattedCouponCode ?? item.couponCode,
                    couponUsedAt: item.redeemedAt,
                  ),
                );
              },
              child: const Text('Continue to after-sales'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push(
                  '/after-sales/${item.orderId}',
                  extra: AfterSalesScreenArgs(
                    orderId: item.orderId,
                    couponId: couponId,
                    dealTitle: item.dealTitle,
                    totalAmount: item.unitPrice + item.serviceFee,
                    merchantName: item.merchantName ?? item.redeemedMerchantName,
                    couponCode: item.formattedCouponCode ?? item.couponCode,
                    couponUsedAt: item.redeemedAt,
                  ),
                );
              },
              child: const Text('View after-sales status'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    return;
  }

  if (item.isPastAfterSalesRefundWindow) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refund window closed'),
        content: const Text(
          'Refund and after-sales requests are only available within 7 days of using your voucher.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }
}

class _DisputeRefundSheet extends ConsumerStatefulWidget {
  const _DisputeRefundSheet({
    required this.parentContext,
    required this.item,
    required this.onRefresh,
  });

  /// 打开 bottom sheet 的页面 context，用于关闭弹窗后在主 Scaffold 上显示 SnackBar（避免被遮罩）
  final BuildContext parentContext;
  final OrderItemModel item;
  final VoidCallback onRefresh;

  @override
  ConsumerState<_DisputeRefundSheet> createState() => _DisputeRefundSheetState();
}

String _disputeErrorMessage(Object? error) {
  if (error == null) return 'Request failed. Please try again.';
  if (error is AppException) return error.message;
  return error.toString();
}

class _DisputeRefundSheetState extends ConsumerState<_DisputeRefundSheet> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textHint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Dispute refund',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Within 24 hours of redemption you can request a refund for review. '
              'If approved, the amount will be credited to Store Credit.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Please describe the issue (10–500 characters)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.length < 10) return 'Enter at least 10 characters';
                if (t.length > 500) return 'Max 500 characters';
                return null;
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting
                  ? null
                  : () async {
                      if (!(_formKey.currentState?.validate() ?? false)) return;
                      final sheetContext = context;
                      final parentContext = widget.parentContext;
                      setState(() => _submitting = true);
                      final ok = await ref.read(refundNotifierProvider.notifier).submitRefundDispute(
                            widget.item.id,
                            _controller.text.trim(),
                            couponId: widget.item.couponId,
                            orderId: widget.item.orderId,
                          );
                      final err = ref.read(refundNotifierProvider).error;
                      if (!sheetContext.mounted) return;
                      // 先关弹窗再提示，避免 SnackBar 被 bottom sheet 挡住；此处不再 setState（即将 dispose）
                      Navigator.of(sheetContext).pop();
                      if (ok) widget.onRefresh();
                      final String snackText = ok
                          ? 'Request submitted. The merchant will review it.'
                          : _disputeErrorMessage(err);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!parentContext.mounted) return;
                        ScaffoldMessenger.of(parentContext).clearSnackBars();
                        ScaffoldMessenger.of(parentContext).showSnackBar(
                          SnackBar(
                            content: Text(snackText),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: ok ? 4 : 6),
                            backgroundColor: ok ? null : AppColors.error,
                          ),
                        );
                      });
                    },
              child: _submitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit for review'),
            ),
            TextButton(
              onPressed: _submitting ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
