// V2.4 品牌聚合详情页
// 展示品牌信息 + 旗下所有门店列表 + 聚合数据

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../data/models/brand_detail_model.dart';
import '../../domain/providers/merchant_provider.dart';

class BrandDetailScreen extends ConsumerWidget {
  final String brandId;
  const BrandDetailScreen({super.key, required this.brandId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brandAsync = ref.watch(brandDetailProvider(brandId));

    return Scaffold(
      body: brandAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text('Failed to load brand', style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 16),
              ElevatedButton(
                key: const ValueKey('brand_detail_retry_btn'),
                onPressed: () => ref.invalidate(brandDetailProvider(brandId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (brand) => CustomScrollView(
          slivers: [
            // 品牌 Header
            _BrandAppBar(brand: brand),
            // 聚合统计
            SliverToBoxAdapter(child: _BrandStats(brand: brand)),
            // 门店列表标题
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  '${brand.storeCount} Locations',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // 门店列表
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _StoreCard(store: brand.stores[index]),
                childCount: brand.stores.length,
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }
}

// 品牌 AppBar（含 Logo + 名称 + 描述）
class _BrandAppBar extends StatelessWidget {
  final BrandDetailModel brand;
  const _BrandAppBar({required this.brand});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          brand.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.orange[700]!, Colors.deepOrange[400]!],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                if (brand.logoUrl != null && brand.logoUrl!.isNotEmpty)
                  CircleAvatar(
                    radius: 36,
                    backgroundImage:
                        CachedNetworkImageProvider(brand.logoUrl!),
                  )
                else
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white24,
                    child: Text(
                      brand.name.isNotEmpty ? brand.name[0].toUpperCase() : 'B',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                if (brand.category != null && brand.category!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      brand.category!,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 品牌聚合统计
class _BrandStats extends StatelessWidget {
  final BrandDetailModel brand;
  const _BrandStats({required this.brand});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (brand.description != null && brand.description!.isNotEmpty) ...[
            Text(
              brand.description!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              _StatItem(
                icon: Icons.storefront,
                value: '${brand.storeCount}',
                label: 'Stores',
              ),
              _StatItem(
                icon: Icons.local_offer,
                value: '${brand.totalActiveDeals}',
                label: 'Deals',
              ),
              _StatItem(
                icon: Icons.star,
                value: brand.averageRating > 0
                    ? brand.averageRating.toStringAsFixed(1)
                    : '--',
                label: 'Rating',
              ),
              _StatItem(
                icon: Icons.rate_review,
                value: '${brand.totalReviews}',
                label: 'Reviews',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: Colors.orange[600]),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

// 门店卡片
class _StoreCard extends StatelessWidget {
  final BrandStoreModel store;
  const _StoreCard({required this.store});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/merchant/${store.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 门店封面
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: store.homepageCoverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: store.homepageCoverUrl!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          width: 72,
                          height: 72,
                          color: Colors.grey[200],
                          child: const Icon(Icons.storefront, color: Colors.grey),
                        ),
                        errorWidget: (_, _, _) => Container(
                          width: 72,
                          height: 72,
                          color: Colors.grey[200],
                          child: const Icon(Icons.storefront, color: Colors.grey),
                        ),
                      )
                    : Container(
                        width: 72,
                        height: 72,
                        color: Colors.grey[200],
                        child: const Icon(Icons.storefront, color: Colors.grey),
                      ),
              ),
              const SizedBox(width: 12),
              // 门店信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (store.address != null)
                      Text(
                        store.address!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (store.avgRating > 0) ...[
                          Icon(Icons.star, size: 14, color: Colors.amber[600]),
                          const SizedBox(width: 2),
                          Text(
                            store.avgRating.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(${store.reviewCount})',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (store.activeDealCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${store.activeDealCount} deals',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
