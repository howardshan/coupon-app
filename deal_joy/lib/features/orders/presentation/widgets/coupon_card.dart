// 团购券列表卡片组件 — 在 CouponsScreen 中复用

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/coupon_model.dart';

/// 每种状态对应的颜色映射
Color _statusColor(String status) => switch (status) {
      'unused' => AppColors.primary,
      'used' => AppColors.success,
      'expired' => AppColors.textHint,
      'refunded' => AppColors.warning,
      _ => AppColors.textHint,
    };

/// 每种状态对应的展示文案
String _statusLabel(String status) => switch (status) {
      'unused' => 'Unused',
      'used' => 'Used',
      'expired' => 'Expired',
      'refunded' => 'Refunded',
      _ => status.toUpperCase(),
    };

/// 格式化日期：Mar 15, 2026
String _formatDate(DateTime dt) =>
    DateFormat('MMM d, yyyy').format(dt.toLocal());

class CouponCard extends StatelessWidget {
  final CouponModel coupon;
  final VoidCallback onTap;

  const CouponCard({
    super.key,
    required this.coupon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 按时间已过期时在列表中统一显示为 Expired
    final displayExpired = coupon.isExpired;
    final color = displayExpired
        ? _statusColor('expired')
        : _statusColor(coupon.status);
    final label = displayExpired ? 'Expired' : _statusLabel(coupon.status);

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
                      if (coupon.isUnused && !coupon.isExpired) ...[
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

              // 底部行：有效期 + 购买日期
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.event_available_outlined,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Expires: ${_formatDate(coupon.expiresAt)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  if (coupon.orderNumber != null && coupon.orderNumber!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '#${coupon.orderNumber}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  const Icon(Icons.shopping_bag_outlined,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Purchased: ${_formatDate(coupon.createdAt)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
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
