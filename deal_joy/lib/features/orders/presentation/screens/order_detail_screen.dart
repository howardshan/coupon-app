// 订单详情页 — 与商家端一致的分块展示（Deal / Payment / Voucher / Timeline）
// 数据来自 user-order-detail Edge Function

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../data/models/order_detail_model.dart';
import '../../domain/providers/orders_provider.dart';
import '../../../after_sales/presentation/pages/after_sales_screen_args.dart';

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
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
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

// ── 状态标签展示文案（与商家端一致）
String _statusTagLabel(String tag) {
  switch (tag) {
    case 'unused':
      return 'Paid';
    case 'used':
      return 'Redeemed';
    case 'refund_requested':
      return 'Refund Requested';
    case 'refunded':
      return 'Refunded';
    case 'refund_failed':
      return 'Refund Failed';
    case 'refund_rejected':
      return 'Refund Rejected';
    case 'expired':
      return 'Expired';
    case 'pending_refund':
      return 'Pending Refund';
    default:
      return tag.replaceAll('_', ' ').split(' ').map((e) => e.isNotEmpty ? '${e[0].toUpperCase()}${e.substring(1)}' : '').join(' ');
  }
}

Color _statusTagColor(String tag) {
  switch (tag) {
    case 'unused':
      return AppColors.info;
    case 'used':
      return AppColors.success;
    case 'refunded':
      return AppColors.warning;
    case 'refund_requested':
      return AppColors.warning;
    case 'refund_failed':
      return AppColors.error;
    case 'refund_rejected':
      return AppColors.warning;
    case 'expired':
      return AppColors.textHint;
    case 'pending_refund':
      return AppColors.warning;
    default:
      return AppColors.textHint;
  }
}

class _OrderDetailBody extends StatelessWidget {
  final OrderDetailModel detail;

  const _OrderDetailBody({required this.detail});

