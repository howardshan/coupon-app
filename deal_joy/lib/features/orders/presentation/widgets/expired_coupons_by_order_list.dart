// Expired 标签：按订单分组展示过期券（布局与 Used 订单卡片一致）

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/coupon_model.dart';
import '../../domain/providers/coupons_repository_provider.dart';

String _formatDate(DateTime dt) =>
    DateFormat('MMM d, yyyy').format(dt.toLocal());

String _formatDateTime(DateTime dt) =>
    DateFormat('MMM d, yyyy · h:mm a').format(dt.toLocal());

/// 过期券按 orderId 分组；组内按 expiresAt 新→旧；订单组按组内最近过期时间排序
List<List<CouponModel>> groupExpiredCouponsByOrder(List<CouponModel> coupons) {
  final map = <String, List<CouponModel>>{};
  for (final c in coupons) {
    map.putIfAbsent(c.orderId, () => []).add(c);
  }
  for (final list in map.values) {
    list.sort((a, b) => b.expiresAt.compareTo(a.expiresAt));
  }

  DateTime latestExpiryInGroup(List<CouponModel> cs) {
    var best = cs.first.expiresAt;
    for (var i = 1; i < cs.length; i++) {
      final e = cs[i].expiresAt;
      if (e.isAfter(best)) best = e;
    }
    return best;
  }

  final entries = map.entries.toList()
    ..sort((a, b) =>
        latestExpiryInGroup(b.value).compareTo(latestExpiryInGroup(a.value)));

  return entries.map((e) => e.value).toList();
}

String orderTitleForExpiredGroup(List<CouponModel> group) {
  if (group.isEmpty) return 'Order';
  final num = group.first.orderNumber?.trim();
  if (num != null && num.isNotEmpty) return 'Order $num';
  final id = group.first.orderId;
  if (id.length <= 12) return 'Order $id';
  return 'Order …${id.substring(id.length - 8)}';
}

bool _multiMerchant(List<CouponModel> group) {
  if (group.length <= 1) return false;
  final first = group.first.merchantId;
  return group.any((c) => c.merchantId != first);
}

/// Expired Tab 主体
class ExpiredCouponsByOrderList extends ConsumerStatefulWidget {
  final List<CouponModel> coupons;

  const ExpiredCouponsByOrderList({
    super.key,
    required this.coupons,
  });

  @override
  ConsumerState<ExpiredCouponsByOrderList> createState() =>
      _ExpiredCouponsByOrderListState();
}

class _ExpiredCouponsByOrderListState
    extends ConsumerState<ExpiredCouponsByOrderList> {
  Map<String, int> _unusedByOrderId = {};

  @override
  void initState() {
    super.initState();
    _loadUnusedCounts();
  }

  @override
  void didUpdateWidget(covariant ExpiredCouponsByOrderList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coupons.length != widget.coupons.length ||
        oldWidget.coupons.map((c) => c.id).join(',') !=
            widget.coupons.map((c) => c.id).join(',')) {
      _loadUnusedCounts();
    }
  }

  Future<void> _loadUnusedCounts() async {
    final ids = widget.coupons.map((c) => c.orderId).toSet().toList();
    if (ids.isEmpty) {
      if (mounted) setState(() => _unusedByOrderId = {});
      return;
    }
    final m =
        await ref.read(couponsRepositoryProvider).fetchUnusedVoucherCountsByOrders(ids);
    if (mounted) setState(() => _unusedByOrderId = m);
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupExpiredCouponsByOrder(widget.coupons);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _ExpiredOrderCard(
        orderCoupons: groups[i],
        unusedByOrderId: _unusedByOrderId,
      ),
    );
  }
}

class _ExpiredOrderCard extends StatefulWidget {
  final List<CouponModel> orderCoupons;
  final Map<String, int> unusedByOrderId;

  const _ExpiredOrderCard({
    required this.orderCoupons,
    required this.unusedByOrderId,
  });

  @override
  State<_ExpiredOrderCard> createState() => _ExpiredOrderCardState();
}

class _ExpiredOrderCardState extends State<_ExpiredOrderCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final orderCoupons = widget.orderCoupons;
    final first = orderCoupons.first;
    final purchased = orderCoupons
        .map((c) => c.createdAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final multi = _multiMerchant(orderCoupons);
    final merchantLine = first.merchantName ?? 'Merchant';
    final orderTitle = orderTitleForExpiredGroup(orderCoupons);
    final orderId = first.orderId;
    final expiredCount = orderCoupons.length;
    final unusedCount = widget.unusedByOrderId[orderId] ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Icon(
                          Icons.receipt_long_outlined,
                          size: 13,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          orderTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Expired vouchers: $expiredCount',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                          if (unusedCount > 0)
                            Text(
                              'Unused vouchers: $unusedCount',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textHint,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          size: 22,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    multi ? 'Multiple merchants' : merchantLine,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.shopping_bag_outlined,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Purchased: ${_formatDate(purchased)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textHint,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 与展开区域分离，避免与 InkWell 抢手势
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push('/order/$orderId'),
                icon: Icon(
                  Icons.open_in_new,
                  size: 16,
                  color: AppColors.primary,
                ),
                label: const Text('Order details'),
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 16, indent: 14, endIndent: 14),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  for (var i = 0; i < orderCoupons.length; i++) ...[
                    if (i > 0) const SizedBox(height: 4),
                    _ExpiredCouponTile(coupon: orderCoupons[i]),
                  ],
                ],
              ),
            ),
          ] else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ExpiredCouponTile extends StatelessWidget {
  final CouponModel coupon;

  const _ExpiredCouponTile({required this.coupon});

  static const double _thumb = 48;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    final imageUrl = coupon.dealImageUrl;
    final priceLine = coupon.unitPrice != null
        ? '\$${(coupon.unitPrice! + coupon.taxAmount).toStringAsFixed(2)}'
        : null;
    final expiredLine = 'Expired ${_formatDateTime(coupon.expiresAt)}';
    final refundedLine = coupon.refundedAt != null
        ? 'Refunded ${_formatDateTime(coupon.refundedAt!)}'
        : null;

    return InkWell(
      onTap: () => context.push('/coupon/${coupon.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      width: _thumb,
                      height: _thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _dealPlaceholder(),
                    )
                  : _dealPlaceholder(),
            ),
            const SizedBox(width: _gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    coupon.dealTitle ?? 'Deal Coupon',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    expiredLine,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
                  if (refundedLine != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      refundedLine,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (priceLine != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      priceLine,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dealPlaceholder() {
    return Container(
      width: _thumb,
      height: _thumb,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.confirmation_number_outlined,
        size: 20,
        color: AppColors.textHint,
      ),
    );
  }
}
