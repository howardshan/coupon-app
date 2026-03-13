import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../deals/domain/providers/deals_provider.dart';
import '../../data/repositories/checkout_repository.dart';
import '../../domain/providers/checkout_provider.dart';

// 支付方式选项
const _paymentMethods = [
  {'id': 'apple', 'name': 'Apple Pay', 'sub': 'Secure 1-click payment', 'icon': Icons.phone_iphone},
  {'id': 'google', 'name': 'Google Pay', 'sub': 'Fast checkout', 'icon': Icons.g_mobiledata},
  {'id': 'card', 'name': 'Credit Card', 'sub': 'Visa / Mastercard / Amex', 'icon': Icons.credit_card},
];

class CheckoutScreen extends ConsumerStatefulWidget {
  final String dealId;
  final String? purchasedMerchantId; // brand deal 用户选择的门店 ID

  const CheckoutScreen({super.key, required this.dealId, this.purchasedMerchantId});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  int _quantity = 1;
  String _selectedPayment = 'apple';
  final _couponCtrl = TextEditingController();
  bool _isProcessing = false;

  // 优惠码状态
  bool _isValidatingCoupon = false;
  PromoCodeResult? _promoResult;
  String? _couponError;

  @override
  void dispose() {
    _couponCtrl.dispose();
    super.dispose();
  }

  /// 验证优惠码
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
        dealId: widget.dealId,
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

  /// 移除已应用的优惠码
  void _removeCoupon() {
    setState(() {
      _promoResult = null;
      _couponError = null;
      _couponCtrl.clear();
    });
  }

  /// 发起支付
  Future<void> _pay(double total) async {
    // 等待 currentUserProvider 完成（重启后 session 恢复是异步的，避免首次点击误判为未登录）
    final user = await ref.read(currentUserProvider.future);
    final userId = user?.id;
    if (userId == null || userId.isEmpty) {
      _showPaymentFailedDialog('Please sign in to complete your purchase.');
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final repo = ref.read(checkoutRepositoryProvider);

      final result = await repo.checkout(
        userId: userId,
        dealId: widget.dealId,
        quantity: _quantity,
        total: total,
        promoCode: _promoResult?.code, // P0 fix: 传递优惠码给服务端验证
        purchasedMerchantId: widget.purchasedMerchantId,
      );

      if (mounted) context.go('/order-success/${result.orderId}');
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

  /// 支付失败弹窗 — 提供重试和换支付方式选项
  void _showPaymentFailedDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment Failed'),
        content: Text(message),
        actions: [
          TextButton(
            key: const ValueKey('checkout_change_payment_btn'),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Change Payment Method'),
          ),
          ElevatedButton(
            key: const ValueKey('checkout_retry_btn'),
            onPressed: () {
              Navigator.pop(ctx);
              // 重新计算 total 后重试
              final deal = ref.read(dealDetailProvider(widget.dealId)).valueOrNull;
              if (deal != null) {
                final subtotal = deal.discountPrice * _quantity;
                final discount = _promoResult?.calculatedDiscount ?? 0;
                final tax = (subtotal - discount) * 0.0825;
                final total = subtotal - discount + tax;
                _pay(total);
              }
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dealAsync = ref.watch(dealDetailProvider(widget.dealId));

    return dealAsync.when(
      data: (deal) {
        // 限购逻辑：使用 deal 的库存限制（上限 10）
        final maxPerPerson = deal.stockLimit.clamp(1, 10);

        final subtotal = deal.discountPrice * _quantity;
        final discount = _promoResult?.calculatedDiscount ?? 0;
        final taxableAmount = subtotal - discount;
        final tax = taxableAmount * 0.0825; // Texas 8.25% sales tax
        final total = taxableAmount + tax;

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
                child: const Icon(Icons.arrow_back,
                    color: AppColors.textPrimary, size: 20),
              ),
            ),
            title: const Text('Checkout'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Deal summary card ──────────────────────
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
                          child: const Icon(Icons.restaurant,
                              color: AppColors.textHint),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              deal.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            if (deal.merchant != null)
                              Text(
                                'Valid at ${deal.merchant!.name}',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13),
                              ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  '\$${deal.discountPrice.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '\$${deal.originalPrice.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      color: AppColors.textHint,
                                      fontSize: 13,
                                      decoration: TextDecoration.lineThrough),
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

                // ── Quantity selector ──────────────────────
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
                            style: TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 15)),
                        // 显示限购信息
                        Text(
                          'Maximum $maxPerPerson per person',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textHint),
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
                                    // P1 fix: 在 setState 之外发起异步优惠码重算，
                                    // 避免在 setState 回调中调用异步方法触发嵌套 setState
                                    if (_promoResult != null) {
                                      _applyCoupon(
                                          deal.discountPrice * _quantity);
                                    }
                                  }
                                : null,
                            filled: false,
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
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
                                    // P1 fix: 同上，避免嵌套 setState
                                    if (_promoResult != null) {
                                      _applyCoupon(
                                          deal.discountPrice * _quantity);
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

                // ── Promo code ─────────────────────────────
                const Text('Promo Code',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.8)),
                const SizedBox(height: 8),
                if (_promoResult != null)
                  // 已应用优惠码
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.success, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _promoResult!.code,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.success),
                              ),
                              Text(
                                _promoResult!.label,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary),
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
                  // 优惠码输入框
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                                // 输入变化时清除错误
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
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Text('Apply',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 20),

                // ── Payment method ─────────────────────────
                const Text('Payment Method',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.8)),
                const SizedBox(height: 10),
                ...(_paymentMethods.map((method) {
                  final isSelected = _selectedPayment == method['id'];
                  return GestureDetector(
                    onTap: () => setState(
                        () => _selectedPayment = method['id'] as String),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: method['id'] == 'apple'
                                  ? AppColors.textPrimary
                                  : AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              method['icon'] as IconData,
                              color: method['id'] == 'apple'
                                  ? Colors.white
                                  : AppColors.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(method['name'] as String,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                Text(method['sub'] as String,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textHint,
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? Center(
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: const BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  );
                })),
                const SizedBox(height: 12),

                // ── Price breakdown ────────────────────────
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.surfaceVariant),
                  ),
                  child: Column(
                    children: [
                      _PriceRow('Subtotal (\u00d7$_quantity)',
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
                      _PriceRow(
                          'Tax (8.25%)', '\$${tax.toStringAsFixed(2)}'),
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
                const SizedBox(height: 32),

                AppButton(
                  label:
                      'Confirm Payment \u2014 \$${total.toStringAsFixed(2)}',
                  isLoading: _isProcessing,
                  onPressed: () => _pay(total),
                  icon: Icons.lock_outline,
                ),
                const SizedBox(height: 10),
                const Center(
                  child: Text(
                    'ENCRYPTED SSL CONNECTION',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textHint,
                        letterSpacing: 1.2),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Unable to load deal. Please try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  const _QtyButton(
      {required this.icon, required this.onTap, required this.filled});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: filled && onTap != null
              ? AppColors.primary
              : AppColors.surfaceVariant,
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            size: 18,
            color: filled && onTap != null
                ? Colors.white
                : AppColors.textSecondary),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const _PriceRow(this.label, this.value,
      {this.isBold = false, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
            )),
        Text(value,
            style: TextStyle(
              fontSize: isBold ? 20 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: valueColor ??
                  (isBold ? AppColors.primary : AppColors.textPrimary),
            )),
      ],
    );
  }
}