  @override
  Widget build(BuildContext context) {
    final amountFmt = NumberFormat.currency(symbol: '\$');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部：订单号 + 状态 Badge + 下单时间
          _buildHeader(context),
          const SizedBox(height: 12),

          // 退款说明横幅（仅已退款订单）
          if (detail.isRefunded) _buildRefundBanner(),
          if (detail.isRefunded) const SizedBox(height: 12),

          // 区块1：Deal
          _SectionCard(
            title: 'Deal',
            icon: Icons.local_offer_outlined,
            children: [
              _InfoRow(label: 'Title', value: detail.dealTitle),
              _InfoRow(label: 'Merchant', value: detail.merchantName ?? '—'),
              _InfoRow(label: 'Original Price', value: amountFmt.format(detail.dealOriginalPrice)),
              _InfoRow(
                label: 'Deal Price',
                value: amountFmt.format(detail.dealDiscountPrice),
                valueColor: AppColors.primary,
              ),
              _InfoRow(label: 'Quantity', value: '× ${detail.quantity}'),
            ],
          ),

          // 区块2：Payment
          _SectionCard(
            title: 'Payment',
            icon: Icons.credit_card_outlined,
            children: [
              _InfoRow(label: 'Total', value: amountFmt.format(detail.totalAmount), valueBold: true),
              if (detail.paymentIntentIdMasked != null)
                _InfoRow(
                  label: 'Transaction ID',
                  value: detail.paymentIntentIdMasked!,
                  monospace: true,
                ),
              if (detail.paymentStatus != null)
                _InfoRow(label: 'Payment Status', value: _capitalise(detail.paymentStatus!)),
              if (detail.refundAmount != null)
                _InfoRow(
                  label: 'Refunded Amount',
                  value: amountFmt.format(detail.refundAmount!),
                  valueColor: AppColors.warning,
                ),
            ],
          ),

          // 区块3：Voucher（有券码时展示）
          if (detail.couponCode != null)
            _SectionCard(
              title: 'Voucher',
              icon: Icons.qr_code_2_rounded,
              children: [
                _CouponCodeRow(code: detail.couponCode!),
                if (detail.couponExpiresAt != null)
                  _InfoRow(
                    label: 'Expires',
                    value: DateFormat('MMM d, yyyy').format(detail.couponExpiresAt!.toLocal()),
                  ),
                if (detail.couponStatus != null)
                  _InfoRow(label: 'Coupon Status', value: _capitalise(detail.couponStatus!)),
              ],
            ),

          // 区块4：退款原因（如有）
          if (detail.isRefunded &&
              detail.refundReason != null &&
              detail.refundReason!.isNotEmpty)
            _SectionCard(
              title: 'Refund Reason',
              icon: Icons.info_outline_rounded,
              iconColor: AppColors.warning,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    detail.refundReason!,
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),

          // 区块5：Timeline
          _SectionCard(
            title: 'Timeline',
            icon: Icons.timeline_rounded,
            children: [OrderTimelineWidget(timeline: detail.timeline)],
          ),

          // 操作按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (detail.isUnused && !detail.isExpiredByDate) ...[
                  if (detail.couponId != null)
                    AppButton(
                      label: 'View Coupon',
                      icon: Icons.qr_code_2,
                      onPressed: () => context.push('/coupon/${detail.couponId}'),
                    ),
                  if (detail.isUnused && !detail.isExpiredByDate) ...[
                    if (detail.couponId != null) const SizedBox(height: 12),
                    AppButton(
                      label: 'Request Refund',
                      icon: Icons.undo_outlined,
                      isOutlined: true,
                      color: AppColors.error,
                      onPressed: () => context.push('/refund/${detail.id}'),
                    ),
                  ],
                ],
                if (detail.isUnused && detail.isExpiredByDate && detail.couponId != null && !detail.isRefunded) ...[
                  AppButton(
                    label: 'View Coupon',
                    icon: Icons.qr_code_2,
                    isOutlined: true,
                    onPressed: () => context.push('/coupon/${detail.couponId}'),
                  ),
                ],
                if (detail.canRequestAfterSales && detail.couponId != null) ...[
                  const SizedBox(height: 12),
                  AppButton(
                    label: '申请售后',
                    icon: Icons.support_agent_outlined,
                    onPressed: () {
                      final args = AfterSalesScreenArgs(
                        orderId: detail.id,
                        couponId: detail.couponId!,
                        dealTitle: detail.dealTitle,
                        totalAmount: detail.totalAmount,
                        merchantName: detail.merchantName,
                        couponCode: detail.couponCode,
                        couponUsedAt: detail.couponUsedAt,
                      );
                      context.push('/after-sales/\${detail.id}', extra: args);
                    },
                  ),
                ],
                // 已核销且未在退款流程中，显示核销后退款入口
                if (detail.isUsed &&
                    !detail.isRefunded &&
                    detail.status != 'refund_pending_merchant' &&
                    detail.status != 'refund_pending_admin' &&
                    detail.status != 'refund_rejected') ...[
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Request Post-Use Refund',
                    icon: Icons.policy_outlined,
                    isOutlined: true,
                    color: AppColors.warning,
                    onPressed: () => context.push('/post-use-refund/${detail.id}'),
                  ),
                ],
                const SizedBox(height: 16),
                AppButton(
                  label: 'Back to Orders',
                  onPressed: () => context.go('/orders'),
                  isOutlined: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
          Text(
            detail.orderNumber,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              fontFamily: 'monospace',
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: detail.detailStatusTags
                    .map((tag) => _StatusChip(
                          label: _statusTagLabel(tag),
                          color: _statusTagColor(tag),
                        ))
                    .toList(),
              ),
              const Spacer(),
              Text(
                DateFormat('MMM d, yyyy · h:mm a').format(detail.createdAt.toLocal()),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          if (detail.detailStatusTags.contains('expired') || detail.detailStatusTags.contains('pending_refund'))
            if (detail.isUnused)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  detail.detailStatusTags.contains('expired')
                      ? 'Coupon expired; will be auto-refunded 24h after expiry.'
                      : 'Auto-refund in progress (runs hourly).',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildRefundBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.currency_exchange_rounded, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Refunded by DealJoy',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail.refundedAt != null
                      ? 'Refunded on ${DateFormat('MMM d, yyyy').format(detail.refundedAt!.toLocal())}.'
                      : 'This order was refunded.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
}

// ── 状态 Chip ─────────────────────────────────────
class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

// ── 区块卡片 ─────────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.iconColor = AppColors.primary,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Color iconColor;

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
                Icon(icon, size: 16, color: iconColor),
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

// ── 信息行 ───────────────────────────────────────
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
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.surfaceVariant),
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
              child: const Icon(Icons.copy_rounded, size: 16, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 时间线组件 ───────────────────────────────────
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
                      child: Icon(event.icon, size: 18, color: event.iconColor),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
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
                          tsFormatter.format(event.timestamp!.toLocal()),
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
