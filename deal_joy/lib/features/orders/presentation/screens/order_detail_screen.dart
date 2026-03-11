// 订单详情页 — 展示订单完整信息，按状态显示不同操作与说明

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../data/models/order_model.dart';
import '../../domain/providers/orders_provider.dart';

class OrderDetailScreen extends ConsumerWidget {
  final String orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Order Detail')),
      body: orderAsync.when(
        data: (order) => _OrderDetailBody(order: order),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
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
                  e.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(orderDetailProvider(orderId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderDetailBody extends StatelessWidget {
  final OrderModel order;

  const _OrderDetailBody({required this.order});

  /// 与订单列表一致：已退款优先显示 REFUNDED，再按过期/其他状态
  static String _displayStatus(OrderModel order) {
    if (order.status == 'refunded') return 'refunded';
    if (order.isExpired) return 'expired';
    if (order.isRefundFailed) return 'refund_failed';
    if (order.isUnused && order.isExpiredByDate) return 'expired';
    return order.status;
  }

  static Color _statusColor(String status) => switch (status) {
        'unused' => AppColors.info,
        'used' => AppColors.success,
        'refunded' => AppColors.textSecondary,
        'refund_requested' => AppColors.warning,
        'refund_failed' => AppColors.error,
        'expired' => AppColors.textHint,
        _ => AppColors.textHint,
      };

  @override
  Widget build(BuildContext context) {
    final displayStatus = _displayStatus(order);
    final deal = order.deal;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 状态 Banner
          _StatusBanner(order: order, displayStatus: displayStatus),
          const SizedBox(height: 20),

          // 订单信息卡片（始终展示）
          _OrderInfoCard(order: order),
          const SizedBox(height: 16),

          // 按状态展示说明与操作
          if (order.isRefunded) _RefundedSection(order: order),
          if (order.isRefundFailed) _RefundFailedSection(order: order),
          if (order.isRefundRejected) _RefundRejectedSection(order: order),
          if (order.isRefundRequested) _ProcessingSection(order: order),
          if (order.isUnused && !order.isExpiredByDate) _UnusedSection(order: order),
          if (order.isUnused && order.isExpiredByDate) _ExpiredSection(order: order),
          if (order.isUsed) _UsedSection(order: order),
          if (order.isExpired) _ExpiredSection(order: order),

          const SizedBox(height: 24),
          AppButton(
            label: 'Back to Orders',
            onPressed: () => context.go('/orders'),
            isOutlined: true,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── 状态 Banner ─────────────────────────────────
class _StatusBanner extends StatelessWidget {
  final OrderModel order;
  final String displayStatus;

  const _StatusBanner({required this.order, required this.displayStatus});

  @override
  Widget build(BuildContext context) {
    final color = _OrderDetailBody._statusColor(displayStatus);
    final label = displayStatus.replaceAll('_', ' ').toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }
}

// ── 订单信息卡片 ─────────────────────────────────
class _OrderInfoCard extends StatelessWidget {
  final OrderModel order;

  const _OrderInfoCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final deal = order.deal;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: deal?.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: deal!.imageUrl!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 80,
                        height: 80,
                        color: AppColors.surfaceVariant,
                        child: const Icon(Icons.restaurant, color: AppColors.textHint),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (deal?.merchantName != null)
                      Text(
                        deal!.merchantName!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      deal?.title ?? 'Deal',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '\$${order.totalAmount.toStringAsFixed(2)} · Qty ${order.quantity}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (order.orderNumber != null && order.orderNumber!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Order #${order.orderNumber}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Placed',
            value: DateFormat('MMM d, yyyy \'at\' h:mm a').format(order.createdAt.toLocal()),
          ),
          if (order.refundedAt != null) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.currency_exchange,
              label: 'Refunded',
              value: DateFormat('MMM d, yyyy').format(order.refundedAt!.toLocal()),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── 已退款说明 ───────────────────────────────────
class _RefundedSection extends StatelessWidget {
  final OrderModel order;

  const _RefundedSection({required this.order});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.success, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '\$${order.totalAmount.toStringAsFixed(2)} has been refunded to your original payment method.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 退款失败说明 ───────────────────────────────────
class _RefundFailedSection extends StatelessWidget {
  final OrderModel order;

  const _RefundFailedSection({required this.order});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'We could not process your refund. Please contact support.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 退款被拒说明 ───────────────────────────────────
class _RefundRejectedSection extends StatelessWidget {
  final OrderModel order;

  const _RefundRejectedSection({required this.order});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          const Icon(Icons.cancel_outlined, color: AppColors.warning, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your refund request was not approved. This order remains valid.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 处理中说明 ───────────────────────────────────
class _ProcessingSection extends StatelessWidget {
  final OrderModel order;

  const _ProcessingSection({required this.order});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          const Icon(Icons.hourglass_empty, color: AppColors.warning, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your refund is being processed. You will be notified once it is complete.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 未使用且未过期：View Coupon + Request Refund ───
class _UnusedSection extends StatelessWidget {
  final OrderModel order;

  const _UnusedSection({required this.order});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (order.couponId != null)
            AppButton(
              label: 'View Coupon',
              icon: Icons.qr_code_2,
              onPressed: () => context.push('/coupon/${order.couponId}'),
            ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Request Refund',
            icon: Icons.undo_outlined,
            isOutlined: true,
            color: AppColors.error,
            onPressed: () => context.push('/refund/${order.id}'),
          ),
        ],
      ),
    );
  }
}

// ── 已过期（未使用且券过期）说明 + View Coupon ─────
class _ExpiredSection extends StatelessWidget {
  final OrderModel order;

  const _ExpiredSection({required this.order});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.timer_off_outlined, color: AppColors.textHint, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  order.isRefunded
                      ? 'This order was refunded.'
                      : 'This order has expired. Unused coupons are automatically refunded within 24 hours.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          if (order.couponId != null && !order.isRefunded) ...[
            const SizedBox(height: 12),
            AppButton(
              label: 'View Coupon',
              icon: Icons.qr_code_2,
              isOutlined: true,
              onPressed: () => context.push('/coupon/${order.couponId}'),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 已使用说明 ───────────────────────────────────
class _UsedSection extends StatelessWidget {
  final OrderModel order;

  const _UsedSection({required this.order});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.success, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This order has been used.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
