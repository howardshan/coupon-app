// Used 标签：按订单分组展示已核销券；视觉与 Unused 商家分组卡片、券行对齐

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../deals/data/models/review_model.dart';
import '../../../reviews/domain/providers/my_reviews_provider.dart';
import '../../data/models/coupon_model.dart';

String _formatDate(DateTime dt) =>
    DateFormat('MMM d, yyyy').format(dt.toLocal());

/// 核销时间：日期 + 时分（与 coupons_provider Unused 统计规则一致）
String _formatUsedAt(DateTime dt) =>
    DateFormat('MMM d, yyyy · h:mm a').format(dt.toLocal());

/// 与 Unused Tab 过滤一致，用于按订单统计未使用券数量
bool _couponCountsAsUnusedTab(CouponModel c) {
  return c.status == 'unused' &&
      !c.isExpired &&
      c.refundedAt == null &&
      c.orderItemId != null &&
      (c.customerStatus == null || c.customerStatus == 'unused');
}

int _unusedCountForOrder(String orderId, List<CouponModel> allCoupons) {
  return allCoupons
      .where((c) => c.orderId == orderId && _couponCountsAsUnusedTab(c))
      .length;
}

/// 将已使用券按 orderId 分组，组内按 usedAt 降序；订单组按组内最近 usedAt 降序
List<List<CouponModel>> groupUsedCouponsByOrder(List<CouponModel> coupons) {
  final map = <String, List<CouponModel>>{};
  for (final c in coupons) {
    map.putIfAbsent(c.orderId, () => []).add(c);
  }
  for (final list in map.values) {
    list.sort((a, b) {
      final ta = a.usedAt;
      final tb = b.usedAt;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
  }

  DateTime? latestUsedInGroup(List<CouponModel> cs) {
    DateTime? best;
    for (final c in cs) {
      final u = c.usedAt;
      if (u == null) continue;
      if (best == null || u.isAfter(best)) best = u;
    }
    return best;
  }

  final entries = map.entries.toList()
    ..sort((a, b) {
      final la = latestUsedInGroup(a.value);
      final lb = latestUsedInGroup(b.value);
      if (la == null && lb == null) return 0;
      if (la == null) return 1;
      if (lb == null) return -1;
      return lb.compareTo(la);
    });

  return entries.map((e) => e.value).toList();
}

/// 订单抬头展示用：优先可读订单号，否则缩短 UUID
String orderTitleForGroup(List<CouponModel> group) {
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

/// Used Tab 主体：每个订单一张可展开卡片
class UsedCouponsByOrderList extends StatelessWidget {
  final List<CouponModel> coupons;
  /// 全量券列表（用于按订单统计未使用券数量）
  final List<CouponModel> allCoupons;
  final List<ReviewModel> myReviews;

  const UsedCouponsByOrderList({
    super.key,
    required this.coupons,
    required this.allCoupons,
    required this.myReviews,
  });

  @override
  Widget build(BuildContext context) {
    final groups = groupUsedCouponsByOrder(coupons);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _UsedOrderCard(
        orderCoupons: groups[i],
        allCoupons: allCoupons,
        myReviews: myReviews,
      ),
    );
  }
}

/// 与 Unused `_MerchantCouponGroup` 一致：白底圆角阴影 + 抬头行 + Divider + 内容区
class _UsedOrderCard extends StatefulWidget {
  final List<CouponModel> orderCoupons;
  final List<CouponModel> allCoupons;
  final List<ReviewModel> myReviews;

  const _UsedOrderCard({
    required this.orderCoupons,
    required this.allCoupons,
    required this.myReviews,
  });

  @override
  State<_UsedOrderCard> createState() => _UsedOrderCardState();
}

class _UsedOrderCardState extends State<_UsedOrderCard> {
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
    final orderTitle = orderTitleForGroup(orderCoupons);
    final orderId = first.orderId;
    final usedCount = orderCoupons.length;
    final unusedCount = _unusedCountForOrder(orderId, widget.allCoupons);

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
                            'Used vouchers: $usedCount',
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
          if (_expanded) ...[
            const Divider(height: 16, indent: 14, endIndent: 14),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  for (var i = 0; i < orderCoupons.length; i++) ...[
                    if (i > 0) const SizedBox(height: 4),
                    _UsedCouponTile(
                      coupon: orderCoupons[i],
                      writtenReview: matchWrittenReviewForCoupon(
                        orderCoupons[i],
                        widget.myReviews,
                      ),
                    ),
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

/// 与 Unused `_CouponRow` 对齐：48 图 + 标题/辅文 + 右侧 chevron
class _UsedCouponTile extends StatelessWidget {
  final CouponModel coupon;
  final ReviewModel? writtenReview;

  const _UsedCouponTile({
    required this.coupon,
    required this.writtenReview,
  });

  static const double _thumb = 48;
  static const double _gap = 10;
  static const double _textInset = _thumb + _gap;

  @override
  Widget build(BuildContext context) {
    final showWriteHint = writtenReview == null;
    final usedLine = coupon.usedAt != null
        ? 'Used ${_formatUsedAt(coupon.usedAt!)}'
        : 'Used';
    final imageUrl = coupon.dealImageUrl;
    final priceLine = coupon.unitPrice != null
        ? '\$${(coupon.unitPrice! + coupon.taxAmount).toStringAsFixed(2)}'
        : null;

    return InkWell(
      onTap: () => context.push('/coupon/${coupon.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                        usedLine,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
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
            if (writtenReview != null) ...[
              Padding(
                padding: const EdgeInsets.only(left: _textInset, top: 6),
                child: Row(
                  children: [
                    ...List.generate(5, (idx) {
                      final stars = writtenReview!.ratingOverall > 0
                          ? writtenReview!.ratingOverall
                          : writtenReview!.rating;
                      return Icon(
                        idx < stars ? Icons.star : Icons.star_border,
                        size: 14,
                        color: AppColors.warning,
                      );
                    }),
                    const SizedBox(width: 6),
                    Text(
                      'Reviewed',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (showWriteHint && coupon.status == 'used') ...[
              Padding(
                padding: const EdgeInsets.only(left: _textInset, top: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.rate_review_outlined,
                      size: 14,
                      color: AppColors.primary.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Write a review',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
