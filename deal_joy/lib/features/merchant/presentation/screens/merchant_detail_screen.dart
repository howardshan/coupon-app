import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/location_utils.dart';
import '../../../deals/domain/providers/deals_provider.dart';
import '../../../deals/domain/providers/history_provider.dart';
import '../../data/models/merchant_detail_model.dart';
import '../../data/models/merchant_hour_model.dart';
import '../../data/models/merchant_photo_model.dart';
import '../../data/models/menu_item_model.dart';
import '../../data/models/store_facility_model.dart';
import '../../domain/providers/merchant_provider.dart';
import '../../domain/providers/store_detail_provider.dart';
import '../widgets/deal_card_v2.dart';
import '../widgets/deal_category_filter.dart';
import '../widgets/deal_voucher_section.dart';
import '../widgets/facility_card.dart';
import '../widgets/menu_item_card.dart';
import '../widgets/nearby_merchant_card.dart';
import '../widgets/review_card.dart';
import '../widgets/review_stats_header.dart';
import '../widgets/store_bottom_bar.dart';
import '../widgets/store_info_card.dart';
import '../widgets/store_photo_header.dart';

// Tab 顺序常量
const _kTabCount = 5;
const _kTabDeals = 0;
const _kTabMenu = 1;
const _kTabAbout = 2;
const _kTabReviews = 3;
const _kTabRecommended = 4;


class MerchantDetailScreen extends ConsumerStatefulWidget {
  final String merchantId;

  const MerchantDetailScreen({super.key, required this.merchantId});

  @override
  ConsumerState<MerchantDetailScreen> createState() =>
      _MerchantDetailScreenState();
}

class _MerchantDetailScreenState extends ConsumerState<MerchantDetailScreen> {
  // ScrollController 用于监听滚动位置
  final ScrollController _scrollController = ScrollController();

  // 当前高亮的 tab index
  int _currentTab = 0;

  // 点击 tab 跳转时设为 true，防止滚动过程中 tab 来回闪烁
  bool _isTabClick = false;

  // 每个区块的 GlobalKey，用于获取 RenderBox 位置
  final List<GlobalKey> _sectionKeys = List.generate(
    _kTabCount,
    (_) => GlobalKey(),
  );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // 监听滚动，自动更新当前 tab
  void _onScroll() {
    if (_isTabClick) return;
    _updateCurrentTab();
  }

  // 根据各区块在 viewport 中的位置计算当前 tab
  // 策略：找最后一个区块顶部已滚过 tabbar 底部的区块
  void _updateCurrentTab() {
    int activeIndex = 0;
    // AppBar(56) + TabBar(48) + 一点余量 = 约 120dp
    const tabBarBottom = 120.0;
    for (int i = 0; i < _kTabCount; i++) {
      final ctx = _sectionKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final topY = box.localToGlobal(Offset.zero).dy;
      if (topY <= tabBarBottom) {
        activeIndex = i;
      }
    }

    if (activeIndex != _currentTab) {
      setState(() => _currentTab = activeIndex);
    }
  }

  // 点击 tab，滚动到对应区块
  Future<void> _scrollToSection(int index) async {
    final ctx = _sectionKeys[index].currentContext;
    if (ctx == null) return;

    setState(() {
      _currentTab = index;
      _isTabClick = true;
    });

    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      // alignmentPolicy 让区块尽量靠近顶部
      alignment: 0.0,
    );

