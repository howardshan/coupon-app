import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../deals/domain/providers/history_provider.dart';
import '../../domain/providers/merchant_provider.dart';
import '../../domain/providers/store_detail_provider.dart';
import '../widgets/about_tab.dart';
import '../widgets/deals_tab.dart';
import '../widgets/menu_tab.dart';
import '../widgets/recommended_tab.dart';
import '../widgets/reviews_tab.dart';
import '../widgets/store_bottom_bar.dart';
import '../widgets/store_info_card.dart';
import '../widgets/store_photo_header.dart';

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

    return detailAsync.when(
      data: (merchant) {
        final reviewStats = reviewStatsAsync.valueOrNull;
        final facilities = facilitiesAsync.valueOrNull ?? [];
        final deals = dealsAsync.valueOrNull ?? [];

        // 评价数量用于 tab 标签
        final reviewCount = reviewStats?.totalCount ?? 0;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              // ── SliverAppBar: 头图 ────────────────────────
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
                title: innerBoxIsScrolled
                    ? Text(merchant.name,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary))
                    : null,
                flexibleSpace: FlexibleSpaceBar(
                  background: StorePhotoHeader(
                    merchant: merchant,
                    onPhotosPressed: () =>
                        context.push('/merchant/${widget.merchantId}/photos'),
                  ),
                ),
              ),

              // ── 商家信息卡片 ──────────────────────────────
              SliverToBoxAdapter(
                child: StoreInfoCard(
                  merchant: merchant,
                  reviewStats: reviewStats,
                  facilities: facilities,
                ),
              ),

              // ── 分隔线 ────────────────────────────────────
              const SliverToBoxAdapter(
                child: SizedBox(height: 8),
              ),

              // ── Tab 栏（吸顶）────────────────────────────
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  TabBar(
                    controller: _tabCtrl,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: AppColors.secondary,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: AppColors.secondary,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle:
                        const TextStyle(fontWeight: FontWeight.bold),
                    tabs: [
                      const Tab(text: 'Deals'),
                      const Tab(text: 'Menu'),
                      const Tab(text: 'About'),
                      Tab(
                          text: reviewCount > 0
                              ? 'Reviews ($reviewCount)'
                              : 'Reviews'),
                      const Tab(text: 'Recommended'),
                    ],
                  ),
                ),
              ),
            ],

            // ── Tab 内容 ──────────────────────────────────
            body: TabBarView(
              controller: _tabCtrl,
              children: [
                DealsTab(merchantId: widget.merchantId),
                MenuTab(merchantId: widget.merchantId),
                AboutTab(merchantId: widget.merchantId),
                ReviewsTab(merchantId: widget.merchantId),
                RecommendedTab(
                  merchantId: widget.merchantId,
                  lat: merchant.lat,
                  lng: merchant.lng,
                  brandId: merchant.brandId,
                ),
              ],
            ),
          ),

          // ── 底部操作栏 ──────────────────────────────────
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
  final TabBar tabBar;

  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset,
          bool overlapsContent) =>
      Container(
        color: AppColors.surface,
        child: tabBar,
      );

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}
