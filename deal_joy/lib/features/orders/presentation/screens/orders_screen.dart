// 订单列表页 — V3 适配，展示 order_items 摘要
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/order_item_model.dart';
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

  // 计算 V3 items 的摘要文案，如 "3 vouchers · 2 deals"
  String _buildItemsSummary() {
    final items = order.items;
    if (items.isEmpty) {
      // 旧版 order 无 items，降级展示数量
      final qty = order.quantity ?? 1;
      return '$qty voucher${qty > 1 ? 's' : ''}';
    }
    final totalVouchers = items.length;
    final dealCount = order.itemsByDeal.length;
    final voucherStr = '$totalVouchers voucher${totalVouchers > 1 ? 's' : ''}';
    if (dealCount > 1) {
      return '$voucherStr · $dealCount deals';
    }
    return voucherStr;
  }

  // 从 V3 items 中取第一个 deal 的图片（降级到旧版 deal 图）
  String? _firstImageUrl() {
    if (order.items.isNotEmpty) {
      return order.items.first.dealImageUrl;
    }
    return order.deal?.imageUrl;
  }

  // 从 V3 items 中取第一个 deal 标题（降级到旧版 deal 标题）
  String _dealTitle() {
    if (order.items.isNotEmpty) {
      return order.items.first.dealTitle;
    }
    return order.deal?.title ?? 'Order';
  }

  // 从 V3 items 中取商家名（降级到旧版）
  String? _merchantName() {
    if (order.items.isNotEmpty) {
      return order.items.first.merchantName ??
          order.items.first.purchasedMerchantName;
    }
    return order.deal?.merchantName;
  }

  // 计算 V3 订单的综合状态标签颜色（取最重要的 item 状态）
  Color _summaryStatusColor() {
    final items = order.items;
    if (items.isEmpty) {
      // 旧版降级
      return _legacyStatusColor(order.status ?? '');
    }
    // 优先展示退款/异常状态
    if (items.any((i) => i.customerStatus == CustomerItemStatus.refundReject)) {
      return AppColors.error;
    }
    if (items.any(
        (i) => i.customerStatus == CustomerItemStatus.refundPending ||
            i.customerStatus == CustomerItemStatus.refundReview)) {
      return AppColors.warning;
    }
    if (items.every((i) => i.customerStatus == CustomerItemStatus.refundSuccess)) {
      return AppColors.textSecondary;
    }
    if (items.every((i) => i.customerStatus == CustomerItemStatus.used)) {
      return AppColors.info;
    }
    if (items.every((i) => i.customerStatus == CustomerItemStatus.expired)) {
      return AppColors.textHint;
    }
    // 含未使用券
    if (items.any((i) => i.customerStatus == CustomerItemStatus.unused)) {
      return AppColors.success;
    }
    return AppColors.textHint;
  }

  // 计算 V3 订单的综合状态文案
  String _summaryStatusLabel() {
    final items = order.items;
    if (items.isEmpty) {
      return _legacyStatusLabel(order.status ?? '');
    }
    if (items.any((i) => i.customerStatus == CustomerItemStatus.refundReject)) {
      return 'Refund Rejected';
    }
    if (items.any((i) => i.customerStatus == CustomerItemStatus.refundPending ||
        i.customerStatus == CustomerItemStatus.refundReview)) {
      return 'Refund Processing';
    }
    if (items.every((i) => i.customerStatus == CustomerItemStatus.refundSuccess)) {
      return 'Refunded';
    }
    if (items.every((i) => i.customerStatus == CustomerItemStatus.used)) {
      return 'Used';
    }
    if (items.every((i) => i.customerStatus == CustomerItemStatus.expired)) {
      return 'Expired';
    }
    if (items.any((i) => i.customerStatus == CustomerItemStatus.unused)) {
      return 'Active';
    }
    return 'Active';
  }

  Color _legacyStatusColor(String status) => switch (status) {
    'unused' => AppColors.success,
    'used' => AppColors.info,
    'refunded' => AppColors.textSecondary,
    'voided' => AppColors.textSecondary,
    'refund_requested' => AppColors.warning,
    'refund_failed' => AppColors.error,
    'expired' => AppColors.textHint,
    _ => AppColors.textHint,
  };

  String _legacyStatusLabel(String status) => switch (status) {
    'unused' => 'Active',
    'used' => 'Used',
    'refunded' => 'Refunded',
    'voided' => 'Cancelled',
    'refund_requested' => 'Refund Processing',
    'refund_failed' => 'Refund Failed',
    'expired' => 'Expired',
    _ => status.replaceAll('_', ' '),
  };

  @override
  Widget build(BuildContext context) {
    final imageUrl = _firstImageUrl();
    final statusColor = _summaryStatusColor();
    final statusLabel = _summaryStatusLabel();
    final itemsSummary = _buildItemsSummary();
    final dateFmt = DateFormat('MMM d, yyyy');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/order/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Deal 封面图
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
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

              // 订单信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 商家名
                    if (_merchantName() != null)
                      Text(
                        _merchantName()!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    // Deal 标题
                    Text(
                      _dealTitle(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 总金额 + items 摘要
                    Text(
                      '\$${order.totalAmount.toStringAsFixed(2)} · $itemsSummary',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    // 订单号（如有）
                    if (order.orderNumber != null &&
                        order.orderNumber!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '#${order.orderNumber}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // 右侧：状态 Badge + 日期
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 状态 Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 下单日期
                  Text(
                    dateFmt.format(order.createdAt.toLocal()),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
