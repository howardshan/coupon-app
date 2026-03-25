// 订单列表页 — 以 Order 为外框，内部按商家分组，每个 deal 显示数量
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/order_item_model.dart';
import '../../data/models/order_model.dart';
import '../../domain/providers/orders_provider.dart';

// ── 数据结构 ──────────────────────────────────────────────────

/// 同一 deal 的多张券
class _DealGroup {
  final String dealId;
  final String dealTitle;
  final String? dealImageUrl;
  final double unitPrice;
  final List<OrderItemModel> items;

  _DealGroup({
    required this.dealId,
    required this.dealTitle,
    this.dealImageUrl,
    required this.unitPrice,
    required this.items,
  });

  int get quantity => items.isEmpty ? 1 : items.length;
  double get subtotal => unitPrice * quantity;
}

/// 同一商家下的 deal groups
class _MerchantGroup {
  final String merchantName;
  final List<_DealGroup> dealGroups;

  _MerchantGroup({required this.merchantName, required this.dealGroups});

  // 综合状态
  String get statusLabel {
    final allItems = dealGroups.expand((g) => g.items).toList();
    if (allItems.isEmpty) return 'Active';
    if (allItems.any((i) =>
        i.customerStatus == CustomerItemStatus.refundPending ||
        i.customerStatus == CustomerItemStatus.refundReview)) {
      return 'Refund Processing';
    }
    if (allItems.every((i) => i.customerStatus == CustomerItemStatus.refundSuccess)) {
      return 'Refunded';
    }
    if (allItems.every((i) => i.customerStatus == CustomerItemStatus.used)) {
      return 'Used';
    }
    if (allItems.every((i) => i.customerStatus == CustomerItemStatus.expired)) {
      return 'Expired';
    }
    if (allItems.any((i) => i.customerStatus == CustomerItemStatus.unused)) {
      return 'To Use';
    }
    return 'Completed';
  }

  Color get statusColor => switch (statusLabel) {
    'To Use' => AppColors.success,
    'Used' => AppColors.info,
    'Refunded' => AppColors.textSecondary,
    'Refund Processing' => AppColors.warning,
    'Expired' => AppColors.textHint,
    _ => AppColors.textHint,
  };
}

/// Order 级别包装（含订单号、service fee、total）
class _OrderEntry {
  final OrderModel order;
  final List<_MerchantGroup> merchantGroups;

  _OrderEntry({required this.order, required this.merchantGroups});
}

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  List<_OrderEntry> _buildOrderEntries(List<OrderModel> orders) {
    return orders.map((order) {
      if (order.items.isEmpty) {
        // 旧版订单
        return _OrderEntry(
          order: order,
          merchantGroups: [
            _MerchantGroup(
              merchantName: order.deal?.merchantName ?? 'Merchant',
              dealGroups: [
                _DealGroup(
                  dealId: order.dealId ?? '',
                  dealTitle: order.deal?.title ?? 'Deal',
                  dealImageUrl: order.deal?.imageUrl,
                  unitPrice: order.unitPrice ?? order.totalAmount,
                  items: const [],
                ),
              ],
            ),
          ],
        );
      }

      // V3：按商家分组
      final merchantMap = <String, List<OrderItemModel>>{};
      for (final item in order.items) {
        final merchant = item.merchantName ?? item.purchasedMerchantName ?? 'Merchant';
        merchantMap.putIfAbsent(merchant, () => []).add(item);
      }

      final merchantGroups = merchantMap.entries.map((entry) {
        // 按 deal 分组
        final dealMap = <String, List<OrderItemModel>>{};
        for (final item in entry.value) {
          dealMap.putIfAbsent(item.dealId, () => []).add(item);
        }
        final dealGroups = dealMap.entries.map((de) {
          final items = de.value;
          final first = items.first;
          return _DealGroup(
            dealId: first.dealId,
            dealTitle: first.dealTitle.isNotEmpty ? first.dealTitle : 'Deal',
            dealImageUrl: first.dealImageUrl,
            unitPrice: first.unitPrice,
            items: items,
          );
        }).toList();

        return _MerchantGroup(merchantName: entry.key, dealGroups: dealGroups);
      }).toList();

      return _OrderEntry(order: order, merchantGroups: merchantGroups);
    }).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(userOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : IconButton(
                icon: const Icon(Icons.home_outlined),
                onPressed: () => context.go('/home'),
              ),
      ),
      body: ordersAsync.when(
        data: (orders) {
          final entries = _buildOrderEntries(orders);
          if (entries.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 72, color: AppColors.textHint),
                  SizedBox(height: 16),
                  Text('No orders yet', style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(userOrdersProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (_, i) => _OrderCard(entry: entries[i]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.textHint),
              const SizedBox(height: 12),
              const Text('Failed to load orders', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(userOrdersProvider),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Order 外框卡片 ────────────────────────────────────────────
class _OrderCard extends StatelessWidget {
  final _OrderEntry entry;

  const _OrderCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final order = entry.order;
    final dateFmt = DateFormat('MMM d, yyyy · h:mm a');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 订单号（点击跳转订单详情）──────────────────────
            InkWell(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              onTap: () => context.push('/order/${order.id}'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_outlined, size: 16, color: AppColors.textHint),
                    const SizedBox(width: 6),
                    Text(
                      '#${(order.orderNumber ?? order.id.substring(0, 8)).toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Order Detail',
                      style: TextStyle(fontSize: 11, color: AppColors.textHint),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 16, color: AppColors.textHint),
                  ],
                ),
              ),
            ),
            const Divider(height: 16, indent: 14, endIndent: 14),

            // ── 商家组（可能多个）──────────────────────────────
            ...entry.merchantGroups.map((mg) => _MerchantSection(group: mg, orderId: order.id)),

            // ── 底部：Service Fee + Total ────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  if (order.serviceFeeTotal > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Service Fee', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        Text('\$${order.serviceFeeTotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('\$${order.totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
      ),
    );
  }
}

// ── 商家区域（商家抬头 + deal 行）────────────────────────────
class _MerchantSection extends StatelessWidget {
  final _MerchantGroup group;
  final String orderId;

  const _MerchantSection({required this.group, required this.orderId});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 商家抬头
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Icon(Icons.store, size: 13, color: AppColors.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.merchantName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: group.statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  group.statusLabel,
                  style: TextStyle(color: group.statusColor, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        // Deal 行（每个 deal 独立可点击）
        ...group.dealGroups.map((dg) => _DealRow(group: dg, orderId: orderId)),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ── Deal 行 ──────────────────────────────────────────────────
class _DealRow extends StatelessWidget {
  final _DealGroup group;
  final String orderId;

  const _DealRow({required this.group, required this.orderId});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/voucher/$orderId?dealId=${group.dealId}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: group.dealImageUrl != null
                ? CachedNetworkImage(
                    imageUrl: group.dealImageUrl!,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _placeholder(),
                    errorWidget: (_, __, ___) => _placeholder(),
                  )
                : _placeholder(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.dealTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  'Qty: ${group.quantity}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                // 过期日期（从第一张券获取）
                if (group.items.isNotEmpty && group.items.first.couponExpiresAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Expires ${DateFormat('MMM d, yyyy').format(group.items.first.couponExpiresAt!.toLocal())}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${group.subtotal.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              if (group.quantity > 1)
                Text(
                  '\$${group.unitPrice.toStringAsFixed(2)} ea',
                  style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                ),
            ],
          ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.restaurant, size: 22, color: AppColors.textHint),
    );
  }
}
