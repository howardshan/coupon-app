import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../deals/domain/providers/deals_provider.dart';
import '../../domain/providers/checkout_provider.dart';

// Payment method options (mirrors web app)
const _paymentMethods = [
  {'id': 'apple', 'name': 'Apple Pay', 'sub': 'Secure 1-click payment', 'icon': Icons.phone_iphone},
  {'id': 'google', 'name': 'Google Pay', 'sub': 'Fast checkout', 'icon': Icons.g_mobiledata},
  {'id': 'card', 'name': 'Credit Card', 'sub': 'Visa •••• 4242', 'icon': Icons.credit_card},
];

class CheckoutScreen extends ConsumerStatefulWidget {
  final String dealId;

  const CheckoutScreen({super.key, required this.dealId});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  int _quantity = 1;
  String _selectedPayment = 'apple';
  final _couponCtrl = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _couponCtrl.dispose();
    super.dispose();
  }

  Future<void> _pay(double total) async {
    setState(() => _isProcessing = true);
    try {
      final userId = ref.read(currentUserProvider).valueOrNull?.id ?? '';
      final repo = ref.read(checkoutRepositoryProvider);

      final result = await repo.checkout(
        userId: userId,
        dealId: widget.dealId,
        quantity: _quantity,
        total: total,
      );

      if (mounted) context.go('/order-success/${result.orderId}');
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return;
      _showError('Payment failed: ${e.error.localizedMessage}');
    } on AppException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Payment failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dealAsync = ref.watch(dealDetailProvider(widget.dealId));

    return dealAsync.when(
      data: (deal) {
        final subtotal = deal.discountPrice * _quantity;
        final discount = subtotal * 0.1; // 10% promo placeholder
        final tax = subtotal * 0.0825;   // Texas 8.25% tax
        final total = subtotal - discount + tax;

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
                      // Deal image
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
                            Text(
                              '\$${deal.discountPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18),
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
                    const Text('Quantity',
                        style: TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 15)),
                    const Spacer(),
                    // +/- control
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
                                ? () => setState(() => _quantity--)
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
                            onTap: _quantity < 10
                                ? () => setState(() => _quantity++)
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
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _couponCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Enter coupon code',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.1),
                          foregroundColor: AppColors.primary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Apply',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
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
                    onTap: () =>
                        setState(() => _selectedPayment = method['id'] as String),
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
                          // Radio dot
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
                      _PriceRow('Subtotal (×$_quantity)',
                          '\$${subtotal.toStringAsFixed(2)}'),
                      const SizedBox(height: 8),
                      _PriceRow(
                        'Discount (10%)',
                        '-\$${discount.toStringAsFixed(2)}',
                        valueColor: AppColors.success,
                      ),
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
                  label: 'Confirm Payment — \$${total.toStringAsFixed(2)}',
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
          appBar: AppBar(), body: Center(child: Text('Error: $e'))),
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
