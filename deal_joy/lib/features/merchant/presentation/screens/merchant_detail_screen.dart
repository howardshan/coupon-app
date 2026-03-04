import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../deals/data/models/deal_model.dart';
import '../../../deals/domain/providers/history_provider.dart';
import '../../data/models/merchant_detail_model.dart';
import '../../domain/providers/merchant_provider.dart';
import '../../domain/providers/store_detail_provider.dart';
import '../widgets/deal_card_horizontal.dart';
import '../widgets/deal_filter_bar.dart';
import '../widgets/menu_section.dart';
import '../widgets/nearby_merchant_card.dart';
import '../widgets/review_card.dart';
import '../widgets/review_stats_header.dart';
import '../widgets/services_section.dart';
import '../widgets/store_address_card.dart';
import '../widgets/store_feature_tags.dart';
import '../widgets/store_info_header.dart';
import '../widgets/store_photo_carousel.dart';

class MerchantDetailScreen extends ConsumerStatefulWidget {
  final String merchantId;

  const MerchantDetailScreen({super.key, required this.merchantId});

  @override
  ConsumerState<MerchantDetailScreen> createState() =>
      _MerchantDetailScreenState();
}

class _MerchantDetailScreenState extends ConsumerState<MerchantDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync =
        ref.watch(merchantDetailInfoProvider(widget.merchantId));

    // 记录浏览历史
    detailAsync.whenData((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(historyRepositoryProvider)
            .addMerchantToHistory(widget.merchantId);
      });
    });

    return detailAsync.when(
      data: (merchant) => _MerchantDetailBody(
        merchant: merchant,
        tabCtrl: _tabCtrl,
      ),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

// ── 主体内容 ────────────────────────────────────────────────

class _MerchantDetailBody extends ConsumerWidget {
  final MerchantDetailModel merchant;
  final TabController tabCtrl;

  const _MerchantDetailBody({
    required this.merchant,
    required this.tabCtrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          // ── 顶部导航栏 ─────────────────────────────────
          SliverAppBar(
            pinned: true,
            leading: GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
            ),
            actions: [
              _SaveMerchantBtn(merchantId: merchant.id),
              _ActionBtn(
                Icons.share_outlined,
                onTap: () {
                  // 分享功能（后续扩展）
                },
              ),
              const SizedBox(width: 8),
            ],
            backgroundColor:
                AppColors.background.withValues(alpha: 0.95),
            surfaceTintColor: Colors.transparent,
          ),

          // ── 图片轮播 ─────────────────────────────────
          SliverToBoxAdapter(
            child: StorePhotoCarousel(photoUrls: merchant.allPhotoUrls),
          ),

          // ── 商家信息头部 ──────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: StoreInfoHeader(
                name: merchant.name,
                avgRating: 0, // 由 reviewStatsProvider 补充
                reviewCount: 0,
                pricePerPerson: merchant.pricePerPerson,
                isOpenNow: merchant.isOpenNow,
                todayHoursText: merchant.todayHoursText,
                yearsInBusiness: merchant.yearsInBusiness,
              ),
            ),
          ),

          // ── 特色标签 ──────────────────────────────────
          if (merchant.tags.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: StoreFeatureTags(tags: merchant.tags),
              ),
            ),

          // ── 地址卡片 ──────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: StoreAddressCard(
                address: merchant.address ?? '',
                lat: merchant.lat,
                lng: merchant.lng,
                phone: merchant.phone,
              ),
            ),
          ),

          // ── 粘性 Tab 导航 ─────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: tabCtrl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(text: 'Deals'),
                  Tab(text: 'Menu'),
                  Tab(text: 'Services'),
                  Tab(text: 'Reviews'),
                  Tab(text: 'More'),
                ],
              ),
            ),
          ),
        ],

        // ── Tab 内容 ────────────────────────────────────
        body: TabBarView(
          controller: tabCtrl,
          children: [
            _DealsTab(merchantId: merchant.id),
            _MenuTab(merchantId: merchant.id),
            _ServicesTab(merchant: merchant),
            _ReviewsTab(merchantId: merchant.id),
            _MoreTab(merchant: merchant),
          ],
        ),
      ),
    );
  }
}

// ── Deals Tab ───────────────────────────────────────────────

class _DealsTab extends ConsumerStatefulWidget {
  final String merchantId;

  const _DealsTab({required this.merchantId});

  @override
  ConsumerState<_DealsTab> createState() => _DealsTabState();
}

