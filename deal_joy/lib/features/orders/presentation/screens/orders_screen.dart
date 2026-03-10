import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/order_model.dart';
import '../../domain/providers/orders_provider.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(userOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: ordersAsync.when(
        data: (orders) => orders.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 72,
                      color: AppColors.textHint,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No orders yet',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(userOrdersProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _OrderCard(order: orders[i]),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderModel order;

  const _OrderCard({required this.order});

  Color _statusColor(String status) => switch (status) {
    'unused' => AppColors.info,
    'used' => AppColors.success,
    'refunded' => AppColors.textSecondary,
    'refund_requested' => AppColors.warning,
    'refund_failed' => AppColors.error,
    'expired' => AppColors.textHint,
    _ => AppColors.textHint,
  };

  /// 展示用状态：未使用但券已按时间过期时显示为 expired
  String get _displayStatus {
    if (order.isExpired) return 'expired';
    if (order.isRefundFailed) return 'refund_failed';
    if (order.isUnused && order.isExpiredByDate) return 'expired';
    return order.status;
  }

  @override
  Widget build(BuildContext context) {
    final deal = order.deal;
    final displayStatus = _displayStatus;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: order.isUnused
            ? () => context.push('/coupon/${order.couponId}')
            : order.isRefundRequested || order.isRefunded || order.isRefundFailed || order.isRefundRejected
            ? () => context.push('/refund/${order.id}')
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Deal image
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: deal?.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: deal!.imageUrl!,
                        width: 70,
                        height: 70,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 70,
                        height: 70,
                        color: AppColors.surfaceVariant,
                        child: const Icon(
                          Icons.restaurant,
                          color: AppColors.textHint,
                        ),
                      ),
              ),
              const SizedBox(width: 12),

              // Info
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
                    Text(
                      deal?.title ?? 'Deal',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$${order.totalAmount.toStringAsFixed(2)} · Qty ${order.quantity}${order.orderNumber != null && order.orderNumber!.isNotEmpty ? ' · #${order.orderNumber}' : ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Status badge + actions
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(displayStatus).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      displayStatus.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(
                        color: _statusColor(displayStatus),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (order.isUnused && !order.isExpiredByDate) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.qr_code_2,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        // 退款快捷入口
                        GestureDetector(
                          onTap: () => context.push('/refund/${order.id}'),
                          child: const Icon(
                            Icons.undo_outlined,
                            color: AppColors.error,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
