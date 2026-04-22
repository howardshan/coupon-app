import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/store_facility_model.dart';

/// 设施卡片
/// 无图片时：紧凑 chip（图标 + 名称），配合 Wrap 使用
/// 有图片时：宽 200 横滑卡片（图片 + 名称 + 描述 + 容量 + Free 标签）
class FacilityCard extends StatelessWidget {
  final StoreFacilityModel facility;

  const FacilityCard({super.key, required this.facility});

  @override
  Widget build(BuildContext context) {
    // 无图片：紧凑 chip 样式（图标 + 名称）
    if (facility.imageUrl == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_resolveIcon(), size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              facility.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );
    }

    // 有图片：完整卡片
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildImageSection(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildInfoSection(),
          ),
        ],
      ),
    );
  }

  /// 顶部图片区域，高 120，圆角顶部
  Widget _buildImageSection() {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(12),
        topRight: Radius.circular(12),
      ),
      child: CachedNetworkImage(
        imageUrl: facility.imageUrl!,
        height: 120,
        width: 200,
        fit: BoxFit.cover,
        placeholder: (context, url) => Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(height: 120, width: 200, color: Colors.white),
        ),
        errorWidget: (context, url, error) => Container(
          height: 120,
          width: 200,
          color: AppColors.surfaceVariant,
          child: const Icon(Icons.image_not_supported, size: 36, color: AppColors.textHint),
        ),
      ),
    );
  }

  /// 有图片时的信息区域：名称 + 描述 + 容量 + Free 标签
  Widget _buildInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          facility.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        if (facility.description != null && facility.description!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            facility.description!,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],

        if (facility.capacity != null) ...[
          const SizedBox(height: 4),
          Text(
            'Seats up to ${facility.capacity}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],

        if (facility.isFree) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Free',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.success,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  IconData _resolveIcon() {
    return switch (facility.iconName) {
      'meeting_room' => Icons.meeting_room,
      'local_parking' => Icons.local_parking,
      'wifi' => Icons.wifi,
      'child_care' => Icons.child_care,
      'table_restaurant' => Icons.table_restaurant,
      'smoke_free' => Icons.smoke_free,
      'event_available' => Icons.event_available,
      _ => Icons.info_outline,
    };
  }
}
