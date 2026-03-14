import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';

/// 附近推荐商家卡片
/// 接收来自 RPC 结果的 Map，点击跳转到商家详情页
class NearbyMerchantCard extends StatelessWidget {
  /// RPC 返回的商家数据
  /// 包含: id, name, logo_url, address, avg_rating, review_count,
  ///        distance_miles, price_per_person
  final Map<String, dynamic> merchant;

  const NearbyMerchantCard({super.key, required this.merchant});

  @override
  Widget build(BuildContext context) {
    // 从 Map 中安全取值
    final id = merchant['id'] as String? ?? '';
    final name = merchant['name'] as String? ?? 'Unknown';
    final logoUrl = merchant['logo_url'] as String?;
    final address = merchant['address'] as String? ?? '';
    final avgRating = (merchant['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final reviewCount = (merchant['review_count'] as num?)?.toInt() ?? 0;
    final distanceMiles = (merchant['distance_miles'] as num?)?.toDouble();
    final pricePerPerson = (merchant['price_per_person'] as num?)?.toDouble();

    return GestureDetector(
      onTap: () {
        // 跳转到商家详情页
        if (id.isNotEmpty) context.push('/merchant/$id');
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 左侧：圆角 Logo
            _buildLogo(logoUrl, name),
            const SizedBox(width: 12),
            // 右侧：商家信息
            Expanded(
              child: _buildInfo(
                name: name,
                address: address,
                avgRating: avgRating,
                reviewCount: reviewCount,
                distanceMiles: distanceMiles,
                pricePerPerson: pricePerPerson,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 左侧 60x60 圆角 Logo
  Widget _buildLogo(String? logoUrl, String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    if (logoUrl != null && logoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: logoUrl,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          // Shimmer 加载占位
          placeholder: (context, url) => Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              width: 60,
              height: 60,
              color: Colors.white,
            ),
          ),
          // 加载失败时显示首字母
          errorWidget: (context, url, error) => _buildFallbackLogo(initial),
        ),
      );
    }

    // 无 logoUrl 时显示首字母占位
    return _buildFallbackLogo(initial);
  }

  /// Logo 加载失败或无图时的首字母占位
  Widget _buildFallbackLogo(String initial) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }

  /// 右侧信息列
  Widget _buildInfo({
    required String name,
    required String address,
    required double avgRating,
    required int reviewCount,
    double? distanceMiles,
    double? pricePerPerson,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 商家名称
        Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        // 评分 + 评价数 + 距离（同行）
        Row(
          children: [
            // 星星图标
            const Icon(Icons.star, size: 14, color: AppColors.featuredBadge),
            const SizedBox(width: 3),
            // 评分数字短，不需要弹性
            Text(
              avgRating.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            // 评价数 + 距离合并到 Flexible，防止多字段叠加超出行宽
            Flexible(
              child: Text(
                [
                  '$reviewCount reviews',
                  if (distanceMiles != null)
                    '${distanceMiles.toStringAsFixed(1)} mi',
                ].join(' · '),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        // 地址
        Text(
          address,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // 人均消费（若有）
        if (pricePerPerson != null) ...[
          const SizedBox(height: 3),
          Text(
            '\$${pricePerPerson.toStringAsFixed(0)}/person',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
