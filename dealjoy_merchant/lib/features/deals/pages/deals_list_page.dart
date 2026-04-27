// Deal列表页面
// 展示商家所有Deal，支持Tab筛选(All/Active/Inactive/Pending Review)
// 右下角FAB按钮跳转创建Deal页面

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../store/providers/store_provider.dart';
import '../models/merchant_deal.dart';
import '../models/deal_category.dart';
import '../open_merchant_deal_detail.dart';
import '../providers/deals_provider.dart';
import '../widgets/deal_card.dart';

// ============================================================
// DealsListPage — Deal列表主页（ConsumerWidget）
// ============================================================
class DealsListPage extends ConsumerWidget {
  const DealsListPage({super.key, this.brandOnly = false});

  /// true = 只显示品牌多店 Deal（applicableMerchantIds 非空）
  final bool brandOnly;

  // 打开分类管理 BottomSheet
  void _showCategoryManager(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CategoryManagerSheet(ref: ref),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF333333)),
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                context.go('/dashboard');
              }
            },
          ),
          title: Text(
            brandOnly ? 'Brand Deals' : 'My Deals',
            style: const TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: false,
          actions: [
            // V2.2 模板管理按钮（仅品牌管理员可见）
            if (ref.watch(storeProvider).valueOrNull?.isChainStore == true)
              IconButton(
                icon: const Icon(Icons.copy_all_outlined, color: Color(0xFF666666)),
                tooltip: 'Deal Templates',
                onPressed: () => context.push('/deals/templates'),
              ),
            // 分类管理按钮
            IconButton(
              icon: const Icon(Icons.category_outlined, color: Color(0xFF666666)),
              tooltip: 'Manage Categories',
              onPressed: () => _showCategoryManager(context, ref),
            ),
            // 刷新按钮
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF666666)),
              onPressed: () => ref.read(dealsProvider.notifier).refresh(),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Color(0xFFFF6B35),
            unselectedLabelColor: Color(0xFF999999),
            indicatorColor: Color(0xFFFF6B35),
            indicatorWeight: 2.5,
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: TextStyle(fontSize: 13),
            tabs: [
              Tab(text: 'All'),
              Tab(text: 'Active'),
              Tab(text: 'Inactive'),
              Tab(text: 'Pending'),
              Tab(text: 'Declined'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // All — 全部 Deal（无筛选）
            _DealTabView(filter: null, ref: ref, brandOnly: brandOnly),
            // Active — 已上架
            _DealTabView(filter: DealStatus.active, ref: ref, brandOnly: brandOnly),
            // Inactive — 已下架
            _DealTabView(filter: DealStatus.inactive, ref: ref, brandOnly: brandOnly),
            // Pending — 待审核
            _DealTabView(filter: DealStatus.pending, ref: ref, brandOnly: brandOnly),
            // Declined — 已拒绝的品牌 Deal
            const _DeclinedDealsTab(),
          ],
        ),

        // FAB: 创建新 Deal
        // FAB: 创建新 Deal
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/deals/create'),
          backgroundColor: const Color(0xFFFF6B35),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'Create Deal',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 单个 Tab 视图（对应一种筛选状态）
// filter == null 时为 All tab，启用拖拽排序
// ============================================================
class _DealTabView extends ConsumerWidget {
  const _DealTabView({required this.filter, required this.ref, this.brandOnly = false});

  /// null = All（不筛选），其他 tab 不支持拖拽
  final DealStatus? filter;
  final WidgetRef ref;

  /// 只显示品牌多店 Deal
  final bool brandOnly;

