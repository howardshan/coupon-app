import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/deal_model.dart';
import '../../../merchant/data/models/merchant_model.dart';

// ── 横向 Deal 卡片 ─────────────────────────────────────────────
class DealListCard extends StatelessWidget {
  final DealModel deal;

  const DealListCard({super.key, required this.deal});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/deals/${deal.id}'),
      child: _HorizontalCard(
        imageUrl: deal.imageUrls.isNotEmpty ? deal.imageUrls.first : null,
        subtitle: deal.merchant?.name,
        title: deal.title,
        trailing: Row(
          children: [
            Text(
              '\$${deal.discountPrice.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '\$${deal.originalPrice.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textHint,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                deal.effectiveDiscountLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 横向 Store 卡片 ────────────────────────────────────────────
class MerchantListCard extends StatelessWidget {
  final MerchantModel merchant;

  const MerchantListCard({super.key, required this.merchant});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/merchant/${merchant.id}'),
      child: _HorizontalCard(
        imageUrl: merchant.logoUrl,
        subtitle: merchant.address,
        title: merchant.name,
        trailing: Row(
          children: [
            if (merchant.avgRating != null) ...[
              const Icon(Icons.star, size: 14, color: Color(0xFFF59E0B)),
              const SizedBox(width: 2),
              Text(
                merchant.avgRating!.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (merchant.totalReviewCount != null) ...[
                const SizedBox(width: 4),
                Text(
                  '(${merchant.totalReviewCount})',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ],
            const Spacer(),
            if (merchant.activeDealCount != null &&
                merchant.activeDealCount! > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${merchant.activeDealCount} deals',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── 通用空状态 ─────────────────────────────────────────────────
class CollectionEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String hint;
  final VoidCallback onExplore;

  const CollectionEmptyState({
    super.key,
    required this.icon,
    required this.message,
    required this.hint,
    required this.onExplore,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: const TextStyle(fontSize: 13, color: AppColors.textHint),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onExplore,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Explore'),
          ),
        ],
      ),
    );
  }
}

// ── 共用横向卡片骨架（私有，仅本文件使用）─────────────────────
class _HorizontalCard extends StatelessWidget {
  final String? imageUrl;
  final String? subtitle;
  final String title;
  final Widget trailing;

  const _HorizontalCard({
    required this.imageUrl,
    required this.subtitle,
    required this.title,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(16),
            ),
            child: imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: imageUrl!,
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 100,
                    height: 100,
                    color: AppColors.surfaceVariant,
                    child: const Icon(
                      Icons.restaurant,
                      color: AppColors.textHint,
                      size: 32,
                    ),
                  ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  trailing,
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.chevron_right, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}
