import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/merchant_detail_model.dart';
import '../../data/models/review_stats_model.dart';
import '../../data/models/store_facility_model.dart';

/// 商家基本信息整合卡片
/// 包含：名称、评分、标签、营业状态、便利设施、地址+操作按钮
class StoreInfoCard extends StatelessWidget {
  final MerchantDetailModel merchant;
  final ReviewStatsModel? reviewStats;
  final List<StoreFacilityModel> facilities;
  // Near Me 模式下传入的距离（英里）
  final double? distanceMiles;

  const StoreInfoCard({
    super.key,
    required this.merchant,
    this.reviewStats,
    this.facilities = const [],
    this.distanceMiles,
  });

  @override
  Widget build(BuildContext context) {
    final avgRating = reviewStats?.avgRating ?? 0.0;
    final reviewCount = reviewStats?.totalCount ?? 0;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：商家名称
          Text(
            merchant.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          // 品牌标识（连锁店显示）
          if (merchant.isChainStore) ...[
            const SizedBox(height: 6),
            _buildBrandBadge(),
          ],

          const SizedBox(height: 6),

          // 第二行：评分 + 评论数 + 人均 + 经营年数
          _buildRatingRow(avgRating, reviewCount),

          // 第三行：标签 chips
          if (merchant.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildTagChips(),
          ],

          const SizedBox(height: 10),

          // 第四行：营业状态
          _buildHoursRow(),

          // 第五行：便利标签
          if (facilities.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildFacilityChips(),
          ],

          // 第六行：地址 + 操作按钮
          if (merchant.address != null && merchant.address!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildAddressRow(),
          ],
        ],
      ),
    );
  }

  Widget _buildBrandBadge() {
    return Row(
      children: [
        if (merchant.brandLogoUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(
              merchant.brandLogoUrl!,
              width: 18,
              height: 18,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.business,
                size: 16,
                color: AppColors.secondary,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          merchant.brandName ?? '',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'Chain',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.secondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRatingRow(double avgRating, int reviewCount) {
    return Row(
      children: [
        const Icon(Icons.star_rounded, size: 16, color: AppColors.secondary),
        const SizedBox(width: 3),
        // 评分数字固定不长，不需要弹性
        Text(
          avgRating.toStringAsFixed(1),
          style: const TextStyle(
            color: AppColors.secondary,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 4),
        // 评价数 + 距离 + 人均 + 经营年数整体放入 Flexible，超出则截断
        Flexible(
          child: Text(
            [
              '$reviewCount reviews',
              if (distanceMiles != null)
                '${distanceMiles!.toStringAsFixed(1)} mi',
              if (merchant.pricePerPerson != null)
                '\$${merchant.pricePerPerson!.toStringAsFixed(0)}/person',
              if (merchant.yearsInBusiness != null &&
                  merchant.yearsInBusiness! > 0)
                'Est. ${merchant.establishedYear}',
            ].join(' · '),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildTagChips() {
    return SizedBox(
      height: 22,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: merchant.tags.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            merchant.tags[i],
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHoursRow() {
    final isOpen = merchant.isOpenNow;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isOpen ? AppColors.success : AppColors.error,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          isOpen ? 'Open Now' : 'Closed',
          style: TextStyle(
            color: isOpen ? AppColors.success : AppColors.error,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        if (merchant.todayHoursText.isNotEmpty) ...[
          const Text('  ·  ',
              style: TextStyle(color: AppColors.textHint, fontSize: 13)),
          Expanded(
            child: Text(
              merchant.todayHoursText,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFacilityChips() {
    // 只显示前 6 个设施
    final shown = facilities.take(6).toList();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: shown.map((f) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_facilityIcon(f.facilityType),
                  size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                f.name,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAddressRow() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined,
              size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              merchant.address!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // 导航按钮
          _CircleButton(
            icon: Icons.directions_car_outlined,
            onTap: () => _openNavigation(),
          ),
          const SizedBox(width: 8),
          // 电话按钮
          _CircleButton(
            icon: Icons.phone_outlined,
            onTap: merchant.phone != null ? () => _callPhone() : null,
          ),
        ],
      ),
    );
  }

  Future<void> _openNavigation() async {
    final encoded = Uri.encodeComponent(merchant.address ?? '');
    // 使用 daddr（目的地地址）启动导航，地图上会显示实际地址
    final uri = Uri.parse('https://maps.google.com/?daddr=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _callPhone() async {
    if (merchant.phone == null) return;
    final uri = Uri(scheme: 'tel', path: merchant.phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  IconData _facilityIcon(String type) {
    return switch (type) {
      'parking' => Icons.local_parking,
      'wifi' => Icons.wifi,
      'private_room' => Icons.meeting_room,
      'large_table' => Icons.table_restaurant,
      'reservation' => Icons.event_available,
      'baby_chair' => Icons.child_care,
      'no_smoking' => Icons.smoke_free,
      _ => Icons.check_circle_outline,
    };
  }
}

/// 圆形操作按钮（导航/电话）
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CircleButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: disabled
              ? AppColors.surfaceVariant
              : AppColors.secondary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 18,
          color: disabled ? AppColors.textHint : AppColors.secondary,
        ),
      ),
    );
  }
}
