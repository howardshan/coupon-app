import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/merchant_detail_model.dart';
import '../../data/models/merchant_hour_model.dart';
import '../../data/models/merchant_photo_model.dart';
import '../../data/models/store_facility_model.dart';
import '../../domain/providers/store_detail_provider.dart';
import 'facility_card.dart';

/// About Tab 组件
/// 包含：环境照片、设施服务、商家描述、完整营业时间、停车/WiFi 信息
class AboutTab extends ConsumerStatefulWidget {
  final String merchantId;

  const AboutTab({super.key, required this.merchantId});

  @override
  ConsumerState<AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends ConsumerState<AboutTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final merchantAsync =
        ref.watch(merchantDetailInfoProvider(widget.merchantId));
    final facilitiesAsync =
        ref.watch(facilitiesProvider(widget.merchantId));

    return merchantAsync.when(
      data: (merchant) {
        final facilities = facilitiesAsync.valueOrNull ?? [];
        return _buildContent(merchant, facilities);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Failed to load info',
            style: TextStyle(color: AppColors.textSecondary)),
      ),
    );
  }

  Widget _buildContent(
      MerchantDetailModel merchant, List<StoreFacilityModel> facilities) {
    final envPhotos = merchant.environmentPhotos;
    final allEnvPhotos =
        envPhotos.values.expand((list) => list).toList();

    return CustomScrollView(
      slivers: [
        // 环境照片
        if (allEnvPhotos.isNotEmpty) ...[
          _sectionTitle('Environment'),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: allEnvPhotos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) =>
                    _EnvironmentCard(photo: allEnvPhotos[i]),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],

        // 设施服务
        if (facilities.isNotEmpty) ...[
          _sectionTitle('Facilities & Services'),
          SliverToBoxAdapter(
            child: SizedBox(
              height: facilities.any((f) => f.imageUrl != null) ? 220 : 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: facilities.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) =>
                    FacilityCard(facility: facilities[i]),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],

        // 商家描述
        if (merchant.description != null &&
            merchant.description!.isNotEmpty) ...[
          _sectionTitle('About'),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                merchant.description!,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],

        // 完整营业时间表
        if (merchant.hours.isNotEmpty) ...[
          _sectionTitle('Business Hours'),
          SliverToBoxAdapter(
            child: _BusinessHoursTable(hours: merchant.hours),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],

        // 停车信息
        if (merchant.parkingInfo != null &&
            merchant.parkingInfo!.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _InfoRow(
              icon: Icons.local_parking,
              label: 'Parking',
              value: merchant.parkingInfo!,
            ),
          ),
        ],

        // WiFi
        if (merchant.wifi)
          SliverToBoxAdapter(
            child: _InfoRow(
              icon: Icons.wifi,
              label: 'WiFi',
              value: 'Free WiFi available',
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  SliverToBoxAdapter _sectionTitle(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
      ),
    );
  }
}

/// 环境照片卡片
class _EnvironmentCard extends StatelessWidget {
  final MerchantPhotoModel photo;

  const _EnvironmentCard({required this.photo});

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
            CachedNetworkImage(
              imageUrl: photo.photoUrl,
              fit: BoxFit.cover,
              placeholder: (_, _) => Shimmer.fromColors(
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: Container(color: Colors.white),
              ),
              errorWidget: (_, _, _) => Container(
                color: AppColors.surfaceVariant,
                child: const Icon(Icons.image_not_supported,
                    size: 36, color: AppColors.textHint),
              ),
            ),
            // 底部标签
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

/// 营业时间表
class _BusinessHoursTable extends StatelessWidget {
  final List<MerchantHourModel> hours;

  const _BusinessHoursTable({required this.hours});

  static const _dayNames = [
    'Sunday', 'Monday', 'Tuesday', 'Wednesday',
    'Thursday', 'Friday', 'Saturday',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayDow = now.weekday == 7 ? 0 : now.weekday;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: List.generate(7, (dow) {
            final hour =
                hours.where((h) => h.dayOfWeek == dow).firstOrNull;
            final isToday = dow == todayDow;
            final text = hour?.displayText ?? 'Hours not set';

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      _dayNames[dow],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isToday ? FontWeight.bold : FontWeight.normal,
                        color: isToday
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isToday ? FontWeight.bold : FontWeight.normal,
                        color: isToday
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (isToday)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Today',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// 单行信息展示（停车、WiFi 等）
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
