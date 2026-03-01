import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../deals/data/models/deal_model.dart';

// Provider to fetch merchant with their deals
final merchantDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, merchantId) async {
  final client = ref.watch(supabaseClientProvider);
  final merchant = await client
      .from('merchants')
      .select('*, deals(*)')
      .eq('id', merchantId)
      .single();
  return merchant;
});

class MerchantDetailScreen extends ConsumerStatefulWidget {
  final String merchantId;

  const MerchantDetailScreen({super.key, required this.merchantId});

  @override
  ConsumerState<MerchantDetailScreen> createState() =>
      _MerchantDetailScreenState();
}

class _MerchantDetailScreenState
    extends ConsumerState<MerchantDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final merchantAsync = ref.watch(merchantDetailProvider(widget.merchantId));

    return merchantAsync.when(
      data: (data) => _MerchantBody(data: data, tabCtrl: _tabCtrl),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _MerchantBody extends StatelessWidget {
  final Map<String, dynamic> data;
  final TabController tabCtrl;

  const _MerchantBody({required this.data, required this.tabCtrl});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? '';
    final address = data['address'] as String? ?? '';
    final hours = data['hours'] as String? ?? '';
    final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
    final reviewCount = data['reviews_count'] as int? ?? 0;
    final logoUrl = data['logo_url'] as String?;
    final rawDeals = data['deals'] as List? ?? [];

    final deals = rawDeals.map((d) {
      // Parse the deal JSON from Supabase join
      final map = Map<String, dynamic>.from(d as Map);
      // Provide defaults for required fields
      map['image_urls'] ??= <String>[];
      map['expires_at'] ??=
          DateTime.now().add(const Duration(days: 1)).toIso8601String();
      map['stock_limit'] ??= 100;
      return DealModel.fromJson(map);
    }).toList();

    // Photo list: logo + placeholder interiors
    final photos = [
      ?logoUrl,
      'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=800&q=80',
      'https://images.unsplash.com/photo-1552566626-52f8b828add9?auto=format&fit=crop&w=800&q=80',
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          // ── Top bar ───────────────────────────────────
          SliverAppBar(
            pinned: true,
            leading: GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back,
                    color: AppColors.textSecondary, size: 20),
              ),
            ),
            actions: [
              _ActionBtn(Icons.search),
              _ActionBtn(Icons.favorite_border),
              _ActionBtn(Icons.share_outlined),
              const SizedBox(width: 8),
            ],
            backgroundColor: AppColors.background.withValues(alpha: 0.95),
            surfaceTintColor: Colors.transparent,
          ),

          // ── Photo strip ───────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CachedNetworkImage(
                    imageUrl: photos[i],
                    width: 240,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),

          // ── Merchant info ─────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      const SizedBox(width: 6),
                      Text('$reviewCount reviews',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                      const SizedBox(width: 6),
                      const Text('·',
                          style: TextStyle(color: AppColors.textHint)),
                      const SizedBox(width: 6),
                      const Text('2k+ saved',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Hours + parking
                  Row(
                    children: [
                      const Icon(Icons.schedule_outlined,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(hours,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(width: 12),
                      const Icon(Icons.local_parking,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      const Text('Parking available',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Address card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.surfaceVariant),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(address,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500)),
                              const Text('1.2 km away',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Action buttons
                        Row(
                          children: [
                            _MerchantAction(
                                icon: Icons.directions_car_outlined,
                                label: 'Drive'),
                            const SizedBox(width: 16),
                            _MerchantAction(
                                icon: Icons.call_outlined, label: 'Call'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ── Tab bar ───────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: tabCtrl,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(text: 'Deals'),
                  Tab(text: 'Dishes'),
                  Tab(text: 'Reviews'),
                ],
              ),
            ),
          ),
        ],

        body: TabBarView(
          controller: tabCtrl,
          children: [
            // ── Deals tab ─────────────────────────────
            deals.isEmpty
                ? const Center(child: Text('No deals available'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: deals.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _DealRow(deal: deals[i]),
                  ),

            // ── Dishes tab ────────────────────────────
            Builder(
              builder: (_) {
                final allDishes = deals.expand((d) => d.dishes).toList();
                if (allDishes.isEmpty) {
                  return const Center(child: Text('No dish info available'));
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: allDishes.length,
                  itemBuilder: (_, i) => _DishCard(name: allDishes[i]),
                );
              },
            ),

            // ── Reviews tab ───────────────────────────
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ReviewCard(
                  name: 'Sarah Jenkins',
                  rating: 5,
                  text:
                      '"The meal was absolutely divine. Every dish was a work of art. Incredible value!"',
                ),
                const SizedBox(height: 12),
                _ReviewCard(
                  name: 'Michael Chen',
                  rating: 4,
                  text:
                      '"Great atmosphere and even better food. Will definitely come back soon!"',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;

  const _ActionBtn(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: AppColors.textSecondary),
    );
  }
}

class _MerchantAction extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MerchantAction({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(height: 2),
        Text(label,
            style:
                const TextStyle(fontSize: 10, color: AppColors.primary)),
      ],
    );
  }
}

class _DealRow extends StatelessWidget {
  final DealModel deal;

  const _DealRow({required this.deal});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/deals/${deal.id}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Row(
          children: [
            if (deal.imageUrls.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: deal.imageUrls.first,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(deal.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('${deal.totalSold}+ sold this season',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            '\$${deal.discountPrice.toStringAsFixed(0)}',
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 18),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '\$${deal.originalPrice.toStringAsFixed(0)}',
                            style: const TextStyle(
                                color: AppColors.textHint,
                                fontSize: 11,
                                decoration: TextDecoration.lineThrough),
                          ),
                        ],
                      ),
                      ElevatedButton(
                        onPressed: () => context.push('/deals/${deal.id}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(60, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          textStyle: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        child: const Text('Buy'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DishCard extends StatelessWidget {
  final String name;

  const _DishCard({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            child: CachedNetworkImage(
              imageUrl:
                  'https://picsum.photos/seed/${name.hashCode}/300/200',
              height: 100,
              width: double.infinity,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => Container(
                height: 100,
                color: AppColors.surfaceVariant,
                child: const Icon(Icons.restaurant,
                    color: AppColors.textHint),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                const Text('\$18–32',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final String name;
  final int rating;
  final String text;

  const _ReviewCard(
      {required this.name, required this.rating, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: List.generate(
                    5,
                    (i) => Icon(Icons.star,
                        size: 14,
                        color: i < rating
                            ? AppColors.featuredBadge
                            : AppColors.textHint)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(text,
              style: const TextStyle(
                  color: AppColors.textSecondary, height: 1.5)),
        ],
      ),
    );
  }
}

// SliverPersistentHeader delegate for TabBar
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(
        color: AppColors.background.withValues(alpha: 0.98),
        child: tabBar,
      );

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}
