import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/menu_item_model.dart';
import '../../domain/providers/store_detail_provider.dart';
import 'menu_item_card.dart';

/// Menu Tab 组件
/// 复用 MenuItemCard，使用 CustomScrollView 适配 NestedScrollView
class MenuTab extends ConsumerStatefulWidget {
  final String merchantId;

  const MenuTab({super.key, required this.merchantId});

  @override
  ConsumerState<MenuTab> createState() => _MenuTabState();
}

class _MenuTabState extends ConsumerState<MenuTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final menuAsync = ref.watch(menuItemsProvider(widget.merchantId));

    return menuAsync.when(
      data: (grouped) => _buildContent(grouped),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Failed to load menu',
            style: TextStyle(color: AppColors.textSecondary)),
      ),
    );
  }

  Widget _buildContent(Map<String, List<MenuItemModel>> grouped) {
    final signature = grouped['signature'] ?? [];
    final popular = grouped['popular'] ?? [];
    final regular = grouped['regular'] ?? [];

    if (signature.isEmpty && popular.isEmpty && regular.isEmpty) {
      return const Center(
        child: Text('No menu items available',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return CustomScrollView(
      slivers: [
        // Signature Dishes 横滑
        if (signature.isNotEmpty) ...[
          _buildSectionHeader('Signature Dishes', signature.length),
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
          _buildSectionHeader('Popular Picks', popular.length),
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
          _buildSectionHeader('All Items', regular.length),
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

        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  SliverToBoxAdapter _buildSectionHeader(String title, int count) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(width: 6),
            Text('($count)',
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
