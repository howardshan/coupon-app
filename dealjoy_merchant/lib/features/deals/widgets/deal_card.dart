// Deal列表卡片 Widget
// 展示: 主图缩略图 + 标题 + 状态Badge + 价格 + 销量/库存

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/merchant_deal.dart';
import 'deal_status_badge.dart';

// ============================================================
// DealCard — Deal 列表卡片（StatelessWidget）
// 点击回调 onTap，展示完整 Deal 信息摘要
// ============================================================
class DealCard extends StatelessWidget {
  const DealCard({
    super.key,
    required this.deal,
    required this.onTap,
  });

  final MerchantDeal deal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧主图缩略图
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(12),
                bottomLeft:  Radius.circular(12),
              ),
              child: _DealThumbnail(imageUrl: deal.coverImageUrl),
            ),

            // 右侧内容区
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 第一行: 标题 + 状态 Badge
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题（最多2行）
                        Expanded(
                          child: Text(
                            deal.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A1A),
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        DealStatusBadge(status: deal.isExpiredByDate ? DealStatus.expired : deal.dealStatus),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 第二行: 价格信息
                    _PriceRow(deal: deal),
                    const SizedBox(height: 8),

                    // 第三行: 销量 / 库存
                    _StatsRow(deal: deal),
                  ],
                ),
              ),
            ),

            // 右侧箭头
            const Padding(
              padding: EdgeInsets.only(right: 8, top: 16),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFFCCCCCC),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 主图缩略图
// ============================================================
class _DealThumbnail extends StatelessWidget {
  const _DealThumbnail({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _placeholder();
    }

    return CachedNetworkImage(
      imageUrl: imageUrl!,
      width: 88,
      height: 88,
      fit: BoxFit.cover,
      placeholder: (_, _) => _placeholder(),
      errorWidget: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 88,
      height: 88,
      color: const Color(0xFFF0F0F0),
      child: const Icon(
        Icons.local_offer_outlined,
        size: 28,
        color: Color(0xFFCCCCCC),
      ),
    );
  }
}

// ============================================================
// 价格行（原价删除线 + 现价 + 折扣标签）
// ============================================================
class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.deal});

  final MerchantDeal deal;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 现价（固定宽度不截断，数字格式固定不会过长）
        Text(
          '\$${deal.discountPrice.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFFFF6B35),
          ),
        ),
        const SizedBox(width: 6),

        // 原价（删除线），用 Flexible 防止与折扣标签一起超出
        Flexible(
          child: Text(
            '\$${deal.originalPrice.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFBBBBBB),
              decoration: TextDecoration.lineThrough,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 6),

        // 折扣标签
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3EE),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            deal.discountLabel,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFF6B35),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 销量/库存统计行
// ============================================================
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.deal});

  final MerchantDeal deal;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 已售出
        const Icon(Icons.shopping_bag_outlined, size: 13, color: Color(0xFF999999)),
        const SizedBox(width: 3),
        // 用 Flexible 防止在宽度受限时溢出
        Flexible(
          child: Text(
            '${deal.totalSold} sold',
            style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 14),

        // 库存
        const Icon(Icons.inventory_2_outlined, size: 13, color: Color(0xFF999999)),
        const SizedBox(width: 3),
        // 库存文字（"Unlimited"、"Sold Out"、"xxx left"）用 Flexible 防止溢出
        Flexible(
          child: Text(
            deal.isUnlimited
                ? 'Unlimited'
                : deal.isSoldOut
                    ? 'Sold Out'
                    : '${deal.remainingStock} left',
            style: TextStyle(
              fontSize: 12,
              color: deal.isSoldOut
                  ? const Color(0xFFE53935)
                  : const Color(0xFF999999),
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}
