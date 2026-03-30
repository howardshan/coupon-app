import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../chat/presentation/widgets/share_to_friend_sheet.dart';
import '../../data/models/deal_model.dart';
import '../../data/models/review_model.dart';
import '../../domain/providers/deals_provider.dart';
import '../../domain/providers/history_provider.dart';
import '../../domain/providers/recommendation_provider.dart';
import '../../../cart/domain/providers/cart_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';

class DealDetailScreen extends ConsumerWidget {
  final String dealId;

  const DealDetailScreen({super.key, required this.dealId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealAsync = ref.watch(dealDetailProvider(dealId));

    // deal 数据可用时记录浏览历史 + 上报 view_deal 埋点
    // postFrameCallback 避免在 build 内产生副作用
    dealAsync.whenData((deal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(historyRepositoryProvider).addToHistory(deal.id);
        // 上报浏览行为，用于推荐系统个性化
        ref.read(recommendationRepositoryProvider).trackEvent(
          eventType: 'view_deal',
          dealId: deal.id,
          merchantId: deal.merchantId,
          metadata: {'category': deal.category},
        );
      });
    });

    return dealAsync.when(
      data: (deal) => _DealDetailBody(deal: deal),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

// ── Main body ────────────────────────────────────────────────
class _DealDetailBody extends ConsumerStatefulWidget {
  final DealModel deal;

  const _DealDetailBody({required this.deal});

  @override
  ConsumerState<_DealDetailBody> createState() => _DealDetailBodyState();
}

class _DealDetailBodyState extends ConsumerState<_DealDetailBody> {
  // 图片画廊高度
  static const _imageHeight = 280.0;
  // 滚动进度 0.0 ~ 1.0（0=顶部，1=图片完全滚出）
  double _scrollProgress = 0.0;
  final ScrollController _scrollController = ScrollController();

  DealModel get deal => widget.deal;

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

  void _onScroll() {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    // 渐变区间：从图片底部往上 toolbar + statusBar 的距离
    final threshold = _imageHeight - kToolbarHeight - statusBarHeight;
    final progress = (_scrollController.offset / threshold).clamp(0.0, 1.0);
    if ((progress - _scrollProgress).abs() > 0.01) {
      setState(() => _scrollProgress = progress);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // 图片画廊（独立 sliver，不在 SliverAppBar 内，确保 PageView 水平滑动正常）
              SliverToBoxAdapter(
                child: _ImageGallery(imageUrls: deal.imageUrls),
              ),

          // Price section
          SliverToBoxAdapter(child: _PriceSection(deal: deal)),

          // Info section (title, sold, availability, refund)
          SliverToBoxAdapter(child: _InfoSection(deal: deal)),

          // Gray divider
          const SliverToBoxAdapter(child: _SectionDivider()),

          // 套餐横向选择器（吸顶，类似 store detail 的 tab 栏）
          _StickyVariantSliver(deal: deal),

          // Deal details (products + note)
          SliverToBoxAdapter(child: _ProductsSection(deal: deal)),

          // 选项组选择区（"几选几"功能）
          if (deal.optionGroups.isNotEmpty)
            SliverToBoxAdapter(child: _OptionGroupsSelector(deal: deal)),

          // Gray divider
          const SliverToBoxAdapter(child: _SectionDivider()),

          // Purchase notes
          SliverToBoxAdapter(child: _PurchaseNotes(deal: deal)),

          // Gray divider
          const SliverToBoxAdapter(child: _SectionDivider()),

          // Restaurant info
          SliverToBoxAdapter(child: _RestaurantInfo(deal: deal)),

          // 详情竖版图片展示区（restaurant info 下方）
          if (deal.detailImages.isNotEmpty)
            SliverToBoxAdapter(child: _DetailPhotosSection(images: deal.detailImages)),

          // Gray divider
          const SliverToBoxAdapter(child: _SectionDivider()),

          // Applicable stores
          SliverToBoxAdapter(child: _ApplicableStores(deal: deal)),

          // Gray divider
          const SliverToBoxAdapter(child: _SectionDivider()),

          // More from this store
          SliverToBoxAdapter(
            child: _MerchantDeals(
              merchantId: deal.merchantId,
              currentDealId: deal.id,
            ),
          ),

          // Gray divider
          const SliverToBoxAdapter(child: _SectionDivider()),

          // Reviews
          SliverToBoxAdapter(
            child: _ReviewsSection(
              dealId: deal.id,
              dealRating: deal.rating,
              dealReviewCount: deal.reviewCount,
            ),
          ),

          // Bottom padding for the fixed bottom bar
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
          // 浮动导航栏：随滚动从透明渐变到白色背景
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: statusBarHeight + 8,
                left: 12,
                right: 12,
                bottom: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: _scrollProgress),
                boxShadow: _scrollProgress > 0.9
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _AdaptiveCircleButton(
                    icon: Icons.arrow_back,
                    progress: _scrollProgress,
                    onTap: () => context.pop(),
                  ),
                  Row(
                    children: [
                      // 搜索按钮（仅收起后显示）
                      if (_scrollProgress > 0.9)
                        _AdaptiveCircleButton(
                          icon: Icons.search,
                          progress: _scrollProgress,
                          onTap: () => context.push('/search'),
                        ),
                      if (_scrollProgress > 0.9) const SizedBox(width: 8),
                      _AdaptiveSaveButton(
                        dealId: deal.id,
                        progress: _scrollProgress,
                      ),
                      const SizedBox(width: 8),
                      _AdaptiveCircleButton(
                        icon: Icons.share_outlined,
                        progress: _scrollProgress,
                        onTap: () => _showShareOptions(context, deal),
                      ),
                      const SizedBox(width: 8),
                      _AdaptiveCircleButton(
                        icon: Icons.more_horiz,
                        progress: _scrollProgress,
                        onTap: () => _showMoreMenu(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(deal: deal),
    );
  }
}

/// 打开三个点菜单底部弹出框（美团风格）
// 分享选项弹窗（分享给好友 / 系统分享）
void _showShareOptions(BuildContext context, DealModel deal) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.people_outline, color: AppColors.primary),
            title: const Text('Share to Friends'),
            onTap: () {
              Navigator.of(ctx).pop();
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (_) => ShareToFriendSheet(
                  payload: {
                    'type': 'deal_share',
                    'deal_id': deal.id,
                    'deal_title': deal.title,
                    'deal_image_url': deal.imageUrls.isNotEmpty ? deal.imageUrls.first : '',
                    'discount_price': deal.discountPrice,
                    'original_price': deal.originalPrice,
                    'merchant_id': deal.merchantId,
                    'merchant_name': deal.merchant?.name ?? '',
                  },
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined, color: AppColors.textSecondary),
            title: const Text('Share via...'),
            onTap: () {
              Navigator.of(ctx).pop();
              Share.share(
                '${deal.title} - \$${deal.discountPrice.toStringAsFixed(2)} '
                '(${deal.effectiveDiscountLabel}) on DealJoy!',
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void _showMoreMenu(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.75,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _MoreMenuSheet(),
  );
}

// ── 三个点更多菜单底部弹出框（美团风格）────────────────────────
class _MoreMenuSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(historyDealsProvider);
    final savedIdsAsync = ref.watch(savedDealIdsProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖动指示条 + 关闭按钮
            Row(
              children: [
                const Spacer(),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 22, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 快捷操作图标行
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _MenuIcon(
                  icon: Icons.home_outlined,
                  label: 'Home',
                  onTap: () {
                    final nav = GoRouter.of(context);
                    Navigator.pop(context);
                    nav.go('/home');
                  },
                ),
                _MenuIcon(
                  icon: Icons.store_outlined,
                  label: 'Nearby',
                  onTap: () {
                    final nav = GoRouter.of(context);
                    Navigator.pop(context);
                    nav.push('/search');
                  },
                ),
                _MenuIcon(
                  icon: Icons.receipt_long_outlined,
                  label: 'My Orders',
                  onTap: () {
                    final nav = GoRouter.of(context);
                    Navigator.pop(context);
                    nav.push('/orders');
                  },
                ),
                _MenuIcon(
                  icon: Icons.flag_outlined,
                  label: 'Report',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Report submitted. Thank you!')),
                    );
                  },
                ),
                _MenuIcon(
                  icon: Icons.error_outline,
                  label: 'Report Error',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Error report submitted. Thank you!')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 浏览记录
            historyAsync.when(
              data: (deals) {
                if (deals.isEmpty) return const SizedBox.shrink();
                return _MenuDealSection(
                  title: 'Browsing History',
                  deals: deals.take(10).toList(),
                  onViewAll: () {
                    final nav = GoRouter.of(context);
                    Navigator.pop(context);
                    nav.push('/history');
                  },
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            // 我的收藏
            savedIdsAsync.when(
              data: (ids) {
                if (ids.isEmpty) return const SizedBox.shrink();
                return _SavedDealsSection(
                  dealIds: ids.take(10).toList(),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 菜单中的 Deal 横滚区（浏览记录）──────────────────────────
class _MenuDealSection extends StatelessWidget {
  final String title;
  final List<DealModel> deals;
  final VoidCallback? onViewAll;

  const _MenuDealSection({
    required this.title,
    required this.deals,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            if (onViewAll != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onViewAll,
                child: const Row(
                  children: [
                    Text('View All', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
                    Icon(Icons.chevron_right, size: 16, color: AppColors.textHint),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        // 横向滚动卡片
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: deals.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _MenuDealCard(deal: deals[i]),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── 菜单中的单个 Deal 卡片 ─────────────────────────────────
class _MenuDealCard extends StatelessWidget {
  final DealModel deal;

  const _MenuDealCard({required this.deal});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.pop(context);
        context.push('/deals/${deal.id}');
      },
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图片
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: deal.imageUrls.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: deal.imageUrls.first,
                      width: 110,
                      height: 88,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                        width: 110,
                        height: 88,
                        color: AppColors.surfaceVariant,
                        child: const Icon(Icons.restaurant, size: 24, color: AppColors.textHint),
                      ),
                    )
                  : Container(
                      width: 110,
                      height: 88,
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.restaurant, size: 24, color: AppColors.textHint),
                    ),
            ),
            const SizedBox(height: 6),
            // 标题
            Text(
              deal.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 2),
            // 价格
            Text(
              '\$${deal.discountPrice.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 我的收藏区（需要根据 ID 列表获取 deal 数据）──────────────
class _SavedDealsSection extends ConsumerWidget {
  final List<String> dealIds;

  const _SavedDealsSection({required this.dealIds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealsAsync = ref.watch(savedDealsListProvider);

    return dealsAsync.when(
      data: (deals) {
        if (deals.isEmpty) return const SizedBox.shrink();
        return _MenuDealSection(
          title: 'My Favorites',
          deals: deals.take(10).toList(),
          onViewAll: () {
            final nav = GoRouter.of(context);
            Navigator.pop(context);
            nav.push('/collection');
          },
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ── 菜单图标项 ──────────────────────────────────────────────
class _MenuIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 自适应圆形按钮（透明背景 → 无背景，随 progress 渐变）─────
class _AdaptiveCircleButton extends StatelessWidget {
  final IconData icon;
  final double progress;
  final VoidCallback onTap;

  const _AdaptiveCircleButton({
    required this.icon,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // progress 0: 半透明白色圆形背景 + 深色图标
    // progress 1: 无背景 + 深色图标
    final showCircle = progress < 0.9;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: showCircle
            ? BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9 * (1 - progress)),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1 * (1 - progress)),
                    blurRadius: 8,
                  ),
                ],
              )
            : null,
        child: Icon(icon, size: 20, color: AppColors.textPrimary),
      ),
    );
  }
}

// ── 自适应收藏按钮（随 progress 渐变）────────────────────────
class _AdaptiveSaveButton extends ConsumerWidget {
  final String dealId;
  final double progress;

  const _AdaptiveSaveButton({
    required this.dealId,
    required this.progress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedIds = ref.watch(savedDealIdsProvider).valueOrNull ?? {};
    final isSaved = savedIds.contains(dealId);
    final showCircle = progress < 0.9;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          ref.read(savedDealsNotifierProvider.notifier).toggle(dealId),
      child: Container(
        width: 40,
        height: 40,
        decoration: showCircle
            ? BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9 * (1 - progress)),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1 * (1 - progress)),
                    blurRadius: 8,
                  ),
                ],
              )
            : null,
        child: Icon(
          isSaved ? Icons.favorite : Icons.favorite_border,
          size: 20,
          color: isSaved ? Colors.red : AppColors.textPrimary,
        ),
      ),
    );
  }
}

// ── Section divider (8px gray) ───────────────────────────────
class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 8, color: AppColors.background);
  }
}

// ── Image gallery with page indicator ────────────────────────
class _ImageGallery extends StatefulWidget {
  final List<String> imageUrls;

  const _ImageGallery({required this.imageUrls});

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;
    if (urls.isEmpty) {
      return Stack(
        children: [
          Container(
            height: 280,
            color: AppColors.surfaceVariant,
            child: const Center(
              child: Icon(Icons.restaurant, size: 64, color: AppColors.textHint),
            ),
          ),
          // 底部白色圆角覆盖层
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              height: 16,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
          ),
        ],
      );
    }

    return SizedBox(
      key: const ValueKey('deal_image_gallery'),
      height: 280,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (_, i) => CachedNetworkImage(
              imageUrl: urls[i],
              width: double.infinity,
              height: 280,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => Container(
                color: AppColors.surfaceVariant,
                child: const Center(
                  child:
                      Icon(Icons.restaurant, size: 48, color: AppColors.textHint),
                ),
              ),
            ),
          ),
          // 底部白色圆角覆盖层（美团风格）
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 16,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
          ),
          // 底部右侧：页码指示器 + 相册按钮
          Positioned(
            bottom: 28,
            right: 16,
            child: Row(
              children: [
                // 页码指示器（多图时才显示）
                if (urls.length > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_currentPage + 1}/${urls.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                // 相册按钮：点击打开全屏图片查看器
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openFullscreenGallery(context, urls, _currentPage),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 打开全屏图片查看器（黑色背景，支持横向滑动，点击关闭）
  void _openFullscreenGallery(
      BuildContext context, List<String> urls, int initialPage) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => _FullscreenGalleryDialog(
        imageUrls: urls,
        initialPage: initialPage,
      ),
    );
  }
}

// ── 全屏图片查看器 dialog ─────────────────────────────────────
class _FullscreenGalleryDialog extends StatefulWidget {
  final List<String> imageUrls;
  final int initialPage;

  const _FullscreenGalleryDialog({
    required this.imageUrls,
    required this.initialPage,
  });

  @override
  State<_FullscreenGalleryDialog> createState() =>
      _FullscreenGalleryDialogState();
}

class _FullscreenGalleryDialogState extends State<_FullscreenGalleryDialog> {
  late int _currentPage;
  late PageController _controller;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _controller = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 点击任意处关闭
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 横向滑动图片
            PageView.builder(
              controller: _controller,
              itemCount: widget.imageUrls.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) => CachedNetworkImage(
                imageUrl: widget.imageUrls[i],
                fit: BoxFit.contain,
                errorWidget: (_, _, _) => const Center(
                  child: Icon(Icons.broken_image,
                      size: 64, color: Colors.white54),
                ),
              ),
            ),
            // 顶部页码
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${_currentPage + 1} / ${widget.imageUrls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
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

// ── Price section ────────────────────────────────────────────
class _PriceSection extends StatelessWidget {
  final DealModel deal;

  const _PriceSection({required this.deal});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 折扣价 + 折扣标签
          const Text(
            '\$',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            deal.discountPrice.toStringAsFixed(2),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 36,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              deal.effectiveDiscountLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 右侧公式区域（自适应宽度）
          Expanded(
            child: Row(
              children: [
                // = 号
                const Text(
                  '=',
                  style: TextStyle(
                    color: AppColors.textHint,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                // Reg Price 列（可点击弹出说明）
                Flexible(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Price Info'),
                          content: const Text(
                            'The regular price is provided by the merchant for comparison purposes and may not reflect the actual in-store or online retail price. '
                            'It could represent the item\'s list price, suggested retail price, or a previously offered price. '
                            'Due to regional and market variations, the regular price may differ from what you see at the time of purchase. '
                            'This price is for reference only.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Got it'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              'Reg Price',
                              style: TextStyle(
                                color: AppColors.textHint,
                                fontSize: 10,
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(
                              Icons.help_outline,
                              size: 11,
                              color: AppColors.textHint,
                            ),
                          ],
                        ),
                        Text(
                          '\$${deal.originalPrice.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Color(0xFF333333),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // - 号
                const Text(
                  '-',
                  style: TextStyle(
                    color: AppColors.textHint,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                // Deal Promotion 列
                Flexible(
                  child: Column(
                    children: [
                      const Text(
                        'Deal Promotion',
                        style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '\$${(deal.originalPrice - deal.discountPrice).toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info section (title, sold, availability, refund) ─────────
class _InfoSection extends StatelessWidget {
  final DealModel deal;

  const _InfoSection({required this.deal});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            deal.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),

          // Sold count
          Row(
            children: [
              const Icon(Icons.local_fire_department,
                  size: 15, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(
                '${deal.totalSold} sold',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Availability row
          Row(
            children: [
              const Icon(Icons.access_time_outlined,
                  size: 16, color: AppColors.success),
              const SizedBox(width: 6),
              Text(
                'Available Today',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (deal.merchantHours != null) ...[
                Flexible(
                  child: Text(
                    '  ·  ${deal.merchantHours}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Refund badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline,
                    color: AppColors.success, size: 15),
                const SizedBox(width: 6),
                const Text(
                  'Refund Anytime',
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    size: 14, color: AppColors.success),
              ],
            ),
          ),

          // Description（商家填写的描述）
          if (deal.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              deal.description,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

}

// ── 套餐横向选择器（吸顶 Sliver）─────────────────────────────
// 观察 merchantDealsProvider，有多个 deal 时渲染吸顶 header，否则渲染空 sliver
const _kVariantHeight = 72.0; // 56 内容 + 8*2 上下 padding

class _StickyVariantSliver extends ConsumerWidget {
  final DealModel deal;

  const _StickyVariantSliver({required this.deal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealsAsync = ref.watch(merchantDealsProvider(
      (merchantId: deal.merchantId, excludeDealId: ''),
    ));

    return dealsAsync.when(
      data: (deals) {
        if (deals.length <= 1) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverPersistentHeader(
          pinned: true,
          delegate: _VariantSelectorDelegate(
            deal: deal,
            deals: deals,
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }
}

// ── 套餐吸顶 Delegate ────────────────────────────────────────
class _VariantSelectorDelegate extends SliverPersistentHeaderDelegate {
  final DealModel deal;
  final List<DealModel> deals;

  _VariantSelectorDelegate({required this.deal, required this.deals});

  @override
  double get minExtent => _kVariantHeight;

  @override
  double get maxExtent => _kVariantHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final sorted = [...deals]..sort((a, b) {
        if (a.sortOrder == null && b.sortOrder == null) return 0;
        if (a.sortOrder == null) return 1;
        if (b.sortOrder == null) return -1;
        return a.sortOrder!.compareTo(b.sortOrder!);
      });

    // 2.5 卡可见
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth - 32 - 12) / 2.5;
    const imageSize = 48.0;

    final currentIndex = sorted.indexWhere((d) => d.id == deal.id);
    final initialOffset = currentIndex > 0
        ? (currentIndex * (cardWidth + 8)).clamp(0.0, double.infinity)
        : 0.0;

    return Container(
      key: const ValueKey('deal_variant_selector'),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        height: 56,
        child: ListView.separated(
          controller: ScrollController(initialScrollOffset: initialOffset),
          scrollDirection: Axis.horizontal,
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final d = sorted[i];
            final isCurrent = d.id == deal.id;
            final displayName = (d.shortName != null &&
                    d.shortName!.isNotEmpty)
                ? d.shortName!
                : (d.title.length > 8
                    ? '${d.title.substring(0, 8)}…'
                    : d.title);

            return GestureDetector(
              key: ValueKey('deal_variant_item_${d.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: isCurrent
                  ? null
                  : () => context.push('/deals/${d.id}'),
              child: Container(
                width: cardWidth,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCurrent
                        ? AppColors.primary
                        : AppColors.surfaceVariant,
                    width: isCurrent ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    // 左侧小方图
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: d.imageUrls.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: d.imageUrls.first,
                              width: imageSize,
                              height: imageSize,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => Container(
                                width: imageSize,
                                height: imageSize,
                                color: AppColors.surfaceVariant,
                                child: const Icon(Icons.restaurant,
                                    size: 20, color: AppColors.textHint),
                              ),
                            )
                          : Container(
                              width: imageSize,
                              height: imageSize,
                              color: AppColors.surfaceVariant,
                              child: const Icon(Icons.restaurant,
                                  size: 20, color: AppColors.textHint),
                            ),
                    ),
                    const SizedBox(width: 6),
                    // 右侧名称 + 价格
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isCurrent
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '\$${d.discountPrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isCurrent
                                  ? AppColors.primary
                                  : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_VariantSelectorDelegate oldDelegate) =>
      oldDelegate.deal.id != deal.id || oldDelegate.deals.length != deals.length;
}

// ── Products section + Note ────────────────────────────────────
class _ProductsSection extends StatelessWidget {
  final DealModel deal;

  const _ProductsSection({required this.deal});

  @override
  Widget build(BuildContext context) {
    if (deal.products.isEmpty) return const SizedBox.shrink();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Deal Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Products list
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceVariant),
            ),
            child: Column(
              children: deal.products.asMap().entries.map((entry) {
                final isLast = entry.key == deal.products.length - 1;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : const Border(
                            bottom:
                                BorderSide(color: AppColors.surfaceVariant)),
                  ),
                  child: Builder(builder: (_) {
                    // 解析 "name::qty::subtotal" 格式
                    final parts = entry.value.split('::');
                    final name = parts[0];
                    final qty = parts.length > 1 ? parts[1] : '1';
                    final subtotal = parts.length > 2 ? parts[2] : '';

                    // 检查是否有对应的选项组（按名称匹配）
                    final matchedGroup = deal.optionGroups.cast<DealOptionGroup?>().firstWhere(
                      (g) => g!.name.toLowerCase() == name.toLowerCase(),
                      orElse: () => null,
                    );

                    if (matchedGroup != null) {
                      // 选项组产品行：selectMin == items.length 时只显示名称，否则 "Name (Select X from Y)"
                      final totalItems = matchedGroup.items.length;
                      final displayName = matchedGroup.selectMin == totalItems
                          ? name
                          : '$name (Select ${matchedGroup.selectMin} from $totalItems)';
                      return Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    // 普通产品行：显示 ×qty $subtotal
                    final suffix = subtotal.isNotEmpty ? '×$qty \$$subtotal' : '×$qty';
                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          suffix,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    );
                  }),
                );
              }).toList(),
            ),
          ),

          // Usage Notes（商家填写的使用须知）
          if (deal.usageNotes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Note: ${deal.usageNotes}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── 选项组选择器（"几选几"功能）───────────────────────────────
class _OptionGroupsSelector extends ConsumerStatefulWidget {
  final DealModel deal;
  const _OptionGroupsSelector({required this.deal});

  @override
  ConsumerState<_OptionGroupsSelector> createState() => _OptionGroupsSelectorState();
}

class _OptionGroupsSelectorState extends ConsumerState<_OptionGroupsSelector> {
  @override
  void initState() {
    super.initState();
    // 初始化选项组选择状态（每个组初始化为空集合）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = ref.read(dealOptionSelectionsProvider(widget.deal.id));
      if (current.isEmpty) {
        final initial = <String, Set<String>>{};
        for (final group in widget.deal.optionGroups) {
          initial[group.id] = {};
        }
        ref.read(dealOptionSelectionsProvider(widget.deal.id).notifier).state = initial;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selections = ref.watch(dealOptionSelectionsProvider(widget.deal.id));

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          const Text(
            'Customize Your Order',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          // 每个选项组
          ...widget.deal.optionGroups.map((group) => _buildGroup(group, selections)),
        ],
      ),
    );
  }

  Widget _buildGroup(DealOptionGroup group, Map<String, Set<String>> selections) {
    final selected = selections[group.id] ?? {};
    final isComplete = selected.length >= group.selectMin;

    return Container(
      key: ValueKey('option_group_${group.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isComplete
              ? AppColors.primary.withValues(alpha: 0.3)
              : const Color(0xFFE0E0E0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 组标题和状态
          Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              // 状态标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isComplete
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${selected.length}/${group.selectMin == group.selectMax ? group.selectMin : '${group.selectMin}-${group.selectMax}'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isComplete ? AppColors.primary : AppColors.textHint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            group.displayLabel,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          // 选项项列表
          ...group.items.map((item) {
            final isSelected = selected.contains(item.id);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggleItem(group, item.id),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : const Color(0xFFE8E8E8),
                  ),
                ),
                child: Row(
                  children: [
                    // 复选标记
                    Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 20,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textHint,
                    ),
                    const SizedBox(width: 10),
                    // 项名称
                    Expanded(
                      child: Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    // 价格
                    if (item.price > 0)
                      Text(
                        '\$${item.price.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _toggleItem(DealOptionGroup group, String itemId) {
    final selections = Map<String, Set<String>>.from(
      ref.read(dealOptionSelectionsProvider(widget.deal.id)),
    );
    final selected = Set<String>.from(selections[group.id] ?? {});

    if (selected.contains(itemId)) {
      selected.remove(itemId);
    } else {
      // 检查是否已达到 max
      if (selected.length >= group.selectMax) {
        // 如果 max=1，替换选择
        if (group.selectMax == 1) {
          selected.clear();
          selected.add(itemId);
        }
        // 否则不允许继续添加
        else {
          return;
        }
      } else {
        selected.add(itemId);
      }
    }
    selections[group.id] = selected;
    ref.read(dealOptionSelectionsProvider(widget.deal.id).notifier).state = selections;
  }
}

// ── Purchase notes ───────────────────────────────────────────
class _PurchaseNotes extends StatelessWidget {
  final DealModel deal;

  const _PurchaseNotes({required this.deal});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Purchase Notes',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          _NoteRow(
            icon: Icons.event_available,
            label: 'Validity',
            value: switch (deal.validityType) {
              'short_after_purchase' =>
                '${deal.validityDays ?? '?'} days after purchase',
              'long_after_purchase' =>
                '${deal.validityDays ?? '?'} days after purchase',
              _ => 'Valid until ${dateFormat.format(deal.expiresAt)}',
            },
          ),
          // Short-term 预授权模式：额外展示支付方式说明
          if (deal.validityType == 'short_after_purchase') ...[
            const SizedBox(height: 12),
            const _NoteRow(
              icon: Icons.credit_card_outlined,
              label: 'Payment',
              value: 'Card hold only — charged at redemption, released if unused',
            ),
          ],
          if (deal.merchantHours != null) ...[
            const SizedBox(height: 12),
            _NoteRow(
              icon: Icons.schedule_outlined,
              label: 'Hours',
              value: deal.merchantHours!,
            ),
          ],
          const SizedBox(height: 12),
          _NoteRow(
            icon: Icons.shield_outlined,
            label: 'Refund',
            value: deal.refundPolicy,
          ),
          const SizedBox(height: 12),
          // 使用规则（从 DB 读取，按条目展示）
          ...deal.usageRules.asMap().entries.map((entry) {
            return Padding(
              padding: EdgeInsets.only(top: entry.key > 0 ? 12 : 0),
              child: _NoteRow(
                icon: entry.key == 0 ? Icons.rule : Icons.info_outline,
                label: entry.key == 0 ? 'Rules' : 'Note',
                value: entry.value,
              ),
            );
          }),
          // 限购提示（max_per_account > 0 时显示）
          if (deal.maxPerAccount > 0) ...[
            const SizedBox(height: 12),
            _NoteRow(
              icon: Icons.person_outline,
              label: 'Limit',
              value: 'Maximum ${deal.maxPerAccount} per account',
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _NoteRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

// ── Restaurant info ──────────────────────────────────────────
class _RestaurantInfo extends StatelessWidget {
  final DealModel deal;

  const _RestaurantInfo({required this.deal});

  @override
  Widget build(BuildContext context) {
    final merchant = deal.merchant;
    if (merchant == null) return const SizedBox.shrink();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Restaurant Info',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // 圆形头像：优先封面图，降级用 Logo，再降级首字母占位
              Builder(builder: (context) {
                // 确定头像图片 URL
                final avatarUrl = (merchant.homepageCoverUrl != null &&
                        merchant.homepageCoverUrl!.isNotEmpty)
                    ? merchant.homepageCoverUrl!
                    : (merchant.logoUrl != null && merchant.logoUrl!.isNotEmpty)
                        ? merchant.logoUrl!
                        : null;
                // 首字母占位 Widget
                final placeholder = Container(
                  width: 56,
                  height: 56,
                  color: AppColors.surfaceVariant,
                  child: Center(
                    child: Text(
                      merchant.name.isNotEmpty
                          ? merchant.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
                return ClipOval(
                  child: avatarUrl != null
                      ? CachedNetworkImage(
                          imageUrl: avatarUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => placeholder,
                        )
                      : placeholder,
                );
              }),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchant.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 连锁店显示品牌 Badge（品牌 Logo + 品牌名）
                    if (merchant.isChainStore) ...[
                      const SizedBox(height: 4),
                      _DetailBrandBadge(merchant: merchant),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 3),
                        Text(
                          deal.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(${deal.reviewCount} reviews)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Phone button
              if (merchant.phone != null && merchant.phone!.isNotEmpty)
                _ActionCircle(
                  icon: Icons.phone_outlined,
                  onTap: () => launchUrl(
                    Uri.parse('tel:${merchant.phone}'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              const SizedBox(width: 8),
              // Directions button
              _ActionCircle(
                icon: Icons.directions_outlined,
                onTap: () {
                  final addr = deal.address ?? merchant.address;
                  if (addr != null && addr.isNotEmpty) {
                    launchUrl(
                      Uri.parse(
                          'https://maps.google.com/?q=${Uri.encodeComponent(addr)}'),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
              ),
            ],
          ),
          // Address
          if (deal.address != null || merchant.address != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    deal.address ?? merchant.address ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Detail Photos Section ─────────────────────────────────────
/// Deal 详情竖版图片展示区（显示在 Restaurant Info 下方）
class _DetailPhotosSection extends StatelessWidget {
  final List<String> images;

  const _DetailPhotosSection({required this.images});

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Photos',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          // 竖版图片列表，宽度铺满，高宽比 3:4
          ...images.map((url) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: CachedNetworkImage(
                  imageUrl: url,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: AppColors.surfaceVariant,
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: AppColors.surfaceVariant,
                    child: const Center(
                      child: Icon(Icons.broken_image, color: AppColors.textHint),
                    ),
                  ),
                ),
              ),
            ),
          )),
        ],
      ),
    );
  }
}

class _ActionCircle extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ActionCircle({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: AppColors.textSecondary),
      ),
    );
  }
}

// ── Applicable stores ────────────────────────────────────────
class _ApplicableStores extends StatelessWidget {
  final DealModel deal;

  const _ApplicableStores({required this.deal});

  @override
  Widget build(BuildContext context) {
    final merchant = deal.merchant;
    if (merchant == null) return const SizedBox.shrink();

    // 从 deal_applicable_stores 表动态查询 active 门店数量
    final activeStoreFuture = Supabase.instance.client
        .from('deal_applicable_stores')
        .select('id')
        .eq('deal_id', deal.id)
        .eq('status', 'active');

    // 降级：优先用 RPC 返回的 activeStoreCount，其次用旧的 applicableMerchantIds 数组长度
    final legacyStoreIds = deal.applicableMerchantIds;
    final fallbackCount = deal.activeStoreCount ??
        ((legacyStoreIds != null && legacyStoreIds.isNotEmpty)
            ? legacyStoreIds.length
            : 1);

    // 只有1家门店时隐藏整个 section
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: activeStoreFuture,
      builder: (context, snapshot) {
        final storeCount = (snapshot.hasData && snapshot.data!.isNotEmpty)
            ? snapshot.data!.length
            : fallbackCount;

        // 加上主门店共 storeCount+1?  不，deal_applicable_stores 已包含主门店
        // 只有1家门店时不显示
        if (storeCount <= 1) return const SizedBox.shrink();

        return Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Applicable Stores',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Available at $storeCount ${storeCount == 1 ? 'location' : 'locations'}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 主门店卡片始终显示
              _buildStoreCard(context, merchant),

              // 从 deal_applicable_stores 加载并显示其他 active 门店
              _MultiStoreList(
                dealId: deal.id,
                dealDiscountPrice: deal.discountPrice,
                dealDiscountPercent: deal.discountPercent,
                primaryMerchantId: merchant.id,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStoreCard(BuildContext context, MerchantSummary merchant) {
    final coverUrl = merchant.homepageCoverUrl;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/merchant/${merchant.id}'),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 封面图
            if (coverUrl != null && coverUrl.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: CachedNetworkImage(
                  imageUrl: coverUrl,
                  width: double.infinity,
                  height: 100,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Logo
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child:
                        merchant.logoUrl != null && merchant.logoUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: merchant.logoUrl!,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 52,
                                height: 52,
                                color: AppColors.surfaceVariant,
                                child: const Icon(Icons.restaurant,
                                    color: AppColors.textHint),
                              ),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          merchant.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        if (merchant.address != null &&
                            merchant.address!.isNotEmpty)
                          Text(
                            merchant.address!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  // Phone
                  if (merchant.phone != null && merchant.phone!.isNotEmpty)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => launchUrl(
                        Uri.parse('tel:${merchant.phone}'),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.phone,
                            size: 18, color: AppColors.primary),
                      ),
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

// 多店列表：从 deal_applicable_stores 表异步加载 active 门店，支持 per-store 折扣展示
class _MultiStoreList extends StatelessWidget {
  final String dealId;
  final double? dealDiscountPrice;   // deal 现价，用于计算各门店折扣
  final int? dealDiscountPercent;    // 全局折扣%，当门店无独立原价时降级使用
  final String primaryMerchantId;   // 主门店 ID，已在外部展示，此处跳过

  const _MultiStoreList({
    required this.dealId,
    required this.dealDiscountPrice,
    required this.dealDiscountPercent,
    required this.primaryMerchantId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      // 查 deal_applicable_stores 表，join merchants 获取门店信息
      future: Supabase.instance.client
          .from('deal_applicable_stores')
          .select(
            'store_id, store_original_price, '
            'merchants!deal_applicable_stores_store_id_fkey(id, name, address, logo_url, phone, homepage_cover_url)',
          )
          .eq('deal_id', dealId)
          .eq('status', 'active'),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        // 过滤掉主门店（已在上方单独展示）
        final rows = snapshot.data!
            .where((r) => (r['store_id'] as String? ?? '') != primaryMerchantId)
            .toList();

        if (rows.isEmpty) return const SizedBox.shrink();

        return Column(
          children: rows.map((row) {
            final merchant = row['merchants'] as Map<String, dynamic>? ?? {};
            final storeId = row['store_id'] as String? ?? '';
            final logoUrl = merchant['logo_url'] as String? ?? '';
            final coverUrl = merchant['homepage_cover_url'] as String? ?? '';
            final name = merchant['name'] as String? ?? '';
            final address = merchant['address'] as String? ?? '';
            final phone = merchant['phone'] as String? ?? '';

            // 计算门店折扣：优先用 store_original_price，否则降级用全局 discountPercent
            final storeOriginalPrice = (row['store_original_price'] as num?)?.toDouble();
            int? discountPct;
            if (storeOriginalPrice != null &&
                storeOriginalPrice > 0 &&
                dealDiscountPrice != null) {
              discountPct =
                  ((storeOriginalPrice - dealDiscountPrice!) / storeOriginalPrice * 100)
                      .round();
            } else {
              discountPct = dealDiscountPercent;
            }

            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.push('/merchant/$storeId'),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.surfaceVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 封面图
                      if (coverUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          child: CachedNetworkImage(
                            imageUrl: coverUrl,
                            width: double.infinity,
                            height: 100,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                    children: [
                      // 门店 Logo
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: logoUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: logoUrl,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 44,
                                height: 44,
                                color: AppColors.surfaceVariant,
                                child: const Icon(Icons.storefront,
                                    size: 20, color: AppColors.textHint),
                              ),
                      ),
                      const SizedBox(width: 12),
                      // 门店名称 + 地址
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (address.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                address,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      // 折扣 chip（绿色）+ 导航箭头
                      if (discountPct != null && discountPct > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$discountPct% off',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      // 拨号按钮
                      if (phone.isNotEmpty)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => launchUrl(
                            Uri.parse('tel:$phone'),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.phone,
                                size: 16, color: AppColors.primary),
                          ),
                        )
                      else
                        const Icon(Icons.chevron_right,
                            size: 20, color: AppColors.textHint),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
          }).toList(),
        );
      },
    );
  }
}

// ── More from this store ─────────────────────────────────────
class _MerchantDeals extends ConsumerWidget {
  final String merchantId;
  final String currentDealId;

  const _MerchantDeals({
    required this.merchantId,
    required this.currentDealId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealsAsync = ref.watch(merchantDealsProvider(
      (merchantId: merchantId, excludeDealId: currentDealId),
    ));

    return dealsAsync.when(
      data: (deals) {
        if (deals.isEmpty) return const SizedBox.shrink();
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'More from this Store',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('/merchant/$merchantId'),
                    child: Row(
                      children: [
                        Text(
                          'See All',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            size: 16, color: AppColors.primary),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Horizontal list
              SizedBox(
                height: 200,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: deals.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) =>
                      _MerchantDealCard(deal: deals[i]),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _MerchantDealCard extends StatelessWidget {
  final DealModel deal;

  const _MerchantDealCard({required this.deal});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/deals/${deal.id}'),
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: deal.imageUrls.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: deal.imageUrls.first,
                      width: 150,
                      height: 100,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 150,
                      height: 100,
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.restaurant,
                          color: AppColors.textHint),
                    ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deal.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '\$${deal.discountPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '\$${deal.originalPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11,
                          decoration: TextDecoration.lineThrough,
                        ),
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

// ── Reviews section ──────────────────────────────────────────
class _ReviewsSection extends ConsumerWidget {
  final String dealId;
  final double dealRating;
  final int dealReviewCount;

  const _ReviewsSection({
    required this.dealId,
    required this.dealRating,
    required this.dealReviewCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(dealReviewsProvider(dealId));

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Reviews',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  const Icon(Icons.star, size: 16, color: Colors.amber),
                  const SizedBox(width: 3),
                  Text(
                    dealRating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    ' ($dealReviewCount)',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Rating stars summary
          Row(
            children: List.generate(
              5,
              (i) => Icon(
                i < dealRating.round() ? Icons.star : Icons.star_border,
                size: 18,
                color: Colors.amber,
              ),
            ),
          ),
          Text(
            '$dealReviewCount reviews',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),

          // Reviews list
          reviewsAsync.when(
            data: (reviews) {
              if (reviews.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  alignment: Alignment.center,
                  child: const Text(
                    'Be the first to review!',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                );
              }
              final shown = reviews.length > 5 ? reviews.sublist(0, 5) : reviews;
              return Column(
                children: [
                  ...shown.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ReviewCard(review: r),
                      )),
                  if (reviews.length > 5)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // TODO: navigate to full reviews page
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        child: Text(
                          'See All $dealReviewCount Reviews',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),

          // Write a review button
          const SizedBox(height: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push('/review/$dealId'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary),
              ),
              child: const Center(
                child: Text(
                  'Write a Review',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Single review card ───────────────────────────────────────
class _ReviewCard extends StatelessWidget {
  final ReviewModel review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    // 展示上传日期与时间（北美英文格式）
    final dateStr =
        'Posted ${DateFormat('MMM d, y').format(review.createdAt)} · ${DateFormat('h:mm a').format(review.createdAt)}';
    final userName = review.userName ?? 'User';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info row
          Row(
            children: [
              // Avatar
              ClipOval(
                child: review.userAvatarUrl != null &&
                        review.userAvatarUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: review.userAvatarUrl!,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 32,
                        height: 32,
                        color: AppColors.primary.withValues(alpha: 0.1),
                        child: Center(
                          child: Text(
                            userName[0].toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              // Name + date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              // Stars
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < review.rating ? Icons.star : Icons.star_border,
                    size: 14,
                    color: Colors.amber,
                  ),
                ),
              ),
            ],
          ),
          // Verified badge
          if (review.isVerified) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Verified Purchase',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          // Comment
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Bottom bar (Store + Save + Buy Now) ──────────────────────
class _BottomBar extends ConsumerWidget {
  final DealModel deal;

  const _BottomBar({required this.deal});

  /// 校验选项组是否全部满足 selectMin 要求
  List<String> _validateOptionSelections(Map<String, Set<String>> selections) {
    final incomplete = <String>[];
    for (final group in deal.optionGroups) {
      final selected = selections[group.id] ?? {};
      if (selected.length < group.selectMin) {
        incomplete.add(group.name);
      }
    }
    return incomplete;
  }

  /// 选项校验 + 限购校验 + buy now
  Future<void> _handleBuyNow(BuildContext context, WidgetRef ref, DealModel deal) async {
    // 校验选项组
    if (deal.optionGroups.isNotEmpty) {
      final selections = ref.read(dealOptionSelectionsProvider(deal.id));
      final incomplete = _validateOptionSelections(selections);
      if (incomplete.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please complete: ${incomplete.join(', ')}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    // 限购校验（max_per_account > 0 时）
    if (deal.maxPerAccount > 0) {
      final userId = ref.read(currentUserProvider).value?.id;
      if (userId != null) {
        // 查询该用户已购买且未退款的该 deal 数量
        final res = await Supabase.instance.client
            .from('order_items')
            .select('id, orders!inner(user_id)')
            .eq('deal_id', deal.id)
            .eq('orders.user_id', userId)
            .neq('customer_status', 'refund_success');
        final purchasedCount = (res as List).length;
        if (purchasedCount >= deal.maxPerAccount) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("You've reached the purchase limit for this deal"),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
      }
    }

    if (!context.mounted) return;

    // 直接用当前 deal 所属的门店，不弹门店选择
    final merchantId = deal.merchant?.id ?? '';
    context.push('/checkout/${deal.id}?merchantId=$merchantId');
    return;

    // 以下门店选择代码保留但不再执行（品牌 deal 也直接用 deal 的 merchant）
    // ignore: dead_code
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _StorePickerSheet(deal: deal),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (deal.isExpired) {
      return SafeArea(
        child: Center(
          child: Container(
            color: AppColors.surfaceVariant,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Deal Expired',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back, size: 20),
                  label: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final cartCount = ref.watch(cartTotalCountProvider);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: AppColors.surfaceVariant),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Store 按钮
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push('/merchant/${deal.merchantId}'),
              child: const SizedBox(
                width: 48,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.store_outlined,
                        size: 22, color: AppColors.textSecondary),
                    SizedBox(height: 2),
                    Text(
                      'Store',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 购物车图标（带 badge）
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.go('/cart'),
              child: SizedBox(
                width: 48,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Badge(
                      isLabelVisible: cartCount > 0,
                      label: Text(
                        '$cartCount',
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                      backgroundColor: AppColors.primary,
                      child: const Icon(Icons.shopping_cart_outlined,
                          size: 22, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Cart',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Add to Cart 按钮（橙色，截图色号 #FF9500）
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  // 校验选项组
                  if (deal.optionGroups.isNotEmpty) {
                    final selections = ref.read(dealOptionSelectionsProvider(deal.id));
                    final incomplete = _validateOptionSelections(selections);
                    if (incomplete.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Please complete: ${incomplete.join(', ')}'),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }
                  }
                  // 限购校验（max_per_account > 0 时）
                  if (deal.maxPerAccount > 0) {
                    final userId = ref.read(currentUserProvider).value?.id;
                    if (userId != null) {
                      // 查询该用户已购买且未退款的该 deal 数量
                      final res = await Supabase.instance.client
                          .from('order_items')
                          .select('id, orders!inner(user_id)')
                          .eq('deal_id', deal.id)
                          .eq('orders.user_id', userId)
                          .neq('customer_status', 'refund_success');
                      final purchasedCount = (res as List).length;
                      // 购物车中该 deal 数量
                      final cartItems = ref.read(cartProvider).valueOrNull ?? [];
                      final cartCount = cartItems.where((c) => c.dealId == deal.id).length;
                      if (purchasedCount + cartCount >= deal.maxPerAccount) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("You've reached the purchase limit for this deal"),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                        return;
                      }
                    }
                  }
                  ref.read(cartProvider.notifier).addDeal(
                    deal,
                    purchasedMerchantId: deal.merchant?.id,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Added to cart'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9500),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Center(
                    child: Text(
                      'Add to Cart',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Buy Now 按钮（渐变橙红）
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _handleBuyNow(context, ref, deal),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: AppColors.primaryGradient,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Buy Now',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '\$${deal.discountPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
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

// ── 门店选择 Bottom Sheet（brand deal 购买时弹出）──────────────
class _StorePickerSheet extends StatelessWidget {
  final DealModel deal;

  const _StorePickerSheet({required this.deal});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('deal_applicable_stores')
          .select(
            'store_id, store_original_price, '
            'merchants!deal_applicable_stores_store_id_fkey(id, name, address, logo_url)',
          )
          .eq('deal_id', deal.id)
          .eq('status', 'active'),
      builder: (context, snapshot) {
        final stores = snapshot.data ?? [];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 拖拽条
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select a Store',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose which location to purchase from',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                if (!snapshot.hasData)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  )
                else if (stores.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No stores available',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: stores.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final row = stores[index];
                        final merchant =
                            row['merchants'] as Map<String, dynamic>? ?? {};
                        final storeId = row['store_id'] as String? ?? '';
                        final name = merchant['name'] as String? ?? '';
                        final address = merchant['address'] as String? ?? '';
                        final logoUrl = merchant['logo_url'] as String? ?? '';

                        final storeOrigPrice =
                            (row['store_original_price'] as num?)?.toDouble();
                        String? discountText;
                        if (storeOrigPrice != null && storeOrigPrice > 0) {
                          final pct = ((storeOrigPrice - deal.discountPrice) /
                                  storeOrigPrice *
                                  100)
                              .round();
                          if (pct > 0) discountText = '$pct% off';
                        }

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Navigator.pop(context);
                            context.push(
                              '/checkout/${deal.id}?merchantId=$storeId',
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: AppColors.surfaceVariant),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: logoUrl.isNotEmpty
                                      ? Image.network(
                                          logoUrl,
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          width: 44,
                                          height: 44,
                                          color: AppColors.surfaceVariant,
                                          child: const Icon(Icons.storefront,
                                              size: 20,
                                              color: AppColors.textHint),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (address.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          address,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (discountText != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22C55E)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      discountText,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF16A34A),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                const Icon(Icons.chevron_right,
                                    size: 20, color: AppColors.textHint),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 详情页专用连锁品牌 Badge（品牌 Logo 16px + 品牌名，灰色小字）
class _DetailBrandBadge extends StatelessWidget {
  final MerchantSummary merchant;

  const _DetailBrandBadge({required this.merchant});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 品牌 Logo（16px 圆角）
        if (merchant.brandLogoUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Image.network(
              merchant.brandLogoUrl!,
              width: 16,
              height: 16,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => const Icon(
                Icons.business,
                size: 14,
                color: AppColors.textHint,
              ),
            ),
          ),
          const SizedBox(width: 5),
        ],
        // 品牌名称
        Flexible(
          child: Text(
            merchant.brandName ?? '',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textHint,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
