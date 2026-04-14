// Used 标签：按订单分组展示已核销券，可展开查看子券并跳转券详情

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../deals/data/models/review_model.dart';
import '../../../reviews/domain/providers/my_reviews_provider.dart';
import '../../data/models/coupon_model.dart';

String _formatDate(DateTime dt) =>
    DateFormat('MMM d, yyyy').format(dt.toLocal());

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
  final List<ReviewModel> myReviews;

  const UsedCouponsByOrderList({
    super.key,
    required this.coupons,
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
        myReviews: myReviews,
      ),
    );
  }
}

class _UsedOrderCard extends StatelessWidget {
  final List<CouponModel> orderCoupons;
  final List<ReviewModel> myReviews;

  const _UsedOrderCard({
    required this.orderCoupons,
    required this.myReviews,
  });

  @override
  Widget build(BuildContext context) {
    final first = orderCoupons.first;
    final purchased = orderCoupons
        .map((c) => c.createdAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final multi = _multiMerchant(orderCoupons);
    final merchantLine = first.merchantName ?? 'Merchant';
    final subtitle = multi
        ? '$merchantLine · Multiple merchants · ${orderCoupons.length} used'
        : '$merchantLine · ${orderCoupons.length} voucher${orderCoupons.length > 1 ? 's' : ''}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shadowColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              orderTitleForGroup(orderCoupons),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Purchased: ${_formatDate(purchased)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            iconColor: AppColors.primary,
            collapsedIconColor: AppColors.textSecondary,
            children: orderCoupons
                .map(
                  (c) => _UsedCouponTile(
                    coupon: c,
                    writtenReview: matchWrittenReviewForCoupon(c, myReviews),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _UsedCouponTile extends StatelessWidget {
  final CouponModel coupon;
  final ReviewModel? writtenReview;

  const _UsedCouponTile({
    required this.coupon,
    required this.writtenReview,
  });

  @override
  Widget build(BuildContext context) {
    final showWriteHint = writtenReview == null;
    final usedLine = coupon.usedAt != null
        ? 'Used: ${_formatDate(coupon.usedAt!)}'
        : 'Used';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.surfaceVariant.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => context.push('/coupon/${coupon.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            coupon.dealTitle ?? 'Deal Coupon',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            usedLine,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Used',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (writtenReview != null) ...[
                  const SizedBox(height: 8),
                  Row(
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
                ] else if (showWriteHint && coupon.status == 'used') ...[
                  const SizedBox(height: 8),
                  Row(
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
                ],
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'View details',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primary.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.primary.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
