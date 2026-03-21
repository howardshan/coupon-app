import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../cart/data/models/cart_item_model.dart';
import '../../../cart/domain/providers/cart_provider.dart';
import '../../../deals/domain/providers/deals_provider.dart';
import '../../data/repositories/checkout_repository.dart';
import '../../domain/providers/checkout_provider.dart';

// ──────────────────────────────────────────────────────────────────────────────
// CheckoutScreen
//
// 支持两种入口：
//   1. 购物车结账（cartItems 非空）：展示购物车所有 deal，调 checkoutCart
//   2. 单 deal 快速购买（dealId 非空）：保持原有单 deal 模式，调 checkoutSingleDeal
// ──────────────────────────────────────────────────────────────────────────────
class CheckoutScreen extends ConsumerStatefulWidget {
  /// 单 deal 快速购买时传入
  final String? dealId;

  /// 多门店 brand deal 时传入
  final String? purchasedMerchantId;

  /// 购物车结账时传入（非空则进入购物车模式）
  final List<CartItemModel>? cartItems;

  const CheckoutScreen({
    super.key,
    this.dealId,
    this.purchasedMerchantId,
    this.cartItems,
  });

  /// 是否为购物车多 deal 模式
  bool get isCartMode => cartItems != null && cartItems!.isNotEmpty;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  // 单 deal 模式数量
  int _quantity = 1;

  // 优惠码（单 deal 模式）
  final _couponCtrl = TextEditingController();
  bool _isValidatingCoupon = false;
  PromoCodeResult? _promoResult;
  String? _couponError;

  // 支付处理中
  bool _isProcessing = false;

  @override
  void dispose() {
    _couponCtrl.dispose();
    super.dispose();
  }

  // ── 优惠码操作（单 deal 模式专用） ──────────────────────────────

