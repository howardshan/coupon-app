import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
import 'dart:io' show Platform;

// 支付方式选项（按平台过滤）
final _paymentMethods = [
  if (Platform.isIOS)
    {'id': 'apple', 'name': 'Apple Pay', 'sub': 'Secure 1-click payment', 'icon': Icons.phone_iphone},
  if (Platform.isAndroid)
    {'id': 'google', 'name': 'Google Pay', 'sub': 'Fast checkout', 'icon': Icons.g_mobiledata},
  {'id': 'card', 'name': 'Credit Card', 'sub': 'Visa / Mastercard / Amex', 'icon': Icons.credit_card},
];

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
  // 支付方式（默认：iOS=Apple Pay, Android=Google Pay）
  String _selectedPayment = Platform.isIOS ? 'apple' : 'google';

  // 信用卡输入是否完整（CardField 回调）
  bool _cardComplete = false;

  // 单 deal 模式数量
  int _quantity = 1;

  // 优惠码（单 deal 模式）
  final _couponCtrl = TextEditingController();
  bool _isValidatingCoupon = false;
  PromoCodeResult? _promoResult;
  String? _couponError;

  // 支付处理中
  bool _isProcessing = false;

  // 账单地址
  final _addressLine1Ctrl = TextEditingController();
  final _addressLine2Ctrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();
  String _country = 'US';
  bool _addressLoaded = false;

  @override
  void dispose() {
    _couponCtrl.dispose();
    _addressLine1Ctrl.dispose();
    _addressLine2Ctrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _postalCodeCtrl.dispose();
    super.dispose();
  }

  // ── 账单地址加载 ─────────────────────────────────────────────────

  /// 从 DB 加载已保存的 billing address（只执行一次）
  Future<void> _loadSavedAddress() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;
    final data = await Supabase.instance.client
        .from('users')
        .select('billing_address_line1, billing_address_line2, billing_city, billing_state, billing_postal_code, billing_country')
        .eq('id', user.id)
        .single();
    if (mounted) {
      setState(() {
        _addressLine1Ctrl.text = data['billing_address_line1'] as String? ?? '';
        _addressLine2Ctrl.text = data['billing_address_line2'] as String? ?? '';
        _cityCtrl.text = data['billing_city'] as String? ?? '';
        _stateCtrl.text = data['billing_state'] as String? ?? '';
        _postalCodeCtrl.text = data['billing_postal_code'] as String? ?? '';
        _country = data['billing_country'] as String? ?? 'US';
      });
    }
  }

  /// 信用卡模式下按钮可用条件：卡片完整 + 必填地址已填
  bool get _canPayByCard =>
      _cardComplete &&
      _addressLine1Ctrl.text.trim().isNotEmpty &&
      _cityCtrl.text.trim().isNotEmpty &&
      _stateCtrl.text.trim().isNotEmpty &&
      _postalCodeCtrl.text.trim().isNotEmpty;

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

      // 构建 billing details（信用卡支付时携带账单地址）
      BillingDetails? billingDetails;
      if (_selectedPayment == 'card' && _addressLine1Ctrl.text.trim().isNotEmpty) {
        billingDetails = BillingDetails(
          address: Address(
            line1: _addressLine1Ctrl.text.trim(),
            line2: _addressLine2Ctrl.text.trim(),
            city: _cityCtrl.text.trim(),
            state: _stateCtrl.text.trim(),
            postalCode: _postalCodeCtrl.text.trim(),
            country: _country,
          ),
        );
      }

      final result = await repo.checkoutCart(
        userId: userId,
        cartItems: items,
        cartItemIds: cartItemIds,
        paymentMethod: _selectedPayment,
        billingDetails: billingDetails,
      );

      // 支付成功后异步保存 billing address（fire-and-forget）
      if (_selectedPayment == 'card' && _addressLine1Ctrl.text.trim().isNotEmpty) {
        Supabase.instance.client.from('users').update({
          'billing_address_line1': _addressLine1Ctrl.text.trim(),
          'billing_address_line2': _addressLine2Ctrl.text.trim(),
          'billing_city': _cityCtrl.text.trim(),
          'billing_state': _stateCtrl.text.trim(),
          'billing_postal_code': _postalCodeCtrl.text.trim(),
          'billing_country': _country,
        }).eq('id', userId).then((_) {}).catchError((e) {
          debugPrint('保存 billing address 失败: $e');
        });
      }

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

      // 构建 billing details（信用卡支付时携带账单地址）
      BillingDetails? billingDetails;
      if (_selectedPayment == 'card' && _addressLine1Ctrl.text.trim().isNotEmpty) {
        billingDetails = BillingDetails(
          address: Address(
            line1: _addressLine1Ctrl.text.trim(),
            line2: _addressLine2Ctrl.text.trim(),
            city: _cityCtrl.text.trim(),
            state: _stateCtrl.text.trim(),
            postalCode: _postalCodeCtrl.text.trim(),
            country: _country,
          ),
        );
      }

      final result = await repo.checkoutSingleDeal(
        userId: userId,
        dealId: widget.dealId!,
        unitPrice: deal!.discountPrice,
        quantity: _quantity,
        promoCode: _promoResult?.code,
        purchasedMerchantId: widget.purchasedMerchantId,
        selectedOptions: selectedOptions,
        paymentMethod: _selectedPayment,
        billingDetails: billingDetails,
      );

      // 支付成功后异步保存 billing address（fire-and-forget）
      if (_selectedPayment == 'card' && _addressLine1Ctrl.text.trim().isNotEmpty) {
        Supabase.instance.client.from('users').update({
          'billing_address_line1': _addressLine1Ctrl.text.trim(),
          'billing_address_line2': _addressLine2Ctrl.text.trim(),
          'billing_city': _cityCtrl.text.trim(),
          'billing_state': _stateCtrl.text.trim(),
          'billing_postal_code': _postalCodeCtrl.text.trim(),
          'billing_country': _country,
        }).eq('id', userId).then((_) {}).catchError((e) {
          debugPrint('保存 billing address 失败: $e');
        });
      }

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
    // 首次渲染时加载已保存的 billing address
    if (!_addressLoaded) {
      _addressLoaded = true;
      _loadSavedAddress();
    }
    return widget.isCartMode ? _buildCartCheckout() : _buildSingleDealCheckout();
  }

  // ── 购物车多 deal 结账 UI ─────────────────────────────────────────

  Widget _buildCartCheckout() {
    final items = widget.cartItems!;

    // 每张券收 $0.99 service fee
    final serviceFee = items.length * 0.99;
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

            // ── 支付方式 ──────────────────────────────────────────
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
                child: _PaymentMethodCard(
                  method: method,
                  isSelected: isSelected,
                ),
              );
            })),

            // ── 信用卡输入框（仅选择 Credit Card 时显示） ──────────
            if (_selectedPayment == 'card') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.surfaceVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Card Information',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 12),
                    CardField(
                      onCardChanged: (card) {
                        setState(() => _cardComplete = card?.complete ?? false);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildBillingAddressForm(),
            ],
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
                    'Service Fee (\$0.99 × ${items.length} voucher${items.length > 1 ? 's' : ''})',
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
                      'A \$0.99 service fee applies per voucher. This fee is non-refundable for original payment method refunds.',
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
              // 信用卡模式需要卡片完整且必填地址已填
              onPressed: (_selectedPayment == 'card' && !_canPayByCard)
                  ? null
                  : _payCart,
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
        // 综合 stock_limit 和 max_per_account 取更严格的上限
        final maxByStock = deal.stockLimit <= 0 ? 99 : deal.stockLimit.clamp(1, 99);
        final maxByAccount = deal.maxPerAccount <= 0 ? 99 : deal.maxPerAccount.clamp(1, 99);
        final maxPerPerson = (maxByStock < maxByAccount ? maxByStock : maxByAccount).clamp(1, 99);

        final subtotal = deal.discountPrice * _quantity;
        final discount = _promoResult?.calculatedDiscount ?? 0;
        final taxableAmount = subtotal - discount;
        // Texas 8.25% 销售税
        final tax = taxableAmount * 0.0825;
        // 每张券收取 $0.99 服务费
        final serviceFee = 0.99 * _quantity;
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
                          deal.maxPerAccount > 0
                              ? 'Limit ${deal.maxPerAccount} per account'
                              : (deal.stockLimit <= 0
                                  ? 'No purchase limit'
                                  : 'Maximum $maxPerPerson available'),
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

                // ── 支付方式 ─────────────────────────────────────
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
                    child: _PaymentMethodCard(
                      method: method,
                      isSelected: isSelected,
                    ),
                  );
                })),

                // ── 信用卡输入框（仅选择 Credit Card 时显示） ──────
                if (_selectedPayment == 'card') ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.surfaceVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Card Information',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 12),
                        CardField(
                          onCardChanged: (card) {
                            setState(() => _cardComplete = card?.complete ?? false);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildBillingAddressForm(),
                ],
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
                          'A \$0.99 service fee applies per voucher. This fee is non-refundable for original payment method refunds.',
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
                  // 信用卡模式需要卡片完整且必填地址已填
                  onPressed: (_selectedPayment == 'card' && !_canPayByCard)
                      ? null
                      : () => _paySingle(total),
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

  // ── 账单地址表单（Credit Card 模式专用） ──────────────────────────

  Widget _buildBillingAddressForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Billing Address',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 12),
          // 地址第一行
          TextField(
            controller: _addressLine1Ctrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Address Line 1',
              hintText: '123 Main St',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          // 地址第二行（可选）
          TextField(
            controller: _addressLine2Ctrl,
            decoration: const InputDecoration(
              labelText: 'Address Line 2 (optional)',
              hintText: 'Apt, Suite, etc.',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          // 城市 + 州
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cityCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'City',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _stateCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'State',
                    hintText: 'TX',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 邮编 + 国家
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _postalCodeCtrl,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'ZIP Code',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _country,
                  decoration: const InputDecoration(
                    labelText: 'Country',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'US', child: Text('US')),
                    DropdownMenuItem(value: 'CA', child: Text('Canada')),
                    DropdownMenuItem(value: 'CN', child: Text('China')),
                  ],
                  onChanged: (v) => setState(() => _country = v ?? 'US'),
                ),
              ),
            ],
          ),
        ],
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

// ── 支付方式选择卡片 ──────────────────────────────────────────
class _PaymentMethodCard extends StatelessWidget {
  final Map<String, Object> method;
  final bool isSelected;

  const _PaymentMethodCard({required this.method, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? AppColors.primary : Colors.transparent,
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
              color: method['id'] == 'apple' ? Colors.white : AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(method['name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(method['sub'] as String,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.textHint,
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
    );
  }
}
