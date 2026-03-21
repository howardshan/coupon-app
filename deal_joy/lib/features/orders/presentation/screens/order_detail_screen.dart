// 订单详情页 — V3 重构
// 按 deal 分组展示 order_items，每张券独立展示状态 Badge + 操作按钮
// QR Code / Cancel 操作通过 Bottom Sheet 实现

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/order_detail_model.dart';
import '../../data/models/order_item_model.dart';
import '../../domain/providers/orders_provider.dart';
import '../../domain/providers/coupons_provider.dart';

class OrderDetailScreen extends ConsumerWidget {
  final String orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(userOrderDetailProvider(orderId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Order Detail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(userOrderDetailProvider(orderId)),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: detailAsync.when(
        data: (detail) => _OrderDetailBody(detail: detail),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorBody(
          onRetry: () => ref.invalidate(userOrderDetailProvider(orderId)),
          error: e,
        ),
      ),
    );
  }
}

// ── 错误占位 ──────────────────────────────────────
class _ErrorBody extends StatelessWidget {
  final VoidCallback onRetry;
  final Object error;

  const _ErrorBody({required this.onRetry, required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(
              'Failed to load order',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 客户状态 Badge 颜色 / 文案 ─────────────────────
Color _itemStatusColor(CustomerItemStatus status) => switch (status) {
      CustomerItemStatus.unused => AppColors.success,
      CustomerItemStatus.used => AppColors.info,
      CustomerItemStatus.expired => AppColors.textHint,
      CustomerItemStatus.refundPending => AppColors.warning,
      CustomerItemStatus.refundReview => AppColors.warning,
      CustomerItemStatus.refundReject => AppColors.error,
      CustomerItemStatus.refundSuccess => AppColors.textSecondary,
    };

// ── 详情页主体 ────────────────────────────────────
class _OrderDetailBody extends ConsumerWidget {
  final OrderDetailModel detail;

  const _OrderDetailBody({required this.detail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amountFmt = NumberFormat.currency(symbol: '\$');

    // V3：按 deal 分组 items（若无 items，降级到旧版展示）
    final hasV3Items = detail.items.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部：订单号 + 日期 + 总金额
          _buildHeader(context, amountFmt),
          const SizedBox(height: 12),

          // V3 按 deal 分组展示 items
          if (hasV3Items) ..._buildDealGroups(context, ref),

          // V2 降级：旧版 Deal / Payment / Voucher / Timeline 区块
          if (!hasV3Items) ...[
            _buildLegacyDealSection(amountFmt),
            _buildLegacyPaymentSection(amountFmt),
            if (detail.couponCode != null)
              _buildLegacyVoucherSection(),
          ],

          // 时间线（始终展示）
          _SectionCard(
            title: 'Timeline',
            icon: Icons.timeline_rounded,
            children: [OrderTimelineWidget(timeline: detail.timeline)],
          ),

          // 底部操作按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: OutlinedButton(
              onPressed: () => context.go('/orders'),
              child: const Text('Back to Orders'),
            ),
          ),
        ],
      ),
    );
  }

