// 购物车页面 — V3 DB 持久化版本
// 每张券独立一行，同一 deal 的多张券视觉分组展示，底部显示 service fee

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/cart_item_model.dart';
import '../../domain/providers/cart_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartAsync = ref.watch(cartProvider);
    final totalPrice = ref.watch(cartTotalPriceProvider);
    final serviceFee = ref.watch(cartServiceFeeProvider);
    final itemCount = ref.watch(cartTotalCountProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 标题栏 ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Shopping Cart',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  // 有商品时显示 Clear All 按钮
                  if (itemCount > 0)
                    TextButton(
                      onPressed: () =>
                          ref.read(cartProvider.notifier).clear(),
                      child: const Text(
                        'Clear All',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── 列表 / Loading / 空状态 ────────────────────
            Expanded(
              child: cartAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Failed to load cart. Please try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
                data: (items) {
                  if (items.isEmpty) return const _EmptyCart();

                  // 按 dealId 分组，保留原始顺序
                  final groups = _groupByDeal(items);

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: groups.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      return _DealGroup(items: group);
                    },
                  );
                },
              ),
            ),

            // ── 底部结算栏（有商品时显示）──────────────────
            if (itemCount > 0)
              _CheckoutBar(
                totalPrice: totalPrice,
                serviceFee: serviceFee,
                itemCount: itemCount,
              ),
          ],
        ),
      ),
    );
  }

  /// 按 dealId 分组，保持第一次出现的顺序
  List<List<CartItemModel>> _groupByDeal(List<CartItemModel> items) {
    final Map<String, List<CartItemModel>> map = {};
    final List<String> order = [];
    for (final item in items) {
      if (!map.containsKey(item.dealId)) {
        map[item.dealId] = [];
        order.add(item.dealId);
      }
      map[item.dealId]!.add(item);
    }
    return order.map((id) => map[id]!).toList();
  }
}

// ── 空购物车 ──────────────────────────────────────────────────
class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shopping_cart_outlined,
              size: 40,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Your cart is empty',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Looks like you haven't added\nany deals to your cart yet.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => context.go('/home'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              shape: const StadiumBorder(),
              shadowColor: AppColors.primary.withValues(alpha: 0.4),
              elevation: 6,
            ),
            child: const Text(
              'Explore Deals',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 同一 deal 分组卡片 ─────────────────────────────────────────
// 一行 Deal 信息 + 数量选择器（+/-），底层每张券是独立 cart_item 行
class _DealGroup extends ConsumerWidget {
  final List<CartItemModel> items;

  const _DealGroup({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = items.first;
    final quantity = items.length;
    final subtotal = first.unitPrice * quantity;

    return Dismissible(
      key: ValueKey('deal_group_${first.dealId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      // 滑动删除：移除该 deal 的所有券
      onDismissed: (_) {
        for (final item in items) {
          ref.read(cartProvider.notifier).removeItem(item.id);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 缩略图
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: first.dealImageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: first.dealImageUrl,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => _ImagePlaceholder(),
                      errorWidget: (_, _, _) => _ImagePlaceholder(),
                    )
                  : _ImagePlaceholder(),
            ),
            const SizedBox(width: 12),
            // 中间：标题 + 商家 + 单价
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    first.dealTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    first.merchantName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 单价 + 小计
                  Row(
                    children: [
                      Text(
                        '\$${first.unitPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      if (quantity > 1) ...[
                        const SizedBox(width: 8),
                        Text(
                          '= \$${subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 右侧：数量选择器
            Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.surfaceVariant),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 减少按钮
                      _QtyBtn(
                        icon: quantity > 1 ? Icons.remove : Icons.delete_outline,
                        color: quantity > 1 ? AppColors.textPrimary : Colors.red,
                        onTap: () {
                          // 移除该 deal 组的最后一个 cart_item
                          ref.read(cartProvider.notifier).removeItem(items.last.id);
                        },
                      ),
                      // 数量
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '$quantity',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // 增加按钮
                      _QtyBtn(
                        icon: Icons.add,
                        color: AppColors.primary,
                        onTap: () async {
                          // 从 cart_item 元数据中读取 max_per_account
                          final maxPerAccount = first.maxPerAccount;
                          if (maxPerAccount > 0) {
                            final userId = ref.read(currentUserProvider).value?.id;
                            if (userId != null) {
                              // 查询该用户已购买且未退款的该 deal 数量
                              final res = await Supabase.instance.client
                                  .from('order_items')
                                  .select('id, orders!inner(user_id)')
                                  .eq('deal_id', first.dealId)
                                  .eq('orders.user_id', userId)
                                  .neq('customer_status', 'refund_success');
                              final purchasedCount = (res as List).length;
                              // 购物车中当前 deal 已有数量（含本组）
                              final cartCount = quantity; // quantity = items.length
                              if (purchasedCount + cartCount >= maxPerAccount) {
                                final ctx = context;
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
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
                          // 复制第一个 item 的信息，新增一行 cart_item
                          ref.read(cartProvider.notifier).addDealFromCartItem(first);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 数量按钮 ──────────────────────────────────────────────────
class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QtyBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

// ── 底部结算栏 ────────────────────────────────────────────────
class _CheckoutBar extends ConsumerWidget {
  final double totalPrice;
  final double serviceFee;
  final int itemCount;

  const _CheckoutBar({
    required this.totalPrice,
    required this.serviceFee,
    required this.itemCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grandTotal = totalPrice + serviceFee;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 价格明细 ─────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Subtotal',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '\$${totalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Service fee',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '\$${serviceFee.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: AppColors.surfaceVariant),
            ),
            // ── 合计 + 结算按钮 ───────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        '\$${grandTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                // 结算按钮：跳转到购物车多 deal 结账页，传入当前购物车列表
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final items = ref.read(cartProvider).valueOrNull;
                    if (items == null || items.isEmpty) return;
                    context.push('/checkout-cart', extra: items);
                  },
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: AppColors.primaryGradient,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Center(
                      child: Text(
                        'Checkout ($itemCount)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 图片占位符 ────────────────────────────────────────────────
class _ImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.local_offer, color: AppColors.textHint),
    );
  }
}
