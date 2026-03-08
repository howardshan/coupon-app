import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/store_detail_provider.dart';
import 'nearby_merchant_card.dart';

/// Recommended Tab 组件
/// 显示同品牌其他门店 + 附近推荐商家列表
class RecommendedTab extends ConsumerStatefulWidget {
  final String merchantId;
  final double? lat;
  final double? lng;
  final String? brandId;

  const RecommendedTab({
    super.key,
    required this.merchantId,
    this.lat,
    this.lng,
    this.brandId,
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

    final hasLocation = widget.lat != null && widget.lng != null;
    final hasBrand = widget.brandId != null;

    // 无坐标且无品牌 → 无内容
    if (!hasLocation && !hasBrand) {
      return const Center(
        child: Text('Location not available',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return CustomScrollView(
      slivers: [
        // ── 同品牌其他门店 ──────────────────────────────
        if (hasBrand) _buildBrandStoresSection(),

        // ── 附近推荐商家 ────────────────────────────────
        if (hasLocation) _buildNearbySection(),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  Widget _buildBrandStoresSection() {
    final storesAsync = ref.watch(sameBrandStoresProvider((
      brandId: widget.brandId!,
      merchantId: widget.merchantId,
    )));

    return storesAsync.when(
      data: (stores) {
        if (stores.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.store, size: 18, color: AppColors.secondary),
                    const SizedBox(width: 6),
                    Text(
                      'Other Locations (${stores.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _BrandStoreCard(
                  store: stores[i],
                  onTap: () {
                    final id = stores[i]['id'] as String;
                    context.push('/merchant/$id');
                  },
                ),
                childCount: stores.length,
              ),
            ),
            // 分隔线
            const SliverToBoxAdapter(
              child: Divider(height: 24, indent: 16, endIndent: 16),
            ),
          ],
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: Center(child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        )),
      ),
      error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }

  Widget _buildNearbySection() {
    final nearbyAsync = ref.watch(nearbyMerchantsProvider((
      merchantId: widget.merchantId,
      lat: widget.lat!,
      lng: widget.lng!,
    )));

    return nearbyAsync.when(
      data: (merchants) {
        if (merchants.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: const Text(
                  'You May Also Like',
                  style: TextStyle(
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
          ],
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: Center(child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        )),
      ),
      error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }
}

// ── 同品牌门店卡片 ──────────────────────────────────────────
class _BrandStoreCard extends StatelessWidget {
  final Map<String, dynamic> store;
  final VoidCallback? onTap;

  const _BrandStoreCard({required this.store, this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = store['name'] as String? ?? '';
    final address = store['address'] as String?;
    final logoUrl = store['logo_url'] as String?;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Logo
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: logoUrl != null
                  ? Image.network(
                      logoUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _placeholderIcon(),
                    )
                  : _placeholderIcon(),
            ),
            const SizedBox(width: 12),
            // 名称 + 地址
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (address != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      address,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _placeholderIcon() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.store, color: AppColors.secondary, size: 24),
    );
  }
}
