import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../deals/data/models/deal_model.dart';

/// 商家详情页 Deal 水平卡片组件
/// 替代旧版 _DealRow，信息更丰富：含折扣徽章、包含内容、已售数量、Buy 按钮
class DealCardHorizontal extends StatelessWidget {
  final DealModel deal;

  const DealCardHorizontal({super.key, required this.deal});

  @override
  Widget build(BuildContext context) {
    // 取 products 前 3 个拼接成一行描述，超出省略
    // 只取产品名称（去掉 ::qty::subtotal 后缀）
    final productsPreview = deal.products.take(3).map((p) => p.split('::').first).join(', ');

    return GestureDetector(
      onTap: () => context.push('/deals/${deal.id}'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceVariant, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧：90x90 图片，含折扣徽章
              _DealImage(deal: deal),

              const SizedBox(width: 12),

              // 右侧：文字信息 + 价格 + Buy 按钮
              Expanded(
                child: _DealInfo(deal: deal, productsPreview: productsPreview),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 左侧图片区域（含折扣徽章，私有）
class _DealImage extends StatelessWidget {
  final DealModel deal;

  const _DealImage({required this.deal});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      height: 90,
      child: Stack(
        children: [
          // 圆角图片
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: (deal.imageUrls.isNotEmpty || deal.merchant?.homepageCoverUrl != null)
                ? CachedNetworkImage(
                    imageUrl: deal.imageUrls.isNotEmpty
                        ? deal.imageUrls.first
                        : deal.merchant!.homepageCoverUrl!,
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                    // Shimmer 加载占位
                    placeholder: (context, url) => Shimmer.fromColors(
                      baseColor: Colors.grey[300]!,
                      highlightColor: Colors.grey[100]!,
                      child: Container(
                        width: 90,
                        height: 90,
                        color: Colors.white,
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 90,
                      height: 90,
                      color: AppColors.surfaceVariant,
                      child: const Icon(
                        Icons.restaurant,
                        size: 32,
                        color: AppColors.textHint,
                      ),
                    ),
                  )
                : Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.restaurant,
                      size: 32,
                      color: AppColors.textHint,
                    ),
                  ),
          ),

          // 左上角折扣徽章（有 discountLabel 时才显示）
          if (deal.effectiveDiscountLabel.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: const BoxDecoration(
                  color: AppColors.discountBadge,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(10),
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
}

/// 连锁品牌 Badge（品牌 Logo + 品牌名，紧凑小字样式）
class _HorizontalBrandBadge extends StatelessWidget {
  final MerchantSummary merchant;

  const _HorizontalBrandBadge({required this.merchant});

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

/// 右侧文字信息区域（私有）
class _DealInfo extends StatelessWidget {
  final DealModel deal;
  final String productsPreview;

  const _DealInfo({required this.deal, required this.productsPreview});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题，最多 2 行
        Text(
          deal.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: AppColors.textPrimary,
            height: 1.3,
          ),
        ),

        const SizedBox(height: 4),

        // 连锁店品牌 Badge（品牌 Logo + 品牌名）
        if (deal.merchant?.isChainStore == true) ...[
          _HorizontalBrandBadge(merchant: deal.merchant!),
          const SizedBox(height: 4),
        ],

        // 包含产品描述（products 前几个）
        if (productsPreview.isNotEmpty)
          Text(
            productsPreview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),

        const SizedBox(height: 4),

        // 已售数量
        Text(
          '${deal.totalSold}+ sold',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),

        const SizedBox(height: 8),

        // 底部行：折扣价 + 原价 + Buy 按钮
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 折扣价
            Text(
              '\$${deal.discountPrice.toStringAsFixed(0)}',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),

            const SizedBox(width: 6),

            // 原价（删除线）
            Text(
              '\$${deal.originalPrice.toStringAsFixed(0)}',
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 12,
                decoration: TextDecoration.lineThrough,
              ),
            ),

            const Spacer(),

            // Buy 按钮，圆角 20
            GestureDetector(
              onTap: () => context.push('/deals/${deal.id}'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Buy',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
