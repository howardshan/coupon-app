import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/deal_model.dart';

/// 连锁品牌 Badge（品牌 Logo + 品牌名，紧凑小字样式）
/// 仅在 merchant.isChainStore == true 时使用
class _DealCardBrandBadge extends StatelessWidget {
  final MerchantSummary merchant;

  const _DealCardBrandBadge({required this.merchant});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 品牌 Logo（14px 圆角）
        if (merchant.brandLogoUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Image.network(
              merchant.brandLogoUrl!,
              width: 14,
              height: 14,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.business,
                size: 12,
                color: AppColors.textHint,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        // 品牌名称
        Flexible(
          child: Text(
            merchant.brandName ?? '',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textHint,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class DealCard extends StatelessWidget {
  final DealModel deal;

  const DealCard({super.key, required this.deal});

  // 优先显示距离（Near Me），其次城市名，最后 sold 数量
  String _locationLabel() {
    if (deal.distanceMeters != null) {
      final miles = deal.distanceMeters! / 1609.34;
      return '${miles.toStringAsFixed(1)} mi';
    }
    if (deal.merchantCity != null && deal.merchantCity!.isNotEmpty) {
      return deal.merchantCity!;
    }
    return '${deal.totalSold} sold';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/deals/${deal.id}'),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with discount badge
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: (deal.imageUrls.isNotEmpty || deal.merchant?.homepageCoverUrl != null)
                      ? CachedNetworkImage(
                          imageUrl: deal.imageUrls.isNotEmpty
                              ? deal.imageUrls.first
                              : deal.merchant!.homepageCoverUrl!,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Shimmer.fromColors(
                            baseColor: Colors.grey[300]!,
                            highlightColor: Colors.grey[100]!,
                            child: Container(
                              height: 160,
                              color: Colors.white,
                            ),
                          ),
                          errorWidget: (_, _, _) => Container(
                            height: 160,
                            color: AppColors.surfaceVariant,
                            child: const Icon(Icons.restaurant,
                                size: 48, color: AppColors.textHint),
                          ),
                        )
                      : Container(
                          height: 160,
                          color: AppColors.surfaceVariant,
                          child: const Icon(Icons.restaurant,
                              size: 48, color: AppColors.textHint),
                        ),
                ),
                // Discount badge
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.discountBadge,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${deal.discountPercent}% OFF',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                // 右上角：连锁品牌标识 > Featured
                if (deal.merchant?.isChainStore == true)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(153),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (deal.merchant!.brandLogoUrl != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: Image.network(
                                deal.merchant!.brandLogoUrl!,
                                width: 16,
                                height: 16,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.business, size: 14, color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          const Text(
                            'Chain',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (deal.isFeatured)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.featuredBadge,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Featured',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (deal.merchant != null) ...[
                    Text(
                      deal.merchant!.name,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 连锁店显示品牌 Badge（品牌 Logo + 品牌名）
                    if (deal.merchant!.isChainStore) ...[
                      const SizedBox(height: 3),
                      _DealCardBrandBadge(merchant: deal.merchant!),
                    ],
                  ],
                  const SizedBox(height: 4),
                  Text(
                    deal.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '\$${deal.discountPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '\$${deal.originalPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 13,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star,
                          size: 14, color: AppColors.featuredBadge),
                      const SizedBox(width: 2),
                      Text(
                        deal.rating.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${deal.reviewCount})',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      Text(
                        _locationLabel(),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
