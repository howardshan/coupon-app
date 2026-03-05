import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/store_detail_provider.dart';
import 'nearby_merchant_card.dart';

/// Recommended Tab 组件
/// 显示附近推荐商家列表，复用 NearbyMerchantCard
class RecommendedTab extends ConsumerStatefulWidget {
  final String merchantId;
  final double? lat;
  final double? lng;

  const RecommendedTab({
    super.key,
    required this.merchantId,
    this.lat,
    this.lng,
  });

  @override
  ConsumerState<RecommendedTab> createState() => _RecommendedTabState();
}

class _RecommendedTabState extends ConsumerState<RecommendedTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // 无坐标时无法查附近商家
    if (widget.lat == null || widget.lng == null) {
      return const Center(
        child: Text('Location not available',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final nearbyAsync = ref.watch(nearbyMerchantsProvider((
      merchantId: widget.merchantId,
      lat: widget.lat!,
      lng: widget.lng!,
    )));

    return nearbyAsync.when(
      data: (merchants) {
        if (merchants.isEmpty) {
          return const Center(
            child: Text('No nearby merchants found',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'You May Also Like',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => NearbyMerchantCard(merchant: merchants[i]),
                childCount: merchants.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: Text('Failed to load recommendations',
            style: TextStyle(color: AppColors.textSecondary)),
      ),
    );
  }
}
