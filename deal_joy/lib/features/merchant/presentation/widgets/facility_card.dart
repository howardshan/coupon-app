import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/store_facility_model.dart';

/// 设施卡片
/// 宽 200，用于横滑列表；有图片时顶部展示图片，无图片时纯文字布局
class FacilityCard extends StatelessWidget {
  final StoreFacilityModel facility;

  const FacilityCard({super.key, required this.facility});

  @override
  Widget build(BuildContext context) {
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
          // 有图片时显示顶部图片区域
          if (facility.imageUrl != null) _buildImageSection(),
          // 信息区域
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildInfoSection(context),
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
        // Shimmer 加载占位
        placeholder: (context, url) => Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            height: 120,
            width: 200,
            color: Colors.white,
          ),
        ),
        // 加载失败占位
        errorWidget: (context, url, error) => Container(
          height: 120,
          width: 200,
          color: AppColors.surfaceVariant,
          child: const Icon(
            Icons.image_not_supported,
            size: 36,
            color: AppColors.textHint,
          ),
        ),
      ),
    );
  }

  /// 信息区域：图标 + 名称 + 描述 + 容量 + 免费标签
  Widget _buildInfoSection(BuildContext context) {
    // 无图片时在信息区域展示图标
    final showIcon = facility.imageUrl == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 无图片时：图标 + 名称同行
        if (showIcon)
          Row(
            children: [
              Icon(
                _resolveIcon(),
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  facility.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          )
        else
          // 有图片时：单独显示名称
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

        // 描述
        if (facility.description != null && facility.description!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            facility.description!,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],

        // 容量信息
        if (facility.capacity != null) ...[
          const SizedBox(height: 4),
          Text(
            'Seats up to ${facility.capacity}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],

        // 免费标签（仅 isFree 时显示绿色 badge）
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

  /// 将 iconName 字符串转换为 IconData
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
