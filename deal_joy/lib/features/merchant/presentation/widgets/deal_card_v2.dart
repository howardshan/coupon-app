import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../deals/data/models/deal_model.dart';

/// 连锁品牌 Badge（品牌 Logo + 品牌名，紧凑小字样式）
class _V2BrandBadge extends StatelessWidget {
  final MerchantSummary merchant;

  const _V2BrandBadge({required this.merchant});

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

/// V2 Deal 水平卡片
/// 相比 DealCardHorizontal 增加了：
/// - 120x90 图片（更大）
/// - badge_text 自定义角标
/// - 折扣标签
/// - Buy 按钮使用 secondary 色
class DealCardV2 extends StatelessWidget {
  final DealModel deal;

  const DealCardV2({super.key, required this.deal});

  @override
  Widget build(BuildContext context) {
    // 只取产品名称（去掉 ::qty::subtotal 后缀）
    final productsPreview = deal.products.take(3).map((p) => p.split('::').first).join(', ');

    return GestureDetector(
      onTap: () => context.push('/deals/${deal.id}'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceVariant, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧：120x90 图片 + 角标
            _buildImage(),
            const SizedBox(width: 12),
            // 右侧：文字信息（高度与图片对齐，避免 Spacer 在无界约束下崩溃）
            Expanded(child: SizedBox(height: 90, child: _buildInfo(productsPreview))),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    final imageUrl = deal.imageUrls.isNotEmpty
        ? deal.imageUrls.first
        : deal.merchant?.homepageCoverUrl;

    return SizedBox(
      width: 120,
      height: 90,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 120,
                    height: 90,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Shimmer.fromColors(
                      baseColor: Colors.grey[300]!,
                      highlightColor: Colors.grey[100]!,
                      child: Container(
                          width: 120, height: 90, color: Colors.white),
                    ),
                    errorWidget: (_, _, _) => Container(
                      width: 120,
                      height: 90,
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.restaurant,
                          size: 28, color: AppColors.textHint),
                    ),
                  )
                : Container(
                    width: 120,
                    height: 90,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.restaurant,
                        size: 28, color: AppColors.textHint),
                  ),
          ),

          // 左上角自定义角标（badge_text）
          if (deal.badgeText != null && deal.badgeText!.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: const BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Text(
                  deal.badgeText!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // 左上角折扣徽章（无 badge_text 时显示折扣）
          if ((deal.badgeText == null || deal.badgeText!.isEmpty) &&
              deal.effectiveDiscountLabel.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: const BoxDecoration(
                  color: AppColors.discountBadge,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Text(
                  deal.effectiveDiscountLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfo(String productsPreview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Text(
          deal.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: AppColors.textPrimary,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 3),

        // 连锁店品牌 Badge（品牌 Logo + 品牌名）
        if (deal.merchant?.isChainStore == true) ...[
          _V2BrandBadge(merchant: deal.merchant!),
          const SizedBox(height: 3),
        ],

        // 菜品预览
        if (productsPreview.isNotEmpty)
          Text(
            productsPreview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),

        const Spacer(),

        // 价格行
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 左侧价格区域（可收缩）
            Flexible(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 现价
                  Text(
                    '\$${deal.discountPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 折扣
                  if (deal.effectiveDiscountLabel.isNotEmpty)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Text(
                          deal.effectiveDiscountLabel,
                          style: const TextStyle(
                            color: AppColors.secondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  // 原价删除线
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '\$${deal.originalPrice.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Buy 按钮
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Buy',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
