import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/merchant_photo_model.dart';
import '../../data/models/store_facility_model.dart';
import 'facility_card.dart';

/// Services Tab 整体容器
/// 接收环境照片分组 Map 和设施列表，分区块展示
class ServicesSection extends StatelessWidget {
  /// 按 category 分组的环境照片
  final Map<String, List<MerchantPhotoModel>> environmentPhotos;

  /// 所有设施列表
  final List<StoreFacilityModel> facilities;

  const ServicesSection({
    super.key,
    required this.environmentPhotos,
    required this.facilities,
  });

  @override
  Widget build(BuildContext context) {
    // 判断各类型设施是否存在
    final privateRooms =
        facilities.where((f) => f.facilityType == 'private_room').toList();
    final parking =
        facilities.where((f) => f.facilityType == 'parking').toList();
    final others = facilities
        .where((f) => f.facilityType != 'private_room' && f.facilityType != 'parking')
        .toList();

    final hasAnyContent = environmentPhotos.isNotEmpty ||
        privateRooms.isNotEmpty ||
        parking.isNotEmpty ||
        others.isNotEmpty;

    if (!hasAnyContent) {
      return const Center(
        child: Text(
          'No service info available',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section 1: Environment 环境照片
          if (environmentPhotos.isNotEmpty) ...[
            _buildSectionTitle('Environment'),
            const SizedBox(height: 10),
            _buildEnvironmentPhotos(),
            const SizedBox(height: 20),
          ],

          // Section 2: Private Rooms（仅在有包间设施时显示）
          if (privateRooms.isNotEmpty) ...[
            _buildSectionTitle('Private Rooms'),
            const SizedBox(height: 10),
            _buildFacilityList(privateRooms),
            const SizedBox(height: 20),
          ],

          // Section 3: Parking 停车信息
          if (parking.isNotEmpty) ...[
            _buildSectionTitle('Parking'),
            const SizedBox(height: 10),
            _buildFacilityList(parking),
            const SizedBox(height: 20),
          ],

          // Section 4: Other Services 其他设施
          if (others.isNotEmpty) ...[
            _buildSectionTitle('Other Services'),
            const SizedBox(height: 10),
            _buildOtherFacilities(others),
          ],
        ],
      ),
    );
  }

  /// 区块标题
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  /// 环境照片横滑列表（扁平展开所有分组照片，每张带 categoryLabel 标签）
  Widget _buildEnvironmentPhotos() {
    // 将所有分组的照片合并为一个列表
    final allPhotos = environmentPhotos.values.expand((list) => list).toList();

    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: allPhotos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final photo = allPhotos[index];
          return _EnvironmentPhotoCard(photo: photo);
        },
      ),
    );
  }

  /// 设施横滑列表（使用 FacilityCard）
  Widget _buildFacilityList(List<StoreFacilityModel> items) {
    return SizedBox(
      // 有图片的卡片高度更大，取最大预估高度
      height: items.any((f) => f.imageUrl != null) ? 220 : 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) => FacilityCard(facility: items[index]),
      ),
    );
  }

  /// 其他设施：用 Chip 展示（圆角 20，surfaceVariant 背景）
  Widget _buildOtherFacilities(List<StoreFacilityModel> items) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items
            .map(
              (f) => Chip(
                avatar: Icon(
                  _resolveIcon(f.iconName),
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                label: Text(
                  f.name,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                backgroundColor: AppColors.surfaceVariant,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide.none,
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  /// 将 iconName 字符串转换为 IconData
  IconData _resolveIcon(String iconName) {
    return switch (iconName) {
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

/// 单张环境照片卡片（宽 200，底部叠加半透明标签）
class _EnvironmentPhotoCard extends StatelessWidget {
  final MerchantPhotoModel photo;

  const _EnvironmentPhotoCard({required this.photo});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 200,
        height: 150,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 照片
            CachedNetworkImage(
              imageUrl: photo.photoUrl,
              fit: BoxFit.cover,
              // Shimmer 加载占位
              placeholder: (context, url) => Shimmer.fromColors(
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: Container(color: Colors.white),
              ),
              // 加载失败占位
              errorWidget: (context, url, error) => Container(
                color: AppColors.surfaceVariant,
                child: const Icon(
                  Icons.image_not_supported,
                  size: 36,
                  color: AppColors.textHint,
                ),
              ),
            ),
            // 底部半透明遮罩 + category 标签文字
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  photo.categoryLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