  // 顶部 Header：订单号 + 创建时间 + 总金额
  Widget _buildHeader(BuildContext context, NumberFormat amountFmt) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 订单号
          Text(
            detail.orderNumber,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              fontFamily: 'monospace',
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 下单日期
              Text(
                DateFormat('MMM d, yyyy · h:mm a')
                    .format(detail.createdAt.toLocal()),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              // 总金额
              Text(
                amountFmt.format(detail.totalAmount),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // V3：按 deal 分组展示 items
  List<Widget> _buildDealGroups(BuildContext context, WidgetRef ref) {
    // 从 detail.items 构建按 deal_id 分组的 Map（保持顺序）
    final groupMap = <String, List<OrderItemModel>>{};
    for (final item in detail.items) {
      groupMap.putIfAbsent(item.dealId, () => []).add(item);
    }

    return groupMap.entries.map((entry) {
      final dealItems = entry.value;
      return _DealGroupSection(
        dealItems: dealItems,
        onRefreshOrder: () => ref.invalidate(userOrderDetailProvider(detail.id)),
      );
    }).toList();
  }

  // V2 降级：旧版 Deal 区块
  Widget _buildLegacyDealSection(NumberFormat amountFmt) {
    return _SectionCard(
      title: 'Deal',
      icon: Icons.local_offer_outlined,
      children: [
        _InfoRow(label: 'Title', value: detail.dealTitle),
        _InfoRow(label: 'Merchant', value: detail.merchantName ?? '—'),
        _InfoRow(
          label: 'Original Price',
          value: amountFmt.format(detail.dealOriginalPrice),
        ),
        _InfoRow(
          label: 'Deal Price',
          value: amountFmt.format(detail.dealDiscountPrice),
          valueColor: AppColors.primary,
        ),
        _InfoRow(label: 'Quantity', value: '× ${detail.quantity}'),
      ],
    );
  }

  // V2 降级：旧版 Payment 区块
  Widget _buildLegacyPaymentSection(NumberFormat amountFmt) {
    return _SectionCard(
      title: 'Payment',
      icon: Icons.credit_card_outlined,
      children: [
        _InfoRow(
          label: 'Total',
          value: amountFmt.format(detail.totalAmount),
          valueBold: true,
        ),
        if (detail.paymentIntentIdMasked != null)
          _InfoRow(
            label: 'Transaction ID',
            value: detail.paymentIntentIdMasked!,
            monospace: true,
          ),
        if (detail.paymentStatus != null)
          _InfoRow(
            label: 'Payment Status',
            value: _capitalise(detail.paymentStatus!),
          ),
        if (detail.refundAmount != null)
          _InfoRow(
            label: 'Refunded Amount',
            value: amountFmt.format(detail.refundAmount!),
            valueColor: AppColors.warning,
          ),
      ],
    );
  }

  // V2 降级：旧版 Voucher 区块
  Widget _buildLegacyVoucherSection() {
    return _SectionCard(
      title: 'Voucher',
      icon: Icons.qr_code_2_rounded,
      children: [
        _CouponCodeRow(code: detail.couponCode!),
        if (detail.couponExpiresAt != null)
          _InfoRow(
            label: 'Expires',
            value: DateFormat('MMM d, yyyy')
                .format(detail.couponExpiresAt!.toLocal()),
          ),
        if (detail.couponStatus != null)
          _InfoRow(
            label: 'Coupon Status',
            value: _capitalise(detail.couponStatus!),
          ),
      ],
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
}

// ── Deal 分组区块 ─────────────────────────────────
class _DealGroupSection extends ConsumerWidget {
  final List<OrderItemModel> dealItems;
  final VoidCallback onRefreshOrder;

  const _DealGroupSection({
    required this.dealItems,
    required this.onRefreshOrder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 取该 deal 的汇总信息（所有 items 共享同一 deal）
    final firstItem = dealItems.first;
    final dealTitle = firstItem.dealTitle;
    final merchantName = firstItem.merchantName ??
        firstItem.purchasedMerchantName;
    final count = dealItems.length;

    // 小计（items 单价之和）
    final subtotal = dealItems.fold<double>(0, (s, i) => s + i.unitPrice);
    // service fee 总额
    final serviceFeeTotal =
        dealItems.fold<double>(0, (s, i) => s + i.serviceFee);

    final amountFmt = NumberFormat.currency(symbol: '\$');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Deal 组标题
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.local_offer_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dealTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                // 张数 badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count voucher${count > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 商家名
          if (merchantName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                merchantName,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),

          const Divider(height: 1),

          // 每张券
          ...dealItems.map(
            (item) => _ItemRow(
              item: item,
              onRefreshOrder: onRefreshOrder,
            ),
          ),

          const Divider(height: 1),

          // 小计 + service fee
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      'Subtotal',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      amountFmt.format(subtotal),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                if (serviceFeeTotal > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text(
                        'Service Fee',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        amountFmt.format(serviceFeeTotal),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 单张券行 ──────────────────────────────────────
class _ItemRow extends ConsumerWidget {
  final OrderItemModel item;
  final VoidCallback onRefreshOrder;

  const _ItemRow({required this.item, required this.onRefreshOrder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = _itemStatusColor(item.customerStatus);
    final statusLabel = item.customerStatus.displayLabel;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 状态 Badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
          const Spacer(),
          // 操作按钮区
          Wrap(
            spacing: 8,
            children: [
              if (item.showQrCode)
                _ActionButton(
                  label: 'QR Code',
                  icon: Icons.qr_code_2,
                  color: AppColors.primary,
                  onTap: () => _showQrCodeSheet(context, item),
                ),
              if (item.showCancel)
                _ActionButton(
                  label: 'Cancel',
                  icon: Icons.undo_outlined,
                  color: AppColors.error,
                  onTap: () => _showCancelSheet(context, ref, item),
                ),
              if (item.showRefundRequest)
                _ActionButton(
                  label: 'Refund',
                  icon: Icons.support_agent_outlined,
                  color: AppColors.warning,
                  onTap: () => _showCancelSheet(context, ref, item),
                ),
              if (item.showWriteReview)
                _ActionButton(
                  label: 'Review',
                  icon: Icons.star_border_rounded,
                  color: AppColors.accent,
                  onTap: () => context.push('/review/${item.dealId}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // 展示 QR Code Bottom Sheet
  void _showQrCodeSheet(BuildContext context, OrderItemModel item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QrCodeSheet(item: item),
    );
  }

  // 展示 Cancel / Refund Request Bottom Sheet
  void _showCancelSheet(
      BuildContext context, WidgetRef ref, OrderItemModel item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CancelSheet(
        item: item,
        onConfirm: (refundMethod) async {
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final success = await ref
              .read(refundNotifierProvider.notifier)
              .requestItemRefund(
                item.id,
                refundMethod: refundMethod,
              );
          navigator.pop(); // 关闭 Bottom Sheet
          if (success) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Refund request submitted successfully'),
                behavior: SnackBarBehavior.floating,
              ),
            );
            onRefreshOrder();
          } else {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Failed to submit refund request'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
      ),
    );
  }
}

// ── 操作按钮（小尺寸） ────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── QR Code Bottom Sheet ──────────────────────────
class _QrCodeSheet extends StatelessWidget {
  final OrderItemModel item;

  const _QrCodeSheet({required this.item});

  @override
  Widget build(BuildContext context) {
    final qrData = item.couponQrCode ?? item.couponCode ?? '';
    final formattedCode = item.formattedCouponCode;
    final expiresAt = item.couponExpiresAt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Scan to Redeem',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),

          // QR Code 图片
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: qrData.isNotEmpty
                ? QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                  )
                : const SizedBox(
                    width: 200,
                    height: 200,
                    child: Center(
                      child: Text(
                        'QR code unavailable',
                        style: TextStyle(color: AppColors.textHint),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 20),

          // 券码（带复制）
          if (formattedCode != null) ...[
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: formattedCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Coupon code copied'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      formattedCode,
                      style: const TextStyle(
                        fontSize: 18,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.copy_rounded,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Deal 标题 + 商家 + 过期日期
          Text(
            item.dealTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (item.merchantName != null ||
              item.purchasedMerchantName != null) ...[
            const SizedBox(height: 4),
            Text(
              item.merchantName ?? item.purchasedMerchantName!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (expiresAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Expires ${DateFormat('MMM d, yyyy').format(expiresAt.toLocal())}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textHint,
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Cancel / Refund Bottom Sheet ──────────────────
class _CancelSheet extends ConsumerStatefulWidget {
  final OrderItemModel item;
  final Future<void> Function(String refundMethod) onConfirm;

  const _CancelSheet({required this.item, required this.onConfirm});

  @override
  ConsumerState<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends ConsumerState<_CancelSheet> {
  // 退款方式选择（默认 store_credit）
  String _selectedMethod = 'store_credit';
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final isCancel = widget.item.showCancel;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 拖拽指示条
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

          // 标题
          Text(
            isCancel ? 'Cancel & Refund' : 'Request Refund',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isCancel
                ? 'Choose how you would like to receive your refund.'
                : 'You used this voucher. Choose a refund method.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),

          // 选项1：Store Credit（推荐）
          _RefundMethodOption(
            selected: _selectedMethod == 'store_credit',
            title: 'Store Credit',
            subtitle: isCancel
                ? 'Full amount incl. service fee · Instant'
                : 'Processed within 1-2 business days',
            badge: 'Recommended',
            badgeColor: AppColors.success,
            onTap: () => setState(() => _selectedMethod = 'store_credit'),
          ),
          const SizedBox(height: 12),

          // 选项2：Original Payment
          _RefundMethodOption(
            selected: _selectedMethod == 'original_payment',
            title: 'Original Payment',
            subtitle: isCancel
                ? 'Excluding service fee · 5-10 business days'
                : '5-10 business days to original card',
            onTap: () =>
                setState(() => _selectedMethod = 'original_payment'),
          ),
          const SizedBox(height: 24),

          // 确认按钮
          ElevatedButton(
            onPressed: _isSubmitting
                ? null
                : () async {
                    setState(() => _isSubmitting = true);
                    await widget.onConfirm(_selectedMethod);
                    if (mounted) {
                      setState(() => _isSubmitting = false);
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Confirm',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// 退款方式选项卡
class _RefundMethodOption extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _RefundMethodOption({
    required this.selected,
    required this.title,
    required this.subtitle,
    this.badge,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.textHint.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // 单选圆圈
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.textHint,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            // 文案
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (badgeColor ?? AppColors.success)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: badgeColor ?? AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 区块卡片 ──────────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 信息行 ────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueBold = false,
    this.monospace = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool valueBold;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    valueBold ? FontWeight.w700 : FontWeight.w500,
                color: valueColor ?? AppColors.textPrimary,
                fontFamily: monospace ? 'monospace' : null,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 券码行（带复制） ──────────────────────────────
class _CouponCodeRow extends StatelessWidget {
  const _CouponCodeRow({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  letterSpacing: 1,
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Coupon code copied'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Icon(
                Icons.copy_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 时间线组件（保留原版逻辑） ──────────────────────
class OrderTimelineWidget extends StatelessWidget {
  const OrderTimelineWidget({super.key, required this.timeline});

  final OrderTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final events = timeline.events;
    if (events.isEmpty) return const SizedBox.shrink();

    final tsFormatter = DateFormat('MMM d, yyyy · h:mm a');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(events.length, (index) {
        final event = events[index];
        final isLast = index == events.length - 1;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: event.completed
                            ? event.iconColor.withValues(alpha: 0.12)
                            : AppColors.surfaceVariant,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: event.completed
                              ? event.iconColor.withValues(alpha: 0.3)
                              : AppColors.textHint.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(event.icon,
                          size: 18, color: event.iconColor),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin:
                              const EdgeInsets.symmetric(vertical: 4),
                          color: AppColors.textHint.withValues(alpha: 0.3),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.displayTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (event.timestamp != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          tsFormatter
                              .format(event.timestamp!.toLocal()),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