class _DealsTabState extends ConsumerState<_DealsTab>
    with AutomaticKeepAliveClientMixin {
  String _selectedFilter = 'All';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final dealsAsync = ref.watch(merchantActiveDealsProvider(widget.merchantId));

    return dealsAsync.when(
      data: (deals) {
        if (deals.isEmpty) {
          return const Center(
            child: Text(
              'No deals available',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }

        // 过滤
        final filtered = _filterDeals(deals, _selectedFilter);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DealFilterBar(
              selectedFilter: _selectedFilter,
              onFilterChanged: (f) => setState(() => _selectedFilter = f),
            ),
            const SizedBox(height: 12),
            ...filtered.map(
              (deal) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DealCardHorizontal(deal: deal),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  List<DealModel> _filterDeals(List<DealModel> deals, String filter) {
    if (filter == 'All') return deals;
    // 根据 deal 标题/描述中的关键词粗略过滤
    final keyword = filter.toLowerCase();
    return deals.where((d) {
      final text = '${d.title} ${d.description}'.toLowerCase();
      return text.contains(keyword.replaceAll('-', ' '));
    }).toList();
  }
}

// ── Menu Tab ────────────────────────────────────────────────

class _MenuTab extends ConsumerStatefulWidget {
  final String merchantId;

  const _MenuTab({required this.merchantId});

  @override
  ConsumerState<_MenuTab> createState() => _MenuTabState();
}

class _MenuTabState extends ConsumerState<_MenuTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final menuAsync = ref.watch(menuItemsProvider(widget.merchantId));

    return menuAsync.when(
      data: (groupedItems) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: MenuSection(groupedItems: groupedItems),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ── Services Tab ────────────────────────────────────────────

class _ServicesTab extends ConsumerStatefulWidget {
  final MerchantDetailModel merchant;

  const _ServicesTab({required this.merchant});

  @override
  ConsumerState<_ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends ConsumerState<_ServicesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final facilitiesAsync =
        ref.watch(facilitiesProvider(widget.merchant.id));

    return facilitiesAsync.when(
      data: (facilities) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: ServicesSection(
          environmentPhotos: widget.merchant.environmentPhotos,
          facilities: facilities,
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ── Reviews Tab ─────────────────────────────────────────────

class _ReviewsTab extends ConsumerStatefulWidget {
  final String merchantId;

  const _ReviewsTab({required this.merchantId});

  @override
  ConsumerState<_ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends ConsumerState<_ReviewsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final statsAsync = ref.watch(reviewStatsProvider(widget.merchantId));
    final reviewsAsync = ref.watch(merchantReviewsProvider(widget.merchantId));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 评价统计
        statsAsync.when(
          data: (stats) => ReviewStatsHeader(stats: stats),
          loading: () => const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),

        // 评价列表
        reviewsAsync.when(
          data: (reviews) {
            if (reviews.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(
                  child: Text(
                    'No reviews yet. Be the first to review!',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              );
            }
            return Column(
              children: [
                ...reviews.map(
                  (review) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ReviewCard(review: review),
                  ),
                ),
                // 加载更多按钮
                if (ref
                    .read(merchantReviewsProvider(widget.merchantId).notifier)
                    .hasMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton(
                      onPressed: () => ref
                          .read(merchantReviewsProvider(widget.merchantId)
                              .notifier)
                          .loadMore(),
                      child: const Text('Load More Reviews'),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ],
    );
  }
}

// ── More Tab ────────────────────────────────────────────────

class _MoreTab extends ConsumerStatefulWidget {
  final MerchantDetailModel merchant;

  const _MoreTab({required this.merchant});

  @override
  ConsumerState<_MoreTab> createState() => _MoreTabState();
}

class _MoreTabState extends ConsumerState<_MoreTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lat = widget.merchant.lat;
    final lng = widget.merchant.lng;

    if (lat == null || lng == null) {
      return const Center(
        child: Text(
          'Location not available',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    final nearbyAsync = ref.watch(nearbyMerchantsProvider((
      merchantId: widget.merchant.id,
      lat: lat,
      lng: lng,
    )));

    return nearbyAsync.when(
      data: (merchants) {
        if (merchants.isEmpty) {
          return const Center(
            child: Text(
              'No nearby stores found',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'More Recommendations',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...merchants.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NearbyMerchantCard(merchant: m),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ── 通用小组件（复用自旧版）─────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _ActionBtn(this.icon, {this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: AppColors.surfaceVariant,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: AppColors.textSecondary),
      ),
    );
  }
}

// ── 收藏商家按钮 ────────────────────────────────────────────

class _SaveMerchantBtn extends ConsumerWidget {
  final String merchantId;

  const _SaveMerchantBtn({required this.merchantId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedIds = ref.watch(savedMerchantIdsProvider).valueOrNull ?? {};
    final isSaved = savedIds.contains(merchantId);

    return GestureDetector(
      onTap: () => ref
          .read(savedMerchantsNotifierProvider.notifier)
          .toggle(merchantId),
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: AppColors.surfaceVariant,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isSaved ? Icons.favorite : Icons.favorite_border,
          size: 18,
          color: isSaved ? Colors.red : AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ── SliverPersistentHeader TabBar 代理 ──────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      Container(
        color: AppColors.background.withValues(alpha: 0.98),
        child: tabBar,
      );

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}
