import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/store_detail_provider.dart';
import 'deal_card_v2.dart';
import 'deal_category_filter.dart';
import 'deal_voucher_section.dart';

/// Deals Tab 组件
/// 包含代金券区域 + 分类标签二级吸顶 + Deal 列表
/// 使用 CustomScrollView + SliverPersistentHeader 实现分类标签吸顶
class DealsTab extends ConsumerStatefulWidget {
  final String merchantId;

  const DealsTab({super.key, required this.merchantId});

  @override
  ConsumerState<DealsTab> createState() => _DealsTabState();
}

class _DealsTabState extends ConsumerState<DealsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final dealsAsync =
        ref.watch(merchantActiveDealsProvider(widget.merchantId));
    final categoriesAsync =
        ref.watch(dealCategoriesProvider(widget.merchantId));
    final selectedCategory =
        ref.watch(selectedDealCategoryProvider(widget.merchantId));
    final filtered = ref.watch(filteredDealsProvider(widget.merchantId));

    // 如果 deals 还在加载中，显示加载指示器
    if (dealsAsync.isLoading) {
      return const CustomScrollView(
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.secondary),
            ),
          ),
        ],
      );
    }

    // 如果 deals 加载出错，显示错误信息
    if (dealsAsync.hasError) {
      return CustomScrollView(
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load deals',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      // 不要传自定义 ScrollController，让 NestedScrollView 管理
      slivers: [
        // 代金券区域
        if (filtered.vouchers.isNotEmpty)
          SliverToBoxAdapter(
            child: DealVoucherSection(vouchers: filtered.vouchers),
          ),

        // 分类标签 — 二级吸顶
        categoriesAsync.when(
          data: (categories) {
            if (categories.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
            return SliverPersistentHeader(
              pinned: true,
              delegate: DealCategoryFilterDelegate(
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
          error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
        ),

        // Deal 列表（无代金券也无普通 deal 时显示空状态）
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
              (context, index) => DealCardV2(deal: filtered.regulars[index]),
              childCount: filtered.regulars.length,
            ),
          ),

        // 底部间距
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}