    // 动画结束后恢复滚动监听
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _isTabClick = false);
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync =
        ref.watch(merchantDetailInfoProvider(widget.merchantId));
    final reviewStatsAsync =
        ref.watch(reviewStatsProvider(widget.merchantId));
    final facilitiesAsync =
        ref.watch(facilitiesProvider(widget.merchantId));
    final dealsAsync =
        ref.watch(merchantActiveDealsProvider(widget.merchantId));

    // 记录浏览历史
    detailAsync.whenData((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(historyRepositoryProvider)
            .addMerchantToHistory(widget.merchantId);
      });
    });

    // 收藏状态
    final savedIds = ref.watch(savedMerchantIdsProvider).valueOrNull ?? {};
    final isSaved = savedIds.contains(widget.merchantId);

    // 计算用户与商家的距离（GPS 可用时）
    final userLoc = ref.watch(userLocationProvider).valueOrNull;

    return detailAsync.when(
      data: (merchant) {
        final reviewStats = reviewStatsAsync.valueOrNull;
        final facilities = facilitiesAsync.valueOrNull ?? [];
        final deals = dealsAsync.valueOrNull ?? [];
        final reviewCount = reviewStats?.totalCount ?? 0;

        // 构建带 review count 的 tab 标签列表
        final tabLabels = [
          'Deals',
          'Menu',
          'About',
          reviewCount > 0 ? 'Reviews ($reviewCount)' : 'Reviews',
          'Recommended',
        ];

        return Scaffold(
          backgroundColor: AppColors.background,
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // ── SliverAppBar: 头图 ────────────────────────────────
              SliverAppBar(
                pinned: true,
                expandedHeight: merchant.useTripleHeader ? 200 : 250,
                leading: _BackButton(),
                actions: [
                  _ActionBtn(
                    Icons.favorite,
                    isFilled: isSaved,
                    onTap: () => ref
                        .read(savedMerchantsNotifierProvider.notifier)
                        .toggle(widget.merchantId),
                  ),
                  _ActionBtn(Icons.share_outlined, onTap: () {}),
                  const SizedBox(width: 8),
                ],
                backgroundColor:
                    AppColors.background.withValues(alpha: 0.95),
                surfaceTintColor: Colors.transparent,
                title: Text(
                  merchant.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: StorePhotoHeader(
                    merchant: merchant,
                    onPhotosPressed: () =>
                        context.push('/merchant/${widget.merchantId}/photos'),
                  ),
                ),
              ),

              // ── 商家信息卡片（圆角上移覆盖图片底部）──────────────────
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: const Offset(0, -16),
                  child: StoreInfoCard(
                    merchant: merchant,
                    reviewStats: reviewStats,
                    facilities: facilities,
                    distanceMiles: (userLoc != null &&
                            merchant.lat != null &&
                            merchant.lng != null)
                        ? haversineDistanceMiles(
                            userLoc.lat, userLoc.lng,
                            merchant.lat!, merchant.lng!)
                        : null,
                  ),
                ),
              ),

              // ── 分隔（补偿上移的 16px）─────────────────────────────
              const SliverToBoxAdapter(child: SizedBox(height: 0)),

              // ── Tab 栏（吸顶）────────────────────────────────────
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  _StickyTabBar(
                    labels: tabLabels,
                    currentIndex: _currentTab,
                    onTap: _scrollToSection,
                  ),
                ),
              ),

              // ══════════════════════════════════════════════════════
              //  区块 1: Deals
              // ══════════════════════════════════════════════════════
              SliverToBoxAdapter(
                child: _SectionDivider(
                    key: _sectionKeys[_kTabDeals], label: 'Deals'),
              ),
              _buildDealsSection(),

              // ══════════════════════════════════════════════════════
              //  区块 2: Menu
              // ══════════════════════════════════════════════════════
              SliverToBoxAdapter(
                child: _SectionDivider(
                    key: _sectionKeys[_kTabMenu], label: 'Menu'),
              ),
              _buildMenuSection(),

              // ══════════════════════════════════════════════════════
              //  区块 3: About
              // ══════════════════════════════════════════════════════
              SliverToBoxAdapter(
                child: _SectionDivider(
                    key: _sectionKeys[_kTabAbout], label: 'About'),
              ),
              _buildAboutSection(merchant, facilities),

              // ══════════════════════════════════════════════════════
              //  区块 4: Reviews
              // ══════════════════════════════════════════════════════
              SliverToBoxAdapter(
                child: _SectionDivider(
                    key: _sectionKeys[_kTabReviews], label: 'Reviews'),
              ),
              _buildReviewsSection(),

              // ══════════════════════════════════════════════════════
              //  区块 5: Recommended
              // ══════════════════════════════════════════════════════
              SliverToBoxAdapter(
                child: _SectionDivider(
                    key: _sectionKeys[_kTabRecommended],
                    label: 'Recommended'),
              ),
              _buildRecommendedSection(
                lat: merchant.lat,
                lng: merchant.lng,
                brandId: merchant.brandId,
              ),

              // ── 底部留白 ──────────────────────────────────────────
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),

          // ── 底部操作栏 ────────────────────────────────────────────
          bottomNavigationBar: StoreBottomBar(
            merchantId: widget.merchantId,
            phone: merchant.phone,
            deals: deals,
            isSaved: isSaved,
            onToggleSave: () => ref
                .read(savedMerchantsNotifierProvider.notifier)
                .toggle(widget.merchantId),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }

  // ── Deals 区块内容 ──────────────────────────────────────────
  Widget _buildDealsSection() {
    final dealsAsync =
        ref.watch(merchantActiveDealsProvider(widget.merchantId));
    final categoriesAsync =
        ref.watch(dealCategoriesProvider(widget.merchantId));
    final selectedCategory =
        ref.watch(selectedDealCategoryProvider(widget.merchantId));
    final filtered = ref.watch(filteredDealsProvider(widget.merchantId));

    // 加载中
    if (dealsAsync.isLoading) {
      return const SliverToBoxAdapter(
        child: SizedBox(
          height: 100,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.secondary),
          ),
        ),
      );
    }

    // 加载出错
    if (dealsAsync.hasError) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              'Failed to load deals',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ),
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        // 代金券区域
        if (filtered.vouchers.isNotEmpty)
          SliverToBoxAdapter(
            child: DealVoucherSection(vouchers: filtered.vouchers),
          ),

        // 分类标签 — 普通 sliver（不再二级吸顶）
        categoriesAsync.when(
          data: (categories) {
            if (categories.isEmpty) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }
            return SliverToBoxAdapter(
              child: DealCategoryFilter(
                categories: categories,
                selectedCategoryId: selectedCategory,
                onSelected: (id) => ref
                    .read(selectedDealCategoryProvider(widget.merchantId)
                        .notifier)
                    .state = id,
              ),
            );
          },
          loading: () => const SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
          error: (_, _) =>
              const SliverToBoxAdapter(child: SizedBox.shrink()),
        ),

        // Deal 列表或空状态
        if (filtered.vouchers.isEmpty && filtered.regulars.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.local_offer_outlined,
                        size: 48, color: AppColors.textHint),
                    const SizedBox(height: 12),
                    Text(
                      selectedCategory != null
                          ? 'No deals in this category'
                          : 'No deals available',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (filtered.regulars.isNotEmpty)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  DealCardV2(deal: filtered.regulars[index]),
              childCount: filtered.regulars.length,
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }

  // ── Menu 区块内容 ──────────────────────────────────────────
  Widget _buildMenuSection() {
    final menuAsync =
        ref.watch(menuItemsProvider(widget.merchantId));

    return menuAsync.when(
      data: (grouped) => _buildMenuContent(grouped),
      loading: () => const SliverToBoxAdapter(
        child: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (_, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'Failed to load menu',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuContent(Map<String, List<MenuItemModel>> grouped) {
    final signature = grouped['signature'] ?? [];
    final popular = grouped['popular'] ?? [];
    final regular = grouped['regular'] ?? [];

    if (signature.isEmpty && popular.isEmpty && regular.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'No menu items available',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        // Signature Products 横滑
        if (signature.isNotEmpty) ...[
          _buildMenuSectionHeader('Signature Products', signature.length),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: signature.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => MenuItemCard(item: signature[i]),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],

        // Popular Picks 横滑
        if (popular.isNotEmpty) ...[
          _buildMenuSectionHeader('Popular Picks', popular.length),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: popular.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => MenuItemCard(item: popular[i]),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],

        // All Items 网格
        if (regular.isNotEmpty) ...[
          _buildMenuSectionHeader('All Items', regular.length),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 140 / 180,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => MenuItemCard(item: regular[i]),
                childCount: regular.length,
              ),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }

  SliverToBoxAdapter _buildMenuSectionHeader(String title, int count) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '($count)',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── About 区块内容 ──────────────────────────────────────────
  Widget _buildAboutSection(
    MerchantDetailModel merchant,
    List<StoreFacilityModel> facilities,
  ) {
    final envPhotos = merchant.environmentPhotos;
    final allEnvPhotos = envPhotos.values.expand((list) => list).toList();

    return SliverMainAxisGroup(
      slivers: [
        // 环境照片（横滑缩略图 + 点击弹出全部）
        if (allEnvPhotos.isNotEmpty) ...[
          _aboutSectionTitle('Environment'),
          SliverToBoxAdapter(
            child: _EnvironmentGallery(photos: allEnvPhotos),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],

        // 设施服务
        if (facilities.isNotEmpty) ...[
          _aboutSectionTitle('Facilities & Services'),
          SliverToBoxAdapter(
            child: SizedBox(
              height: facilities.any((f) => f.imageUrl != null) ? 220 : 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: facilities.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => FacilityCard(facility: facilities[i]),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],

        // 商家描述
        if (merchant.description != null &&
            merchant.description!.isNotEmpty) ...[
          _aboutSectionTitle('About'),
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

        // 完整营业时间
        if (merchant.hours.isNotEmpty) ...[
          _aboutSectionTitle('Business Hours'),
          SliverToBoxAdapter(
            child: _BusinessHoursTable(hours: merchant.hours),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],

        // 停车信息
        if (merchant.parkingInfo != null &&
            merchant.parkingInfo!.isNotEmpty)
          SliverToBoxAdapter(
            child: _InfoRow(
              icon: Icons.local_parking,
              label: 'Parking',
              value: merchant.parkingInfo!,
            ),
          ),

        // WiFi
        if (merchant.wifi)
          SliverToBoxAdapter(
            child: _InfoRow(
              icon: Icons.wifi,
              label: 'WiFi',
              value: 'Free WiFi available',
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }

  SliverToBoxAdapter _aboutSectionTitle(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  // ── Reviews 区块内容 ────────────────────────────────────────
  Widget _buildReviewsSection() {
    final statsAsync =
        ref.watch(reviewStatsProvider(widget.merchantId));
    final reviewsAsync =
        ref.watch(merchantReviewsProvider(widget.merchantId));

    return SliverMainAxisGroup(
      slivers: [
        // 评价统计头部
        SliverToBoxAdapter(
          child: statsAsync.when(
            data: (stats) => ReviewStatsHeader(stats: stats),
            loading: () => const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ),

        const SliverToBoxAdapter(
          child: Divider(height: 1, indent: 16, endIndent: 16),
        ),

        // 评价列表
        reviewsAsync.when(
          data: (reviews) {
            if (reviews.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'No reviews yet',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              );
            }

            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  // 最后一项触发加载更多
                  if (index == reviews.length - 1) {
                    final notifier = ref.read(
                        merchantReviewsProvider(widget.merchantId).notifier);
                    if (notifier.hasMore) {
                      notifier.loadMore();
                    }
                  }
                  return ReviewCard(review: reviews[index]);
                },
                childCount: reviews.length,
              ),
            );
          },
          loading: () => const SliverToBoxAdapter(
            child: SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (_, _) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Failed to load reviews',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }

  // ── Recommended 区块内容 ────────────────────────────────────
  Widget _buildRecommendedSection({
    double? lat,
    double? lng,
    String? brandId,
  }) {
    final hasLocation = lat != null && lng != null;
    final hasBrand = brandId != null;

    if (!hasLocation && !hasBrand) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'Location not available',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        // 同品牌其他门店
        if (hasBrand) _buildBrandStoresSection(brandId),

        // 附近推荐商家
        if (hasLocation) _buildNearbySection(lat, lng),

        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }

  Widget _buildBrandStoresSection(String brandId) {
    final storesAsync = ref.watch(sameBrandStoresProvider((
      brandId: brandId,
      merchantId: widget.merchantId,
    )));

    return storesAsync.when(
      data: (stores) {
        if (stores.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.store,
                        size: 18, color: AppColors.secondary),
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
            const SliverToBoxAdapter(
              child: Divider(height: 24, indent: 16, endIndent: 16),
            ),
          ],
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      error: (_, _) =>
          const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }

  Widget _buildNearbySection(double lat, double lng) {
    final nearbyAsync = ref.watch(nearbyMerchantsProvider((
      merchantId: widget.merchantId,
      lat: lat,
      lng: lng,
    )));

    return nearbyAsync.when(
      data: (merchants) {
        if (merchants.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverMainAxisGroup(
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
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
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      error: (_, _) =>
          const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }
}

// ── 区块分隔标题 ──────────────────────────────────────────────

class _SectionDivider extends StatelessWidget {
  final String label;

  const _SectionDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    );
  }
}

// ── 自定义吸顶 TabBar ────────────────────────────────────────

class _StickyTabBar extends StatelessWidget implements PreferredSizeWidget {
  final List<String> labels;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _StickyTabBar({
    required this.labels,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isSelected = currentIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.center,
                margin: EdgeInsets.only(left: i > 0 ? 4 : 0),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.secondary.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected
                          ? AppColors.secondary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? AppColors.secondary
                        : AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── 返回按钮 ──────────────────────────────────────────────────

class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.pop(),
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
      ),
    );
  }
}

// ── AppBar 操作按钮 ──────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final bool isFilled;
  final VoidCallback? onTap;

  const _ActionBtn(this.icon, {this.isFilled = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 18,
          color: isFilled ? Colors.red : Colors.white,
        ),
      ),
    );
  }
}

// ── TabBar 吸顶代理 ──────────────────────────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final PreferredSizeWidget tabBar;

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
        color: AppColors.surface,
        child: tabBar,
      );

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}

// ── 环境照片画廊（美团风格分类缩略图） ──────────────────────────

class _EnvironmentGallery extends StatefulWidget {
  final List<MerchantPhotoModel> photos;

  const _EnvironmentGallery({required this.photos});

  @override
  State<_EnvironmentGallery> createState() => _EnvironmentGalleryState();
}

class _EnvironmentGalleryState extends State<_EnvironmentGallery> {
  bool _reachedEnd = false;
  bool _sheetOpen = false;
  static const _cardSize = 80.0;

  void _showPhotoSheet() {
    if (_sheetOpen) return;
    _sheetOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EnvironmentPhotoSheet(photos: widget.photos),
    ).whenComplete(() => _sheetOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    // 照片 + 末尾"释放查看"入口
    final itemCount = photos.length + 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: _cardSize + 24,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification) {
              final metrics = notification.metrics;
              // "释放查看"露出超过一半时标记到达末尾
              final atEnd = metrics.pixels >= metrics.maxScrollExtent - 20;
              if (atEnd != _reachedEnd) {
                setState(() => _reachedEnd = atEnd);
              }
            }
            if (notification is ScrollEndNotification && _reachedEnd) {
              // 松手时自动打开弹窗
              setState(() => _reachedEnd = false);
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _showPhotoSheet());
            }
            return false;
          },
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: itemCount,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              // 最后一项：释放查看入口
              if (i == photos.length) {
                return GestureDetector(
                  onTap: _showPhotoSheet,
                  child: SizedBox(
                    width: 56,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_circle_right_outlined,
                          size: 28,
                          color: _reachedEnd
                              ? AppColors.secondary
                              : AppColors.textHint,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _reachedEnd ? 'Release\nto View' : 'View\nAll',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.2,
                            color: _reachedEnd
                                ? AppColors.secondary
                                : AppColors.textSecondary,
                            fontWeight: _reachedEnd
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // 普通照片缩略图
              final photo = photos[i];
              return GestureDetector(
                onTap: _showPhotoSheet,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: _cardSize,
                        height: _cardSize,
                        child: CachedNetworkImage(
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
                                size: 24, color: AppColors.textHint),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: _cardSize,
                      child: Text(
                        photo.categoryLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── 环境照片详情弹窗（展示所有照片） ─────────────────────────────

class _EnvironmentPhotoSheet extends StatelessWidget {
  final List<MerchantPhotoModel> photos;

  const _EnvironmentPhotoSheet({required this.photos});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 顶部拖拽指示条 + 标题
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'Photos (${photos.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 22),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 照片网格（每行 2 张）
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 4 / 3,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (_, i) {
                    final photo = photos[i];
                    return GestureDetector(
                      onTap: () => _showFullImage(context, i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
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
                                child: const Icon(
                                    Icons.image_not_supported,
                                    size: 28,
                                    color: AppColors.textHint),
                              ),
                            ),
                            // 底部标签
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.6),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                                child: Text(
                                  photo.categoryLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFullImage(BuildContext context, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenGallery(photos: photos, initialIndex: index),
      ),
    );
  }
}

// ── 全屏照片查看器 ───────────────────────────────────────────

class _FullScreenGallery extends StatefulWidget {
  final List<MerchantPhotoModel> photos;
  final int initialIndex;

  const _FullScreenGallery(
      {required this.photos, required this.initialIndex});

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.photos.length}',
          style: const TextStyle(fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (_, i) {
          return InteractiveViewer(
            child: Center(
              child: CachedNetworkImage(
                imageUrl: widget.photos[i].photoUrl,
                fit: BoxFit.contain,
                placeholder: (_, _) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (_, _, _) => const Icon(
                  Icons.image_not_supported,
                  size: 48,
                  color: Colors.white54,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── 营业时间表 ────────────────────────────────────────────────

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

// ── 单行信息展示（停车、WiFi 等）──────────────────────────────

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
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 同品牌门店卡片 ────────────────────────────────────────────

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
            const Icon(
              Icons.chevron_right,
              color: AppColors.textHint,
              size: 20,
            ),
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
      child: const Icon(
        Icons.store,
        color: AppColors.secondary,
        size: 24,
      ),
    );
  }
}
