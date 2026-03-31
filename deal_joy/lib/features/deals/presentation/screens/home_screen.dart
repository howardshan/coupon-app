import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/deal_model.dart';
import '../../../../core/utils/location_utils.dart';
import '../../domain/providers/deals_provider.dart';
import '../../domain/providers/recommendation_provider.dart';
import '../../../merchant/data/models/merchant_model.dart';
import '../../../merchant/domain/providers/merchant_provider.dart';
import '../../../chat/domain/providers/notification_provider.dart';
import '../../../welcome/presentation/widgets/home_banner.dart';

// ── Location data (mirrors web app) ──────────────────────────
const _locationData = {
  'Texas': {
    'DFW': [
      'Dallas',
      'Richardson',
      'Plano',
      'Frisco',
      'Fairview',
      'McKinney',
      'Fort Worth',
      'Arlington',
    ],
    'Austin': ['Austin', 'Round Rock', 'Cedar Park', 'Georgetown'],
    'Houston': ['Houston', 'The Woodlands', 'Sugar Land', 'Katy'],
  },
};

// Use first 6 categories from centralized constants for the icon grid
final _categories = AppConstants.categoryItems.take(6).toList();

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchCtrl = TextEditingController();
  bool _locationMenuOpen = false;
  String _selectionLevel = 'state';
  // 中间选择状态（选州/metro 时暂存，不触发 provider 刷新）
  String _pendingState = 'Texas';
  String _pendingMetro = 'DFW';
  // 搜索模式：'store' 或 'deal'
  String _searchMode = 'store';

  @override
  void initState() {
    super.initState();
    // 监听输入框内容变化，触发 rebuild 以更新小叉按钮的显示/隐藏
    _searchCtrl.addListener(() => setState(() {}));
    // 页面重建时将 Provider 中保存的搜索词同步回输入框，
    // 避免导航离开再回来时搜索框显示为空但仍处于搜索模式的问题
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentQuery = ref.read(searchQueryProvider);
      if (currentQuery.isNotEmpty && _searchCtrl.text != currentQuery) {
        _searchCtrl.text = currentQuery;
        _searchCtrl.selection = TextSelection.collapsed(
          offset: currentQuery.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(selectedLocationProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final isSearching = searchQuery.isNotEmpty;
    final deals = ref.watch(dealsListProvider(0));
    final featuredDeals = ref.watch(featuredDealsProvider);
    // 非搜索模式时加载个性化推荐
    final recommendedDeals = !isSearching ? ref.watch(recommendedDealsProvider) : null;
    final merchantResults =
        isSearching ? ref.watch(merchantSearchProvider) : null;
    final merchantList = ref.watch(merchantListProvider);
    // 搜索无结果时的相似推荐
    final similarDeals = isSearching ? ref.watch(similarDealsProvider) : null;
    final similarMerchants = isSearching ? ref.watch(similarMerchantsProvider) : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(userLocationProvider); // 刷新 GPS 坐标
              ref.invalidate(featuredDealsProvider);
              ref.invalidate(dealsListProvider);
              ref.invalidate(merchantListProvider);
              if (isSearching) ref.invalidate(merchantSearchProvider);
            },
            child: CustomScrollView(
              slivers: [
                // Sticky header — 城市+消息固定在顶部，搜索栏在 bottom
                SliverAppBar(
                  pinned: true,
                  floating: false,
                  backgroundColor: AppColors.accent,
                  surfaceTintColor: Colors.transparent,
                  toolbarHeight: 48,
                  titleSpacing: 0,
                  // 城市选择 + 消息图标（始终固定在顶部）
                  title: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => setState(() {
                            _locationMenuOpen = !_locationMenuOpen;
                            _selectionLevel = 'state';
                            final loc = ref.read(selectedLocationProvider);
                            _pendingState = loc.state;
                            _pendingMetro = loc.metro;
                          }),
                          child: Row(
                            children: [
                              Icon(
                                ref.watch(isNearMeProvider)
                                    ? Icons.my_location
                                    : Icons.location_on,
                                color: AppColors.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                ref.watch(isNearMeProvider)
                                    ? 'Near Me'
                                    : '${location.city}, TX',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 2),
                              AnimatedRotation(
                                turns: _locationMenuOpen ? 0.5 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: const Icon(
                                  Icons.expand_more,
                                  color: AppColors.textSecondary,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        _NotificationBell(),
                      ],
                    ),
                  ),
                  // 搜索栏固定在城市行下方
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(44),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: TextField(
                        key: const ValueKey('home_search_field'),
                        controller: _searchCtrl,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search deals, restaurants...',
                          hintStyle: const TextStyle(fontSize: 14),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          isDense: true,
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppColors.textHint,
                            size: 20,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    ref
                                        .read(searchQueryProvider.notifier)
                                        .state = '';
                                  },
                                )
                              : null,
                        ),
                        onChanged: (v) =>
                            ref.read(searchQueryProvider.notifier).state = v,
                      ),
                    ),
                  ),
                ),

                // ── 搜索模式 ──
                if (isSearching) ...[
                  // Store / Deal 切换
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: [
                          _SearchModeChip(
                            label: 'Store',
                            selected: _searchMode == 'store',
                            onTap: () =>
                                setState(() => _searchMode = 'store'),
                          ),
                          const SizedBox(width: 8),
                          _SearchModeChip(
                            label: 'Deal',
                            selected: _searchMode == 'deal',
                            onTap: () =>
                                setState(() => _searchMode = 'deal'),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Store 模式：商家结果
                  if (_searchMode == 'store')
                    merchantResults!.when(
                      data: (merchants) => merchants.isEmpty
                          ? _NoResultWithSimilar<MerchantModel>(
                              similarAsync: similarMerchants,
                              emptyLabel: 'No restaurants found',
                              itemBuilder: (merchant) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _MerchantCard(merchant: merchant),
                              ),
                            )
                          : SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 0, 16, 100),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 12),
                                    child: _MerchantCard(
                                        merchant: merchants[i]),
                                  ),
                                  childCount: merchants.length,
                                ),
                              ),
                            ),
                      loading: () => const SliverFillRemaining(
                        child:
                            Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => SliverFillRemaining(
                        child: _ErrorRetry(
                          message: 'Failed to load stores',
                          onRetry: () => ref.invalidate(merchantSearchProvider),
                        ),
                      ),
                    ),

                  // Deal 模式：deal 结果
                  if (_searchMode == 'deal')
                    deals.when(
                      data: (list) => list.isEmpty
                          ? _NoResultWithSimilar<DealModel>(
                              similarAsync: similarDeals,
                              emptyLabel: 'No deals found',
                              itemBuilder: (deal) => Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: _LargeDealCard(deal: deal),
                              ),
                            )
                          : SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 0, 16, 100),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 20),
                                    child:
                                        _LargeDealCard(deal: list[i]),
                                  ),
                                  childCount: list.length,
                                ),
                              ),
                            ),
                      loading: () => const SliverFillRemaining(
                        child:
                            Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => SliverFillRemaining(
                        child: _ErrorRetry(
                          message: 'Failed to load deals',
                          onRetry: () => ref.invalidate(dealsListProvider),
                        ),
                      ),
                    ),
                ],

                // ── 正常模式：Banner + 分类 + Featured + Deals ──
                if (!isSearching) ...[
                  // 首页 Banner 轮播
                  const SliverToBoxAdapter(child: HomeBanner()),

                  // GPS 权限被拒提示条（仅 Near Me 模式下显示）
                  if (ref.watch(isNearMeProvider) &&
                      ref.watch(locationPermissionDeniedProvider))
                    SliverToBoxAdapter(
                      child: GestureDetector(
                        onTap: () async {
                          // 检查当前权限状态
                          final current = await Geolocator.checkPermission();
                          if (current == LocationPermission.deniedForever) {
                            // 永久拒绝，直接去系统设置
                            await Geolocator.openAppSettings();
                          } else if (current == LocationPermission.denied) {
                            // 尝试再次请求（iOS 只弹一次对话框）
                            final result = await Geolocator.requestPermission();
                            if (result == LocationPermission.denied ||
                                result == LocationPermission.deniedForever) {
                              // 系统没弹对话框或再次被拒，引导去设置
                              await Geolocator.openAppSettings();
                            }
                          }
                          // 刷新位置 provider 以更新状态
                          ref.invalidate(userLocationProvider);
                          ref.invalidate(featuredDealsProvider);
                          ref.invalidate(dealsListProvider);
                          ref.invalidate(merchantListProvider);
                        },
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.location_off,
                                  color: AppColors.primary, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Location permission is required for Near Me. Tap to enable.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  color: AppColors.textHint, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Category icons
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 88,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: _categories.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: 16),
                        itemBuilder: (_, i) {
                          final cat = _categories[i];
                          final selectedCat =
                              ref.watch(selectedCategoryProvider);
                          final isHot = cat.id == 'hot';
                          final catValue = isHot ? 'All' : cat.name;
                          final isSelected = selectedCat == catValue;
                          return GestureDetector(
                            onTap: () {
                              ref
                                  .read(selectedCategoryProvider.notifier)
                                  .state = catValue;
                            },
                            child: Column(
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary
                                            .withValues(alpha: 0.15)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.06),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    cat.icon,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  cat.name,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // 首页展示券（水平滚动）
                  featuredDeals.when(
                    data: (list) => list.isEmpty
                        ? const SliverToBoxAdapter(
                            child: SizedBox.shrink())
                        : SliverToBoxAdapter(
                            child: SizedBox(
                              height: 190,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.fromLTRB(
                                    16, 8, 16, 0),
                                itemCount: list.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (_, i) => SizedBox(
                                  width: 160,
                                  child: _SmallDealCard(deal: list[i]),
                                ),
                              ),
                            ),
                          ),
                    loading: () => const SliverToBoxAdapter(
                        child: SizedBox.shrink()),
                    error: (e, st) {
                      debugPrint('[ERROR] featuredDeals: $e\n$st');
                      return const SliverToBoxAdapter(
                          child: SizedBox.shrink());
                    },
                  ),

                  // 分隔线
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: Color(0xFFE0E0E0),
                      ),
                    ),
                  ),

                  // 个性化推荐 section
                  if (recommendedDeals != null)
                    recommendedDeals.when(
                      data: (list) => list.isEmpty
                          ? const SliverToBoxAdapter(child: SizedBox.shrink())
                          : SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // section 标题
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.auto_awesome,
                                          size: 16,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          'Recommended For You',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 水平滚动卡片列表，复用 _SmallDealCard
                                  SizedBox(
                                    height: 190,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                                      itemCount: list.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 8),
                                      itemBuilder: (_, i) => SizedBox(
                                        width: 160,
                                        child: _SmallDealCard(deal: list[i]),
                                      ),
                                    ),
                                  ),
                                  // 推荐区域和商家网格之间的分隔线
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                                    child: Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: Color(0xFFE0E0E0),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      // 加载中静默不显示占位
                      loading: () =>
                          const SliverToBoxAdapter(child: SizedBox.shrink()),
                      error: (e, st) {
                        debugPrint('[ERROR] recommendedDeals: $e\n$st');
                        return const SliverToBoxAdapter(child: SizedBox.shrink());
                      },
                    ),

                  // 商家双列网格
                  merchantList.when(
                    data: (merchants) => merchants.isEmpty
                        ? const SliverFillRemaining(
                            child: Center(
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.store_outlined,
                                      size: 64,
                                      color: AppColors.textHint),
                                  SizedBox(height: 12),
                                  Text('No restaurants found'),
                                ],
                              ),
                            ),
                          )
                        : SliverPadding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 100),
                            sliver: SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.72,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (_, i) => _MerchantGridCard(
                                    merchant: merchants[i]),
                                childCount: merchants.length,
                              ),
                            ),
                          ),
                    loading: () => const SliverFillRemaining(
                      child:
                          Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => SliverFillRemaining(
                      child: _ErrorRetry(
                        message: 'Failed to load restaurants',
                        onRetry: () {
                          ref.invalidate(merchantListProvider);
                          ref.invalidate(featuredDealsProvider);
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Location dropdown overlay
          if (_locationMenuOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _locationMenuOpen = false),
                child: Container(color: Colors.black.withValues(alpha: 0.15)),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 16,
              child: _LocationDropdown(
                location: (state: _pendingState, metro: _pendingMetro, city: ref.read(selectedLocationProvider).city),
                selectionLevel: _selectionLevel,
                onLevelChange: (level) =>
                    setState(() => _selectionLevel = level),
                onStateChange: (state) => setState(() {
                  _pendingState = state;
                  _pendingMetro = _locationData[state]!.keys.first;
                }),
                onMetroChange: (metro) => setState(() {
                  _pendingMetro = metro;
                }),
                onCitySelected: (city) {
                  ref.read(isNearMeProvider.notifier).state = false;
                  ref.read(selectedLocationProvider.notifier).state = (
                    state: _pendingState,
                    metro: _pendingMetro,
                    city: city,
                  );
                  ref.invalidate(merchantListProvider);
                  ref.invalidate(featuredDealsProvider);
                  ref.invalidate(dealsListProvider);
                  setState(() => _locationMenuOpen = false);
                },
                onNearMeSelected: () {
                  debugPrint('[DEBUG] HomeScreen → Near Me 被选中');
                  ref.read(isNearMeProvider.notifier).state = true;
                  debugPrint('[DEBUG] HomeScreen → isNearMe 设为 true, 开始 invalidate providers');
                  ref.invalidate(userLocationProvider); // 重新获取 GPS 坐标
                  ref.invalidate(merchantListProvider);
                  ref.invalidate(featuredDealsProvider);
                  ref.invalidate(dealsListProvider);
                  setState(() => _locationMenuOpen = false);
                },
                isNearMeSelected: ref.read(isNearMeProvider),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Location dropdown ─────────────────────────────────────────
class _LocationDropdown extends StatelessWidget {
  final ({String state, String metro, String city}) location;
  final String selectionLevel;
  final void Function(String) onLevelChange;
  final void Function(String) onStateChange;
  final void Function(String) onMetroChange;
  final void Function(String) onCitySelected;
  final VoidCallback onNearMeSelected;
  final bool isNearMeSelected;

  const _LocationDropdown({
    required this.location,
    required this.selectionLevel,
    required this.onLevelChange,
    required this.onStateChange,
    required this.onMetroChange,
    required this.onCitySelected,
    required this.onNearMeSelected,
    required this.isNearMeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 240,
        constraints: const BoxConstraints(maxHeight: 300),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  if (selectionLevel != 'state')
                    GestureDetector(
                      onTap: () => onLevelChange(
                        selectionLevel == 'city' ? 'metro' : 'state',
                      ),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.arrow_back, size: 16),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    selectionLevel == 'state'
                        ? 'Select State'
                        : selectionLevel == 'metro'
                        ? 'Metro Area'
                        : 'Select City',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Column(children: _buildItems()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildItems() {
    if (selectionLevel == 'state') {
      return [
        // Near Me 选项（置顶）
        _LocationItem(
          label: 'Near Me',
          selected: isNearMeSelected,
          icon: Icons.my_location,
          onTap: onNearMeSelected,
        ),
        const Divider(height: 8),
        ..._locationData.keys.map((state) {
          return _LocationItem(
            label: state,
            selected: !isNearMeSelected && location.state == state,
            hasChildren: true,
            onTap: () {
              onStateChange(state);
              onLevelChange('metro');
            },
          );
        }),
      ];
    }
    if (selectionLevel == 'metro') {
      return _locationData[location.state]!.keys.map((metro) {
        return _LocationItem(
          label: metro,
          selected: location.metro == metro,
          hasChildren: true,
          onTap: () {
            onMetroChange(metro);
            onLevelChange('city');
          },
        );
      }).toList();
    }
    final cities = _locationData[location.state]![location.metro]!;
    return cities.map((city) {
      return _LocationItem(
        label: city,
        selected: location.city == city,
        hasChildren: false,
        onTap: () => onCitySelected(city),
      );
    }).toList();
  }
}

class _LocationItem extends StatelessWidget {
  final String label;
  final bool selected;
  final bool hasChildren;
  final VoidCallback onTap;
  final IconData? icon;

  const _LocationItem({
    required this.label,
    required this.selected,
    required this.onTap,
    this.hasChildren = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16,
                      color: selected ? AppColors.primary : AppColors.textSecondary),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: selected ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            if (hasChildren)
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: AppColors.textHint,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Large vertical deal card (Home feed) ─────────────────────
class _LargeDealCard extends ConsumerWidget {
  final DealModel deal;

  const _LargeDealCard({required this.deal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => context.push('/deals/${deal.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: (deal.imageUrls.isNotEmpty || deal.merchant?.homepageCoverUrl != null)
                      ? CachedNetworkImage(
                          imageUrl: deal.imageUrls.isNotEmpty
                              ? deal.imageUrls.first
                              : deal.merchant!.homepageCoverUrl!,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          height: 200,
                          color: AppColors.surfaceVariant,
                          child: const Icon(Icons.restaurant, size: 48),
                        ),
                ),
                // Discount label
                Positioned(
                  top: 14,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      deal.effectiveDiscountLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // 收藏按钮
                Positioned(
                  top: 10,
                  right: 10,
                  child: GestureDetector(
                    onTap: () => ref
                        .read(savedDealsNotifierProvider.notifier)
                        .toggle(deal.id),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        (ref.watch(savedDealIdsProvider).valueOrNull ?? {})
                                .contains(deal.id)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 18,
                        color: (ref.watch(savedDealIdsProvider).valueOrNull ??
                                    {})
                                .contains(deal.id)
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deal.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.storefront,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          deal.merchant?.name ?? '',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.star,
                              size: 13,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              deal.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.near_me,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      // 距离文字：固定宽度，防止过长撑破行
                      _DistanceText(deal: deal),
                      const SizedBox(width: 6),
                      const Text(
                        '•',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 6),
                      // 分类标签：用 Flexible 包裹，超长时截断
                      Flexible(
                        child: Text(
                          deal.category,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        '\$${deal.discountPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '\$${deal.originalPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 14,
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

// ── GPS 距离文本 ─────────────────────────────────────────────
class _DistanceText extends ConsumerWidget {
  final DealModel deal;
  const _DistanceText({required this.deal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userLoc = ref.watch(userLocationProvider);
    final distance = userLoc.whenOrNull(data: (loc) {
      if (deal.lat == null || deal.lng == null) return null;
      return haversineDistanceMiles(loc.lat, loc.lng, deal.lat!, deal.lng!);
    });
    final text = distance != null
        ? '${distance.toStringAsFixed(1)} mi'
        : '--';
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        color: AppColors.textSecondary,
      ),
    );
  }
}

// ── Small horizontal deal card (Featured) ────────────────────
class _SmallDealCard extends StatelessWidget {
  final DealModel deal;

  const _SmallDealCard({required this.deal});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/deals/${deal.id}'),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: (deal.imageUrls.isNotEmpty || deal.merchant?.homepageCoverUrl != null)
                          ? CachedNetworkImage(
                              imageUrl: deal.imageUrls.isNotEmpty
                                  ? deal.imageUrls.first
                                  : deal.merchant!.homepageCoverUrl!,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                            )
                          : Container(color: AppColors.surfaceVariant),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        deal.effectiveDiscountLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deal.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${deal.discountPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
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

// ── Search mode toggle chip ──────────────────────────────────
class _SearchModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SearchModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.surfaceVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Merchant grid card (首页双列) ─────────────────────────────
class _MerchantGridCard extends StatelessWidget {
  final MerchantModel merchant;

  const _MerchantGridCard({required this.merchant});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/merchant/${merchant.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图片
            Expanded(
              child: SizedBox.expand(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: () {
                    // 优先 homepage cover，fallback 到 logo
                    final coverUrl = merchant.homepageCoverUrl ?? merchant.logoUrl;
                    return coverUrl != null && coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: coverUrl,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: AppColors.surfaceVariant,
                          child: const Center(
                            child: Icon(Icons.restaurant,
                                size: 40, color: AppColors.textHint),
                          ),
                        );
                  }(),
                ),
              ),
            ),
            // 信息区
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 店名
                  Text(
                    merchant.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // 评分 + 评价数
                  Row(
                    children: [
                      if (merchant.avgRating != null) ...[
                        const Icon(Icons.star,
                            size: 13, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          merchant.avgRating!.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (merchant.totalReviewCount != null &&
                          merchant.totalReviewCount! > 0)
                        Text(
                          '${merchant.totalReviewCount} reviews',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      // Near Me 模式下显示距离
                      if (merchant.distanceMiles != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${merchant.distanceMiles!.toStringAsFixed(1)} mi',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  // 折扣价
                  if (merchant.bestDiscount != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'From \$${merchant.bestDiscount!.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Merchant card (search results) ───────────────────────────
class _MerchantCard extends StatelessWidget {
  final MerchantModel merchant;

  const _MerchantCard({required this.merchant});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/merchant/${merchant.id}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // 优先 homepage cover，fallback 到 logo
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: () {
                final coverUrl = merchant.homepageCoverUrl ?? merchant.logoUrl;
                return coverUrl != null && coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: coverUrl,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 64,
                      height: 64,
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.restaurant,
                          color: AppColors.textHint),
                    );
              }(),
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
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (merchant.address != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            merchant.address!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (merchant.phone != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.phone,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        // 电话号码可能较长，用 Flexible 防止溢出
                        Flexible(
                          child: Text(
                            merchant.phone!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

// ── 通知铃铛图标（动态 badge）──────────────────────────────────
class _NotificationBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadAsync = ref.watch(unreadNotificationCountProvider);
    final unread = unreadAsync.valueOrNull ?? 0;

    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => context.push('/chat/notifications'),
        ),
        if (unread > 0)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

// ── 网络错误重试组件 ──────────────────────────────────────────
class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Please check your network connection',
              style: TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 搜索无结果时显示 "No Result" + 相似推荐列表
class _NoResultWithSimilar<T> extends StatelessWidget {
  final AsyncValue<List<T>>? similarAsync;
  final String emptyLabel;
  final Widget Function(T item) itemBuilder;

  const _NoResultWithSimilar({
    super.key,
    required this.similarAsync,
    required this.emptyLabel,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final similarItems = similarAsync?.valueOrNull ?? [];

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          // No Result 提示
          const SizedBox(height: 48),
          const Center(
            child: Icon(Icons.search_off, size: 64, color: AppColors.textHint),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              emptyLabel,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          // Similar 推荐区域
          if (similarItems.isNotEmpty) ...[
            const SizedBox(height: 32),
            const Center(
              child: Text(
                'You might also like',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Center(
              child: Text(
                'Popular picks near you',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textHint,
                ),
              ),
            ),
            const Divider(height: 32),
            ...similarItems.map(itemBuilder),
          ],
        ]),
      ),
    );
  }
}
