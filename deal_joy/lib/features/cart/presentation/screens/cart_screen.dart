// 购物车页面 — 展示已添加的 deal，支持数量调整和移除

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/cart_item_model.dart';
import '../../domain/providers/cart_provider.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final totalPrice = ref.watch(cartTotalPriceProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
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
                  if (items.isNotEmpty)
                    TextButton(
                      onPressed: () => ref.read(cartProvider.notifier).clear(),
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

            // 列表 / 空状态
            Expanded(
              child: items.isEmpty
                  ? _EmptyCart()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) =>
                          _CartItemCard(item: items[index]),
                    ),
            ),

            // 底部结算栏
            if (items.isNotEmpty)
              Container(
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
                  child: Row(
                    children: [
                      // 合计
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
                              '\$${totalPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 结算按钮：跳转到第一个商品的结账页（当前结账为单 deal 流程）
                      GestureDetector(
                        onTap: () {
                          final list = ref.read(cartProvider);
                          if (list.isEmpty) return;
                          context.push('/checkout/${list.first.dealId}');
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
                              'Checkout (${items.length})',
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
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── 空购物车 ──────────────────────────────────────────────────
class _EmptyCart extends StatelessWidget {
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
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 购物车单项卡片 ────────────────────────────────────────────
class _CartItemCard extends ConsumerWidget {
  final CartItemModel item;

  const _CartItemCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(12),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 缩略图
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: item.dealImageUrl != null
                ? CachedNetworkImage(
                    imageUrl: item.dealImageUrl!,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      width: 80,
                      height: 80,
                      color: AppColors.surfaceVariant,
                    ),
                    errorWidget: (_, _, _) => Container(
                      width: 80,
                      height: 80,
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.image_not_supported,
                          color: AppColors.textHint),
                    ),
                  )
                : Container(
                    width: 80,
                    height: 80,
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.local_offer,
                        color: AppColors.textHint),
                  ),
          ),
          const SizedBox(width: 12),
          // 信息区
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题 + 删除
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.dealTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () =>
                          ref.read(cartProvider.notifier).remove(item.dealId),
                      child: const Icon(Icons.close,
                          size: 18, color: AppColors.textHint),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 商家名
                Text(
                  item.merchantName,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                // 价格 + 数量调节
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '\$${item.discountPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    // 数量 +/- 控件
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.surfaceVariant),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _QtyButton(
                            icon: Icons.remove,
                            onTap: () => ref
                                .read(cartProvider.notifier)
                                .updateQuantity(
                                    item.dealId, item.quantity - 1),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              '${item.quantity}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          _QtyButton(
                            icon: Icons.add,
                            onTap: () => ref
                                .read(cartProvider.notifier)
                                .updateQuantity(
                                    item.dealId, item.quantity + 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 数量加减小按钮 ────────────────────────────────────────────
class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: AppColors.textSecondary),
      ),
    );
  }
}
