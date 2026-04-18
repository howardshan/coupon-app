// 已核销券退款入口：统一走 After-sales（核销后 7 天内）/ 超窗提示

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../after_sales/domain/providers/after_sales_provider.dart';
import '../../../after_sales/presentation/pages/after_sales_screen_args.dart';
import '../../data/models/order_item_model.dart';

/// 从订单/券详情对「已使用」券打开退款相关流程（不再对 used 调 create-refund）
void showUsedRefundEntry(
  BuildContext context,
  WidgetRef ref,
  OrderItemModel item,
) {
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
      builder: (sheetCtx) => _AfterSalesRefundChoiceSheet(
        parentContext: context,
        item: item,
        couponId: couponId,
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

/// 7 天售后窗：若该券已有售后单则只展示「查看状态」，避免重复提交
class _AfterSalesRefundChoiceSheet extends ConsumerStatefulWidget {
  const _AfterSalesRefundChoiceSheet({
    required this.parentContext,
    required this.item,
    required this.couponId,
  });

  final BuildContext parentContext;
  final OrderItemModel item;
  final String couponId;

  @override
  ConsumerState<_AfterSalesRefundChoiceSheet> createState() => _AfterSalesRefundChoiceSheetState();
}

class _AfterSalesRefundChoiceSheetState extends ConsumerState<_AfterSalesRefundChoiceSheet> {
  static const Duration _fetchExistingTimeout = Duration(seconds: 12);

  /// null 且 [_loadError] 为 null 表示加载中；非 null 表示已成功并可知是否已有售后单
  bool? _hasExistingForCoupon;

  /// 非 null 表示失败，展示文案 + Retry
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadExistingCase();
    });
  }

  void _retry() {
    setState(() {
      _loadError = null;
      _hasExistingForCoupon = null;
    });
    _loadExistingCase();
  }

  Future<void> _loadExistingCase() async {
    final repo = ref.read(afterSalesRepositoryProvider);
    try {
      final list = await repo
          .fetchRequests(orderId: widget.item.orderId)
          .timeout(_fetchExistingTimeout);
      final cid = widget.couponId.trim();
      final match = list.any((r) => r.couponId.trim() == cid);
      if (!mounted) return;
      setState(() {
        _hasExistingForCoupon = match;
        _loadError = null;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loadError =
            'Request timed out. Check your connection and tap Retry.';
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message.trim().isEmpty
            ? 'Could not load status. Tap Retry.'
            : e.message;
      });
    } catch (e, stack) {
      debugPrint('[after-sales] load existing case failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load status. Tap Retry.';
      });
    }
  }

  AfterSalesScreenArgs _args() {
    final i = widget.item;
    return AfterSalesScreenArgs(
      orderId: i.orderId,
      couponId: widget.couponId,
      dealTitle: i.dealTitle,
      totalAmount: i.unitPrice + i.serviceFee,
      merchantName: i.merchantName ?? i.redeemedMerchantName,
      couponCode: i.formattedCouponCode ?? i.couponCode,
      couponUsedAt: i.redeemedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasError = _loadError != null;
    final loading = !hasError && _hasExistingForCoupon == null;
    final hasCase = _hasExistingForCoupon == true;
    final parent = widget.parentContext;

    return Padding(
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
          Text(
            hasError
                ? _loadError!
                : hasCase
                    ? 'You already have an after-sales case for this voucher. Open status to review updates or escalate if needed.'
                    : 'You can submit an after-sales request within 7 days of redeeming your voucher.',
            style: TextStyle(
              fontSize: 14,
              color: hasError ? AppColors.error : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (hasError) ...[
            FilledButton(
              onPressed: _retry,
              child: const Text('Retry'),
            ),
          ] else ...[
            if (!hasCase) ...[
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  parent.push(
                    '/after-sales/${widget.item.orderId}/request',
                    extra: _args(),
                  );
                },
                child: const Text('Continue to after-sales'),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
                parent.push(
                  '/after-sales/${widget.item.orderId}',
                  extra: _args(),
                );
              },
              child: const Text('View after-sales status'),
            ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