  @override
  Widget build(BuildContext context, WidgetRef consumerRef) {
    final allDealsAsync = consumerRef.watch(dealsProvider);

    return allDealsAsync.when(
      loading: () => const _LoadingView(),
      error: (e, _) => _ErrorView(
        error: e.toString(),
        onRetry: () => consumerRef.read(dealsProvider.notifier).refresh(),
      ),
      data: (deals) {
        // 品牌模式：只显示多店 Deal
        var source = brandOnly
            ? deals.where((d) => d.applicableMerchantIds != null && d.applicableMerchantIds!.isNotEmpty).toList()
            : deals;
        // 按状态筛选；Active tab 排除已过期的 deal（DB deal_status 仍为 active 但 expires_at 已过）
        final filtered = filter == null
            ? source
            : source.where((d) {
                if (filter == DealStatus.active) {
                  return d.dealStatus == DealStatus.active && !d.isExpiredByDate;
                }
                return d.dealStatus == filter;
              }).toList();

        if (filtered.isEmpty) {
          return _EmptyView(filter: filter);
        }

        // All tab（filter == null）：使用可拖拽排序列表
        if (filter == null) {
          return RefreshIndicator(
            color: const Color(0xFFFF6B35),
            onRefresh: () => consumerRef.read(dealsProvider.notifier).refresh(),
            child: ReorderableListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 100),
              itemCount: filtered.length,
              // 拖拽完成回调：调用 provider 更新 sort_order
              onReorder: (oldIndex, newIndex) {
                consumerRef.read(dealsProvider.notifier).reorderDeals(
                  oldIndex: oldIndex,
                  newIndex: newIndex,
                  deals: filtered,
                );
              },
              // 每个 item 必须有唯一 Key，ReorderableListView 要求
              itemBuilder: (context, index) {
                final deal = filtered[index];
                return _ReorderableDealRow(
                  key: ValueKey(deal.id),
                  index: index,
                  deal: deal,
                  onTap: () {
                    openMerchantDealDetail(context, deal.id);
                  },
                );
              },
            ),
          );
        }

        // 其他 tab：普通 ListView，不支持拖拽
        return RefreshIndicator(
          color: const Color(0xFFFF6B35),
          onRefresh: () => consumerRef.read(dealsProvider.notifier).refresh(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 100),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final deal = filtered[index];
              return DealCard(
                deal: deal,
                onTap: () {
                  openMerchantDealDetail(context, deal.id);
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ============================================================
// 可拖拽的 Deal 行（All tab 专用）
// 在 DealCard 右侧叠加拖拽手柄图标
// index 由 ReorderableListView.builder 的 itemBuilder 传入
// ============================================================
class _ReorderableDealRow extends StatelessWidget {
  const _ReorderableDealRow({
    super.key,
    required this.index,
    required this.deal,
    required this.onTap,
  });

  /// 当前行在列表中的位置，ReorderableDragStartListener 必须
  final int index;
  final MerchantDeal deal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        // Deal 卡片（保持原有 UI 不变）
        DealCard(
          deal: deal,
          onTap: onTap,
        ),
        // 拖拽手柄：使用 ReorderableDragStartListener 激活拖拽
        Positioned(
          right: 12,
          child: ReorderableDragStartListener(
            index: index,
            child: const Icon(
              Icons.drag_handle,
              key: ValueKey('deal_list_drag_handle'),
              color: Color(0xFFBBBBBB),
              size: 24,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 加载骨架屏
// ============================================================
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: 5,
      itemBuilder: (_, index) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        height: 88,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // 图片骨架
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: Color(0xFFEEEEEE),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 文字骨架
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEEEEE),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEEEEE),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 空状态视图
// ============================================================
class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.filter});

  final DealStatus? filter;

  @override
  Widget build(BuildContext context) {
    // 根据筛选类型定制文案
    final message = _getMessage(filter);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.local_offer_outlined,
              size: 72,
              color: Color(0xFFDDDDDD),
            ),
            const SizedBox(height: 16),
            Text(
              message.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message.subtitle,
              style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
              textAlign: TextAlign.center,
            ),
            if (filter == null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => context.push('/deals/create'),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create Your First Deal'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 根据筛选类型返回对应文案
  ({String title, String subtitle}) _getMessage(DealStatus? filter) {
    switch (filter) {
      case DealStatus.active:
        return (
          title: 'No Active Deals',
          subtitle: 'Approved deals that you have activated will appear here.',
        );
      case DealStatus.inactive:
        return (
          title: 'No Inactive Deals',
          subtitle: 'Deals you have deactivated will appear here.',
        );
      case DealStatus.pending:
        return (
          title: 'No Pending Deals',
          subtitle: 'Deals waiting for review will appear here.',
        );
      default:
        return (
          title: 'No Deals Yet',
          subtitle: 'Create your first deal to start attracting customers!',
        );
    }
  }
}

// ============================================================
// 错误视图
// ============================================================
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 64, color: Color(0xFFCCCCCC)),
            const SizedBox(height: 16),
            const Text(
              'Failed to load deals',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Declined Tab — 展示被拒绝的品牌 Deal 列表
// 数据来源：declinedStoreDealsProvider（不来自 dealsProvider）
// ============================================================
class _DeclinedDealsTab extends ConsumerWidget {
  const _DeclinedDealsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final declinedAsync = ref.watch(declinedStoreDealsProvider);

    return declinedAsync.when(
      // 加载中显示进度指示器
      loading: () => const Center(child: CircularProgressIndicator()),
      // 出错显示错误提示
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 64, color: Color(0xFFCCCCCC)),
              const SizedBox(height: 16),
              const Text(
                'Failed to load declined deals',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                e.toString(),
                style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
      data: (deals) {
        // 空列表显示空状态
        if (deals.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.block_outlined,
                    size: 72,
                    color: Color(0xFFDDDDDD),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No Declined Deals',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Brand deals you have declined will appear here.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        // 渲染 Deal 列表
        return ListView.separated(
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          itemCount: deals.length,
          separatorBuilder: (_, i) => Divider(height: 1, color: Colors.grey.shade100),
          itemBuilder: (context, index) {
            final row = deals[index];
            final dealId = row['deal_id'] as String? ?? '';

            // 解析嵌套的 deals join 结果
            final dealData = row['deals'] as Map<String, dynamic>? ?? {};
            final title = dealData['title'] as String? ?? 'Untitled Deal';
            final price = (dealData['discount_price'] as num?)?.toDouble() ?? 0.0;

            // 解析品牌名称（双重嵌套）
            final merchantData = dealData['merchants'] as Map<String, dynamic>? ?? {};
            final brandName = merchantData['name'] as String? ?? 'Brand';

            // 解析 deal 图片（优先 is_primary，否则取 sort_order 最小的）
            final dealImages = (dealData['deal_images'] as List<dynamic>?) ?? [];
            String? imageUrl;
            if (dealImages.isNotEmpty) {
              final primary = dealImages.firstWhere(
                (img) => img['is_primary'] == true,
                orElse: () => dealImages.first,
              );
              imageUrl = primary['image_url'] as String?;
            }

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFFF5F5F5),
                            child: const Icon(Icons.local_offer_outlined, size: 20, color: Color(0xFF9E9E9E)),
                          ),
                        )
                      : Container(
                          color: const Color(0xFFF5F5F5),
                          child: const Icon(Icons.local_offer_outlined, size: 20, color: Color(0xFF9E9E9E)),
                        ),
                ),
              ),
              title: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '$brandName · \$${price.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
              ),
              trailing: const Icon(Icons.chevron_right, color: Color(0xFF9E9E9E)),
              // 点击跳转到 Deal 确认页
              onTap: () => context.push(
                '/deals/confirm/$dealId',
                extra: {
                  'title': title,
                  'price': price,
                  'brand_name': brandName,
                },
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================
// 分类管理 BottomSheet
// ============================================================
class _CategoryManagerSheet extends ConsumerStatefulWidget {
  const _CategoryManagerSheet({required this.ref});

  final WidgetRef ref;

  @override
  ConsumerState<_CategoryManagerSheet> createState() =>
      _CategoryManagerSheetState();
}

class _CategoryManagerSheetState extends ConsumerState<_CategoryManagerSheet> {
  static const _orange = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(dealCategoriesProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 拖拽把手 + 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  const Text(
                    'Deal Categories',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const Spacer(),
                  // 添加按钮
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: _orange),
                    onPressed: () => _showAddCategoryDialog(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF999999)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(),
            // 分类列表
            Expanded(
              child: categoriesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Failed to load: $e',
                      style: const TextStyle(color: Colors.red)),
                ),
                data: (categories) {
                  if (categories.isEmpty) {
                    return const Center(
                      child: Text(
                        'No categories yet.\nTap + to create one.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 14, color: Color(0xFF999999)),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final cat = categories[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          cat.name,
                          style: const TextStyle(
                              fontSize: 15, color: Color(0xFF333333)),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 编辑
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  size: 20, color: Color(0xFF666666)),
                              onPressed: () =>
                                  _showEditCategoryDialog(cat),
                            ),
                            // 删除
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: Color(0xFFE53935)),
                              onPressed: () =>
                                  _confirmDeleteCategory(cat),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // 添加分类对话框
  void _showAddCategoryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Category'),
        content: TextField(
          key: const ValueKey('deals_list_new_category_field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Category name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _orange),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final service = ref.read(dealsServiceProvider);
                final categories =
                    ref.read(dealCategoriesProvider).valueOrNull ?? [];
                await service.createDealCategory(
                  merchantId:
                      ref.read(dealsProvider.notifier).merchantId,
                  name: name,
                  sortOrder: categories.length,
                );
                // 刷新分类列表
                ref.invalidate(dealCategoriesProvider);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to create: $e')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // 编辑分类对话框
  void _showEditCategoryDialog(DealCategory cat) {
    final controller = TextEditingController(text: cat.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Category'),
        content: TextField(
          key: const ValueKey('deals_list_edit_category_field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Category name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _orange),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty || name == cat.name) {
                Navigator.pop(ctx);
                return;
              }
              Navigator.pop(ctx);
              try {
                final service = ref.read(dealsServiceProvider);
                await service.updateDealCategory(
                  id: cat.id,
                  name: name,
                );
                ref.invalidate(dealCategoriesProvider);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to update: $e')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // 删除确认
  void _confirmDeleteCategory(DealCategory cat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
            'Are you sure you want to delete "${cat.name}"?\nDeals in this category will become uncategorized.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935)),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final service = ref.read(dealsServiceProvider);
                await service.deleteDealCategory(cat.id);
                ref.invalidate(dealCategoriesProvider);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete: $e')),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
