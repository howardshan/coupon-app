// 购物车页面 — V3 DB 持久化版本
// 每张券独立一行，同一 deal 的多张券视觉分组展示，底部显示 service fee

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
// 显示 deal 标题 + 商家名作为组头，每张券独立一行
class _DealGroup extends ConsumerWidget {
  final List<CartItemModel> items;

  const _DealGroup({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = items.first;
    final hasMultiple = items.length > 1;

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 组头：图片 + deal 标题 + 商家名 ──────────────
          Padding(
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
                // 文字信息
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
                      const SizedBox(height: 6),
                      // 单价
                      Text(
                        '\$${first.unitPrice.toStringAsFixed(2)} / voucher',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── 分割线（多张券时显示）────────────────────────
          if (hasMultiple)
            const Divider(height: 1, color: AppColors.surfaceVariant),

          // ── 每张券独立行 ─────────────────────────────────
          ...items.map(
            (item) => _VoucherRow(
              item: item,
              isLast: item == items.last,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 单张券行 ──────────────────────────────────────────────────
class _VoucherRow extends ConsumerWidget {
  final CartItemModel item;
  final bool isLast;

  const _VoucherRow({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // 券标识图标
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.confirmation_number_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              // 券说明文字
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '1 Voucher',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    // 若有选项快照，展示选项摘要
                    if (item.selectedOptions != null &&
                        item.selectedOptions!.isNotEmpty)
                      Text(
                        _summarizeOptions(item.selectedOptions!),
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
              // 单价
              Text(
                '\$${item.unitPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              // 移除按钮
              GestureDetector(
                onTap: () =>
                    ref.read(cartProvider.notifier).removeItem(item.id),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
        // 分割线（非最后一行时显示）
        if (!isLast)
          const Divider(
            height: 1,
            indent: 12,
            endIndent: 12,
            color: AppColors.surfaceVariant,
          ),
      ],
    );
  }

  /// 将 selectedOptions Map 转为可读摘要字符串
  String _summarizeOptions(Map<String, dynamic> options) {
    return options.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');
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
