// 团购券列表卡片组件 — 在 CouponsScreen 中复用

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../deals/data/models/review_model.dart';
import '../../data/models/coupon_model.dart';

/// 每种状态对应的颜色映射
Color _statusColor(String status) => switch (status) {
      'unused' => AppColors.primary,
      'used' => AppColors.success,
      'expired' => AppColors.textHint,
      'expired_refund' => AppColors.warning,
      'refunded' => AppColors.warning,
      'gifted' => const Color(0xFF9C27B0),
      'voided' => AppColors.textSecondary,
      _ => AppColors.textHint,
    };

/// 每种状态对应的展示文案
String _statusLabel(String status) => switch (status) {
      'unused' => 'Unused',
      'used' => 'Used',
      'expired' => 'Expired',
      'expired_refund' => 'Expired Refund',
      'refunded' => 'Refunded',
      'gifted' => 'Gifted',
      'voided' => 'Cancelled',
      _ => status.toUpperCase(),
    };

/// 格式化日期：Mar 15, 2026
String _formatDate(DateTime dt) =>
    DateFormat('MMM d, yyyy').format(dt.toLocal());

class CouponCard extends StatelessWidget {
  final CouponModel coupon;
  final VoidCallback onTap;

  /// Used tab：已匹配到的用户评价（可选）
  final ReviewModel? writtenReview;

  /// Used tab：提示仍可写评价（列表未匹配到评价时）
  final bool showWriteReviewHint;

  const CouponCard({
    super.key,
    required this.coupon,
    required this.onTap,
    this.writtenReview,
    this.showWriteReviewHint = false,
  });

  @override
  Widget build(BuildContext context) {
    // 状态判断：gifted(含 customerStatus) > voided > 过期(全部自动退款=Expired Return) > 原始状态
    // 受赠人持券可用：order_item 仍为 gifted，但应按 Unused 展示
    final myUid = Supabase.instance.client.auth.currentUser?.id;
    final heldByViewer =
        myUid != null && coupon.isHeldByUser(myUid);
    final String displayStatus;
    if (coupon.customerStatus == 'gifted' &&
        heldByViewer &&
        coupon.isUnused &&
        !coupon.isVoided) {
      displayStatus = 'unused';
    } else if (coupon.customerStatus == 'gifted') {
      displayStatus = 'gifted';
    } else if (coupon.isVoided && coupon.voidReason == 'gifted') {
      displayStatus = 'gifted';
    } else if (coupon.isVoided) {
      displayStatus = 'voided';
    } else if (coupon.isExpired) {
      displayStatus = 'expired_refund';
    } else {
      displayStatus = coupon.status;
    }
    final color = _statusColor(displayStatus);
    final label = _statusLabel(displayStatus);

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部行：商户 logo + 商户名 + 状态 badge + QR icon
              Row(
                children: [
                  // 商户 Logo 圆形头像
                  _MerchantAvatar(logoUrl: coupon.merchantLogoUrl),
                  const SizedBox(width: 12),

                  // 商户名 + deal 标题
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (coupon.merchantName != null)
                          Text(
                            coupon.merchantName!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        Text(
                          coupon.dealTitle ?? 'Deal Coupon',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 状态 Badge + QR 图标（仅 unused 显示）
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 状态 Chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (coupon.isUnused && !coupon.isExpired && coupon.customerStatus != 'gifted') ...[
                        const SizedBox(height: 6),
                        const Icon(
                          Icons.qr_code_2,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 多店通用提示（适用门店数 > 1 时显示）
              if (coupon.applicableMerchantIds != null &&
                  coupon.applicableMerchantIds!.length > 1) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.store_outlined,
                          size: 13, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Valid at ${coupon.applicableMerchantIds!.length} locations',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // 好友赠送来源标签
              if (coupon.giftedFromUserName != null &&
                  coupon.giftedFromUserName!.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9C27B0).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.card_giftcard,
                          size: 13, color: Color(0xFF9C27B0)),
                      const SizedBox(width: 4),
                      Text(
                        'Gift from ${coupon.giftedFromUserName}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9C27B0),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // 底部行：有效期 + 购买日期
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.event_available_outlined,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  // 有效期文字用 Flexible 包裹，防止长日期溢出
                  Flexible(
                    child: Text(
                      'Expires: ${_formatDate(coupon.expiresAt)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.shopping_bag_outlined,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  // 购买日期文字用 Flexible 包裹，防止长日期溢出
                  Flexible(
                    child: Text(
                      'Purchased: ${_formatDate(coupon.createdAt)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              // Used tab：评价状态轻量提示
              if (writtenReview != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    ...List.generate(
                      5,
                      (idx) {
                        final stars = writtenReview!.ratingOverall > 0
                            ? writtenReview!.ratingOverall
                            : writtenReview!.rating;
                        return Icon(
                          idx < stars ? Icons.star : Icons.star_border,
                          size: 16,
                          color: AppColors.warning,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Reviewed',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ] else if (showWriteReviewHint && coupon.status == 'used') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.rate_review_outlined,
                      size: 16,
                      color: AppColors.primary.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Write a review',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 商户 Logo 圆形组件，无图时显示默认图标
class _MerchantAvatar extends StatelessWidget {
  final String? logoUrl;

  const _MerchantAvatar({this.logoUrl});

  @override
  Widget build(BuildContext context) {
    if (logoUrl != null && logoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.surfaceVariant,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: logoUrl!,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => const Icon(
              Icons.store,
              color: AppColors.textSecondary,
              size: 24,
            ),
          ),
        ),
      );
    }
    return const CircleAvatar(
      radius: 24,
      backgroundColor: AppColors.surfaceVariant,
      child: Icon(Icons.store, color: AppColors.textSecondary, size: 24),
    );
  }
}