  Future<void> _applyCoupon(double subtotal) async {
    final code = _couponCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _couponError = 'Please enter a coupon code');
      return;
    }
    setState(() {
      _isValidatingCoupon = true;
      _couponError = null;
      _promoResult = null;
    });
    try {
      final repo = ref.read(checkoutRepositoryProvider);
      final result = await repo.validatePromoCode(
        code: code,
        dealId: widget.dealId ?? '',
        subtotal: subtotal,
      );
      if (mounted) {
        setState(() {
          _promoResult = result;
          _isValidatingCoupon = false;
        });
      }
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _couponError = e.message;
          _isValidatingCoupon = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _couponError = 'Failed to validate coupon';
          _isValidatingCoupon = false;
        });
      }
    }
  }

  void _removeCoupon() {
    setState(() {
      _promoResult = null;
      _couponError = null;
      _couponCtrl.clear();
    });
  }

  // ── 支付触发 ─────────────────────────────────────────────────────

  /// 购物车模式支付
  Future<void> _payCart() async {
    final user = await ref.read(currentUserProvider.future);
    final userId = user?.id;
    if (userId == null || userId.isEmpty) {
      _showPaymentFailedDialog('Please sign in to complete your purchase.');
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final repo = ref.read(checkoutRepositoryProvider);
      final items = widget.cartItems!;
      final cartItemIds = items.map((e) => e.id).where((id) => id.isNotEmpty).toList();

      final result = await repo.checkoutCart(
        userId: userId,
        cartItems: items,
        cartItemIds: cartItemIds,
      );

      if (mounted) {
        // 清空内存购物车
        ref.read(cartProvider.notifier).clear();
        context.go('/order-success/${result.orderId}');
      }
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return;
      if (mounted) _showPaymentFailedDialog(e.error.localizedMessage ?? 'Payment was declined');
    } on AppException catch (e) {
      if (mounted) _showPaymentFailedDialog(e.message);
    } catch (e) {
      if (mounted) _showPaymentFailedDialog('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 单 deal 快速购买支付
  Future<void> _paySingle(double total) async {
    final user = await ref.read(currentUserProvider.future);
    final userId = user?.id;
    if (userId == null || userId.isEmpty) {
      _showPaymentFailedDialog('Please sign in to complete your purchase.');
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final repo = ref.read(checkoutRepositoryProvider);

      // 读取选项组快照
      final deal = ref.read(dealDetailProvider(widget.dealId!)).valueOrNull;
      List<Map<String, dynamic>>? selectedOptions;
      if (deal != null && deal.optionGroups.isNotEmpty) {
        final selections = ref.read(dealOptionSelectionsProvider(deal.id));
        selectedOptions = deal.optionGroups.map((group) {
          final selectedIds = selections[group.id] ?? {};
          final selectedItems = group.items
              .where((item) => selectedIds.contains(item.id))
              .map((item) => {
                    'item_id': item.id,
                    'item_name': item.name,
                    'price': item.price,
                  })
              .toList();
          return {
            'group_id': group.id,
            'group_name': group.name,
            'items': selectedItems,
          };
        }).toList();
      }

      final result = await repo.checkoutSingleDeal(
        userId: userId,
        dealId: widget.dealId!,
        unitPrice: total / _quantity,
        quantity: _quantity,
        promoCode: _promoResult?.code,
        purchasedMerchantId: widget.purchasedMerchantId,
        selectedOptions: selectedOptions,
      );

      if (mounted) {
        // 单 deal 快速购买，不经过购物车，无需清理购物车状态
        context.go('/order-success/${result.orderId}');
      }
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return;
      if (mounted) _showPaymentFailedDialog(e.error.localizedMessage ?? 'Payment was declined');
    } on AppException catch (e) {
      if (mounted) _showPaymentFailedDialog(e.message);
    } catch (e) {
      if (mounted) _showPaymentFailedDialog('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 支付失败弹窗
  void _showPaymentFailedDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment Failed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  // ── build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return widget.isCartMode ? _buildCartCheckout() : _buildSingleDealCheckout();
  }

  // ── 购物车多 deal 结账 UI ─────────────────────────────────────────

  Widget _buildCartCheckout() {
    final items = widget.cartItems!;

    // 按 dealId 分组，计算 distinct deal 数量用于服务费
    final distinctDealIds = items.map((e) => e.dealId).toSet();
    final serviceFee = distinctDealIds.length * 0.99;
    final subtotal = items.fold<double>(0, (sum, e) => sum + e.unitPrice);
    final totalAmount = subtotal + serviceFee;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: GestureDetector(
          onTap: () => context.pop(),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surfaceVariant),
            ),
            child: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 20),
          ),
        ),
        title: const Text('Checkout'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 订单摘要标题 ──────────────────────────────────────
            const Text(
              'ORDER SUMMARY',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: AppColors.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),

            // ── 购物车 deal 列表 ──────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceVariant),
              ),
              child: Column(
                children: [
                  ...items.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    return Column(
                      children: [
                        _CartItemRow(item: item),
                        // 非最后一项显示分割线
                        if (idx < items.length - 1)
                          const Divider(height: 1, indent: 16, endIndent: 16),
                      ],
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── 价格明细 ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceVariant),
              ),
              child: Column(
                children: [
                  _PriceRow(
                    'Subtotal (${items.length} item${items.length > 1 ? 's' : ''})',
                    '\$${subtotal.toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 8),
                  _PriceRow(
                    'Service Fee (\$0.99 × ${distinctDealIds.length} deal${distinctDealIds.length > 1 ? 's' : ''})',
                    '\$${serviceFee.toStringAsFixed(2)}',
                  ),
                  const Divider(height: 20),
                  _PriceRow(
                    'Total',
                    '\$${totalAmount.toStringAsFixed(2)}',
                    isBold: true,
                    valueColor: AppColors.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── 服务费退款政策提示 ────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'A \$0.99 service fee applies per deal. This fee is non-refundable for original payment method refunds.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── 支付按钮 ──────────────────────────────────────────
            AppButton(
              label: 'Confirm Payment — \$${totalAmount.toStringAsFixed(2)}',
              isLoading: _isProcessing,
              onPressed: _payCart,
              icon: Icons.lock_outline,
            ),
            const SizedBox(height: 10),
            const Center(
              child: Text(
                'ENCRYPTED SSL CONNECTION',
                style: TextStyle(fontSize: 10, color: AppColors.textHint, letterSpacing: 1.2),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── 单 deal 快速购买 UI ───────────────────────────────────────────

  Widget _buildSingleDealCheckout() {
    final dealAsync = ref.watch(dealDetailProvider(widget.dealId!));

    return dealAsync.when(
      data: (deal) {
        // 限购：取 deal 库存限制（上限 10）
        final maxPerPerson = deal.stockLimit.clamp(1, 10);

        final subtotal = deal.discountPrice * _quantity;
        final discount = _promoResult?.calculatedDiscount ?? 0;
        final taxableAmount = subtotal - discount;
        // Texas 8.25% 销售税
        final tax = taxableAmount * 0.0825;
        // 单 deal 也收取 $0.99 服务费
        const serviceFee = 0.99;
        final total = taxableAmount + tax + serviceFee;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            leading: GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surfaceVariant),
                ),
                child: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 20),
              ),
            ),
            title: const Text('Checkout'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Deal 摘要卡片 ────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.surfaceVariant),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      if (deal.imageUrls.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            deal.imageUrls.first,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.restaurant, color: AppColors.textHint),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              deal.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            if (deal.merchant != null)
                              Text(
                                'Valid at ${deal.merchant!.name}',
                                style: const TextStyle(
                                    color: AppColors.textSecondary, fontSize: 13),
                              ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  '\$${deal.discountPrice.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '\$${deal.originalPrice.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: AppColors.textHint,
                                    fontSize: 13,
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
                const SizedBox(height: 20),

                // ── 数量选择器 ───────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.shopping_basket,
                          color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Quantity',
                            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                        Text(
                          'Maximum $maxPerPerson per person',
                          style:
                              const TextStyle(fontSize: 11, color: AppColors.textHint),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.surfaceVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _QtyButton(
                            icon: Icons.remove,
                            onTap: _quantity > 1
                                ? () {
                                    setState(() => _quantity--);
                                    if (_promoResult != null) {
                                      _applyCoupon(deal.discountPrice * _quantity);
                                    }
                                  }
                                : null,
                            filled: false,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              '$_quantity',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 17),
                            ),
                          ),
                          _QtyButton(
                            icon: Icons.add,
                            onTap: _quantity < maxPerPerson
                                ? () {
                                    setState(() => _quantity++);
                                    if (_promoResult != null) {
                                      _applyCoupon(deal.discountPrice * _quantity);
                                    }
                                  }
                                : null,
                            filled: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── 优惠码 ───────────────────────────────────────
                const Text(
                  'Promo Code',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                if (_promoResult != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: AppColors.success, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _promoResult!.code,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, color: AppColors.success),
                              ),
                              Text(
                                _promoResult!.label,
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: _removeCoupon,
                          child: const Icon(Icons.close,
                              color: AppColors.textSecondary, size: 20),
                        ),
                      ],
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('checkout_coupon_field'),
                          controller: _couponCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            hintText: 'Enter coupon code',
                            errorText: _couponError,
                          ),
                          onChanged: (_) {
                            if (_couponError != null) {
                              setState(() => _couponError = null);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 52,
                        width: 80,
                        child: ElevatedButton(
                          key: const ValueKey('checkout_apply_coupon_btn'),
                          onPressed: _isValidatingCoupon
                              ? null
                              : () => _applyCoupon(subtotal),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.1),
                            foregroundColor: AppColors.primary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isValidatingCoupon
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Apply',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),

                // ── 价格明细 ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.surfaceVariant),
                  ),
                  child: Column(
                    children: [
                      _PriceRow('Subtotal (×$_quantity)',
                          '\$${subtotal.toStringAsFixed(2)}'),
                      if (discount > 0) ...[
                        const SizedBox(height: 8),
                        _PriceRow(
                          'Coupon (${_promoResult!.label})',
                          '-\$${discount.toStringAsFixed(2)}',
                          valueColor: AppColors.success,
                        ),
                      ],
                      const SizedBox(height: 8),
                      _PriceRow('Tax (8.25%)', '\$${tax.toStringAsFixed(2)}'),
                      const SizedBox(height: 8),
                      _PriceRow('Service Fee', '\$0.99'),
                      const Divider(height: 20),
                      _PriceRow(
                        'Total',
                        '\$${total.toStringAsFixed(2)}',
                        isBold: true,
                        valueColor: AppColors.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── 服务费退款政策提示 ────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: AppColors.warning),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'A \$0.99 service fee applies per deal. This fee is non-refundable for original payment method refunds.',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // ── 支付按钮 ─────────────────────────────────────
                AppButton(
                  label: 'Confirm Payment — \$${total.toStringAsFixed(2)}',
                  isLoading: _isProcessing,
                  onPressed: () => _paySingle(total),
                  icon: Icons.lock_outline,
                ),
                const SizedBox(height: 10),
                const Center(
                  child: Text(
                    'ENCRYPTED SSL CONNECTION',
                    style: TextStyle(
                        fontSize: 10, color: AppColors.textHint, letterSpacing: 1.2),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Unable to load deal. Please try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 购物车 deal 行（购物车模式专用） ─────────────────────────────────────────
class _CartItemRow extends StatelessWidget {
  final CartItemModel item;

  const _CartItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // 缩略图
          if (item.dealImageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                item.dealImageUrl,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 56,
                  height: 56,
                  color: AppColors.surfaceVariant,
                  child: const Icon(Icons.local_offer, color: AppColors.textHint, size: 20),
                ),
              ),
            )
          else
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.local_offer, color: AppColors.textHint, size: 20),
            ),
          const SizedBox(width: 12),
          // 标题 + 商家名
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.dealTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.merchantName,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 单价
          Text(
            '\$${item.unitPrice.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 数量 +/- 小按钮（单 deal 模式） ──────────────────────────────────────────
class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  const _QtyButton({required this.icon, required this.onTap, required this.filled});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: filled && onTap != null ? AppColors.primary : AppColors.surfaceVariant,
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            size: 18,
            color: filled && onTap != null ? Colors.white : AppColors.textSecondary),
      ),
    );
  }
}

// ── 价格明细行 ────────────────────────────────────────────────────────────────
class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const _PriceRow(this.label, this.value, {this.isBold = false, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 20 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: valueColor ?? (isBold ? AppColors.primary : AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}
