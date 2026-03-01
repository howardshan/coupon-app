import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/deal_model.dart';
import '../../domain/providers/deals_provider.dart';

// ── Location data (mirrors web app) ──────────────────────────
const _locationData = {
  'Texas': {
    'DFW': [
      'Dallas',
      'Richardson',
      'Plano',
      'Frisco',
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

// Selected location provider
final selectedLocationProvider =
    StateProvider<({String state, String metro, String city})>(
      (ref) => (state: 'Texas', metro: 'DFW', city: 'Dallas'),
    );

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchCtrl = TextEditingController();
  bool _locationMenuOpen = false;
  String _selectionLevel = 'state';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(selectedLocationProvider);
    final deals = ref.watch(dealsListProvider(0));
    final featuredDeals = ref.watch(featuredDealsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(dealsListProvider);
              ref.invalidate(featuredDealsProvider);
            },
            child: CustomScrollView(
              slivers: [
                // Sticky header
                SliverAppBar(
                  pinned: true,
                  backgroundColor: AppColors.background.withValues(alpha: 0.95),
                  surfaceTintColor: Colors.transparent,
                  expandedHeight: 120,
                  flexibleSpace: FlexibleSpaceBar(
                    background: SafeArea(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () => setState(() {
                                    _locationMenuOpen = !_locationMenuOpen;
                                    _selectionLevel = 'state';
                                  }),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on,
                                        color: AppColors.primary,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${location.city}, TX',
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      AnimatedRotation(
                                        turns: _locationMenuOpen ? 0.5 : 0,
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
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
                                Stack(
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.notifications_outlined,
                                      ),
                                      onPressed: () {},
                                    ),
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
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: 'Search deals, restaurants...',
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: AppColors.textHint,
                                ),
                                suffixIcon: _searchCtrl.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          ref
                                                  .read(
                                                    searchQueryProvider
                                                        .notifier,
                                                  )
                                                  .state =
                                              '';
                                        },
                                      )
                                    : null,
                              ),
                              onChanged: (v) =>
                                  ref.read(searchQueryProvider.notifier).state =
                                      v,
                            ),
                          ),
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
                      separatorBuilder: (_, _) => const SizedBox(width: 16),
                      itemBuilder: (_, i) {
                        final cat = _categories[i];
                        final isHot = cat.id == 'hot';
                        return Column(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: isHot
                                    ? AppColors.primary.withValues(alpha: 0.1)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                cat.icon,
                                color: isHot
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              cat.name,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                // Featured deals (horizontal)
                featuredDeals.when(
                  data: (featured) => featured.isEmpty
                      ? const SliverToBoxAdapter(child: SizedBox.shrink())
                      : SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  10,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Featured',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {},
                                      child: const Text(
                                        'View All',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: 190,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  itemCount: featured.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 12),
                                  itemBuilder: (_, i) => SizedBox(
                                    width: 190,
                                    child: _SmallDealCard(deal: featured[i]),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                  loading: () =>
                      const SliverToBoxAdapter(child: SizedBox.shrink()),
                  error: (_, _) =>
                      const SliverToBoxAdapter(child: SizedBox.shrink()),
                ),

                // All deals header
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
                    child: Text(
                      'High-Quality Deals',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // Deals vertical list
                deals.when(
                  data: (list) => list.isEmpty
                      ? const SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 64,
                                  color: AppColors.textHint,
                                ),
                                SizedBox(height: 12),
                                Text('No deals found'),
                              ],
                            ),
                          ),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: _LargeDealCard(deal: list[i]),
                              ),
                              childCount: list.length,
                            ),
                          ),
                        ),
                  loading: () => const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => SliverFillRemaining(
                    child: Center(child: Text('Error: $e')),
                  ),
                ),
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
                location: ref.read(selectedLocationProvider),
                selectionLevel: _selectionLevel,
                onLevelChange: (level) =>
                    setState(() => _selectionLevel = level),
                onStateChange: (state) =>
                    ref.read(selectedLocationProvider.notifier).state = (
                      state: state,
                      metro: _locationData[state]!.keys.first,
                      city: (_locationData[state]!.values.first)[0],
                    ),
                onMetroChange: (metro) {
                  final state = ref.read(selectedLocationProvider).state;
                  ref.read(selectedLocationProvider.notifier).state = (
                    state: state,
                    metro: metro,
                    city: (_locationData[state]![metro]!)[0],
                  );
                },
                onCitySelected: (city) {
                  final loc = ref.read(selectedLocationProvider);
                  ref.read(selectedLocationProvider.notifier).state = (
                    state: loc.state,
                    metro: loc.metro,
                    city: city,
                  );
                  setState(() => _locationMenuOpen = false);
                },
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

  const _LocationDropdown({
    required this.location,
    required this.selectionLevel,
    required this.onLevelChange,
    required this.onStateChange,
    required this.onMetroChange,
    required this.onCitySelected,
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
      return _locationData.keys.map((state) {
        return _LocationItem(
          label: state,
          selected: location.state == state,
          hasChildren: true,
          onTap: () {
            onStateChange(state);
            onLevelChange('metro');
          },
        );
      }).toList();
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

  const _LocationItem({
    required this.label,
    required this.selected,
    required this.hasChildren,
    required this.onTap,
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
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: selected ? AppColors.primary : AppColors.textPrimary,
              ),
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
class _LargeDealCard extends StatelessWidget {
  final DealModel deal;

  const _LargeDealCard({required this.deal});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/merchant/${deal.merchantId}'),
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
                  child: deal.imageUrls.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: deal.imageUrls.first,
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
                // Fav button
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.favorite_border,
                      size: 18,
                      color: AppColors.textPrimary,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          deal.merchant?.name ?? '',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
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
                      const Text(
                        '1.2 mi',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '•',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        deal.category,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
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
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: deal.imageUrls.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: deal.imageUrls.first,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          )
                        : Container(color: AppColors.surfaceVariant),
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
