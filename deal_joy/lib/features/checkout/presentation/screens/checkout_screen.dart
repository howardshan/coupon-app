import 'dart:math' show min;
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
import '../../data/models/billing_address_model.dart';
import '../../data/repositories/checkout_repository.dart';
import '../../domain/providers/checkout_provider.dart';
import '../../domain/providers/billing_address_provider.dart';
import '../../../profile/domain/providers/store_credit_provider.dart';
import '../../domain/providers/tax_rate_provider.dart';

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

  // Store Credit 余额与使用开关
  double _storeCreditBalance = 0.0;
  bool _useStoreCredit = false;

  // 当前渲染的 items（Buy Now 模式下由 deal 转换生成）
  List<CartItemModel>? _currentItems;
  bool _storeCreditLoaded = false;

  // 支付处理中
  bool _isProcessing = false;

  // 账单地址 — 多地址管理
  List<BillingAddressModel> _savedAddresses = [];
  String? _selectedAddressId;       // 选中的已保存地址 ID，null 表示新增模式
  bool _isAddingNewAddress = false; // 是否显示新增地址表单
  bool _saveAsDefault = false;      // 勾选：Save as default billing address
  bool _saveForFuture = false;      // 勾选：Save for future use
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

  /// 从 store_credits 表加载当前用户余额（只执行一次）
  Future<void> _loadStoreCredit() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;
    final res = await Supabase.instance.client
        .from('store_credits')
        .select('amount')
        .eq('user_id', user.id)
        .maybeSingle();
    final balance = (res?['amount'] as num?)?.toDouble() ?? 0.0;
    if (mounted) {
      setState(() => _storeCreditBalance = balance);
    }
  }

  /// 从 billing_addresses 表加载已保存地址（只执行一次）
  Future<void> _loadSavedAddress() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;
    final repo = ref.read(billingAddressRepositoryProvider);
    // 自动迁移 users 表中的旧地址
    await repo.migrateFromUsersTable(user.id);
    final addresses = await repo.fetchAll(user.id);
    if (mounted) {
      setState(() {
        _savedAddresses = addresses;
        if (addresses.isNotEmpty) {
          // 默认选中 default 地址或第一个
          final defaultAddr = addresses.firstWhere(
            (a) => a.isDefault,
            orElse: () => addresses.first,
          );
          _selectedAddressId = defaultAddr.id;
          _fillFormFromAddress(defaultAddr);
          _isAddingNewAddress = false;
        } else {
          // 没有已保存地址，直接显示新增表单
          _isAddingNewAddress = true;
          _saveForFuture = true;
          _saveAsDefault = true;
        }
      });
    }
  }

  /// 用已保存地址填充表单控制器
  void _fillFormFromAddress(BillingAddressModel addr) {
    _addressLine1Ctrl.text = addr.addressLine1;
    _addressLine2Ctrl.text = addr.addressLine2;
    _cityCtrl.text = addr.city;
    _stateCtrl.text = addr.state;
    _postalCodeCtrl.text = addr.postalCode;
    _country = addr.country;
  }

  /// 清空表单
  void _clearAddressForm() {
    _addressLine1Ctrl.clear();
    _addressLine2Ctrl.clear();
    _cityCtrl.clear();
    _stateCtrl.clear();
    _postalCodeCtrl.clear();
    _country = 'US';
  }

  /// 信用卡模式下按钮可用条件：卡片完整 + 有选中地址或新增表单已填
  bool get _canPayByCard {
    if (!_cardComplete) return false;
    // 选中了已有地址
    if (_selectedAddressId != null && !_isAddingNewAddress) return true;
    // 新增模式需要必填字段
    return _addressLine1Ctrl.text.trim().isNotEmpty &&
        _cityCtrl.text.trim().isNotEmpty &&
        _stateCtrl.text.trim().isNotEmpty &&
        _postalCodeCtrl.text.trim().isNotEmpty;
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
      final items = _currentItems ?? widget.cartItems!;
      final cartItemIds = items.map((e) => e.id).where((id) => id.isNotEmpty).toList();

      // 计算 Store Credit 实际抵扣金额
      final serviceFee = items.length * 0.99;
      final subtotal = items.fold<double>(0, (sum, e) => sum + e.unitPrice);
      final totalAmount = subtotal + serviceFee;
      final creditUsed = _useStoreCredit ? min(_storeCreditBalance, totalAmount) : 0.0;

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
        storeCreditUsed: creditUsed,
      );

      // 支付成功后异步保存 billing address（fire-and-forget）
      _saveBillingAddressAfterPayment(userId);

      if (mounted) {
        // 清空购物车 + 刷新 Store Credit 余额
        ref.read(cartProvider.notifier).clear();
        ref.invalidate(storeCreditBalanceProvider);
        ref.invalidate(storeCreditTransactionsProvider);
        context.go('/order-success/${result.orderId}');
      }
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return;
      if (mounted) _showPaymentFailedDialog(e.error.localizedMessage ?? 'Payment was declined');
    } on AppException catch (e) {
      if (mounted) _showPaymentFailedDialog(e.message);
    } catch (e) {
      if (mounted) _showPaymentFailedDialog('Error: $e');
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
      _saveBillingAddressAfterPayment(userId);

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
      if (mounted) _showPaymentFailedDialog('Error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 支付成功后保存账单地址（fire-and-forget）
  void _saveBillingAddressAfterPayment(String userId) {
    if (_selectedPayment != 'card') return;
    if (_addressLine1Ctrl.text.trim().isEmpty) return;

    // 始终同步到 users 表（保持向后兼容）
    Supabase.instance.client.from('users').update({
      'billing_address_line1': _addressLine1Ctrl.text.trim(),
      'billing_address_line2': _addressLine2Ctrl.text.trim(),
      'billing_city': _cityCtrl.text.trim(),
      'billing_state': _stateCtrl.text.trim(),
      'billing_postal_code': _postalCodeCtrl.text.trim(),
      'billing_country': _country,
    }).eq('id', userId).then((_) {}).catchError((e) {
      debugPrint('保存 billing address 到 users 表失败: $e');
    });

    // 如果是新增地址且勾选了「Save for future use」，保存到 billing_addresses 表
    if (_isAddingNewAddress && _saveForFuture) {
      final repo = ref.read(billingAddressRepositoryProvider);
      repo.create(
        userId: userId,
        label: _saveAsDefault ? 'Default' : '',
        addressLine1: _addressLine1Ctrl.text.trim(),
        addressLine2: _addressLine2Ctrl.text.trim(),
        city: _cityCtrl.text.trim(),
        state: _stateCtrl.text.trim(),
        postalCode: _postalCodeCtrl.text.trim(),
        country: _country,
        isDefault: _saveAsDefault,
      ).then((_) {
        // 刷新已保存地址列表缓存
        ref.invalidate(savedBillingAddressesProvider);
      }).catchError((e) {
        debugPrint('保存新 billing address 失败: $e');
      });
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
    // 首次渲染时加载 Store Credit 余额
    if (!_storeCreditLoaded) {
      _storeCreditLoaded = true;
      _loadStoreCredit();
    }
    // 统一入口：Buy Now 也走 cart checkout（把单 deal 转成 cart items）
    if (widget.isCartMode) {
      return _buildCartCheckout();
    }
    // Buy Now 模式：用 dealDetailProvider 加载后转为 cart items
    final dealAsync = ref.watch(dealDetailProvider(widget.dealId!));
    return dealAsync.when(
      data: (deal) {
        // 将 deal 转为 cart item 格式
        final cartItems = List.generate(_quantity, (_) => CartItemModel(
          id: '',
          userId: '',
          dealId: deal.id,
          unitPrice: deal.discountPrice,
          purchasedMerchantId: widget.purchasedMerchantId,
          dealTitle: deal.title,
          dealImageUrl: deal.imageUrls.isNotEmpty ? deal.imageUrls.first : '',
          originalPrice: deal.originalPrice,
          merchantName: deal.merchant?.name ?? '',
          merchantId: deal.merchant?.id,
          maxPerAccount: deal.maxPerAccount,
          createdAt: DateTime.now(),
        ));
        return _buildCartCheckout(overrideItems: cartItems);
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: Center(child: Text('Failed to load deal: $e')),
      ),
    );
  }

  // ── 购物车多 deal 结账 UI ─────────────────────────────────────────

  Widget _buildCartCheckout({List<CartItemModel>? overrideItems}) {
    final items = overrideItems ?? widget.cartItems!;
    // 保存当前 items 供 _payCart 使用（Buy Now 模式下 widget.cartItems 为 null）
    _currentItems = items;

    // 动态查询购物车第一个 item 对应 merchant 的税率
    final cartMerchantId = items.first.purchasedMerchantId ?? items.first.merchantId ?? '';
    final cartTaxRateAsync = ref.watch(taxRateByMerchantProvider(cartMerchantId));
    final cartTaxRate = cartTaxRateAsync.valueOrNull ?? 0.0;

    // 每张券收 $0.99 service fee
    final serviceFee = items.length * 0.99;
    final subtotal = items.fold<double>(0, (sum, e) => sum + e.unitPrice);
    final cartTax = (subtotal * cartTaxRate * 100).roundToDouble() / 100;
    final totalAmount = subtotal + serviceFee + cartTax;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: GestureDetector(
          behavior: HitTestBehavior.opaque,
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
                behavior: HitTestBehavior.opaque,
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
                  if (cartTax > 0) ...[
                    const SizedBox(height: 8),
                    _PriceRow(
                      'Tax (${(cartTaxRate * 100).toStringAsFixed(2)}%)',
                      '\$${cartTax.toStringAsFixed(2)}',
                    ),
                  ],
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
            // ── Store Credit 抵扣 ──────────────────────────────────
            if (_storeCreditBalance >= 0) ...[
              const SizedBox(height: 12),
              _buildStoreCreditRow(totalAmount),
            ],
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

    // 动态查询 merchant 所在 metro 的税率
    final taxRateAsync = ref.watch(taxRateByMerchantProvider(
      widget.purchasedMerchantId ?? dealAsync.valueOrNull?.merchantId ?? '',
    ));
    final taxRate = taxRateAsync.valueOrNull ?? 0.0;

    return dealAsync.when(
      data: (deal) {
        // 综合 stock_limit 和 max_per_account 取更严格的上限
        final maxByStock = deal.stockLimit <= 0 ? 99 : deal.stockLimit.clamp(1, 99);
        final maxByAccount = deal.maxPerAccount <= 0 ? 99 : deal.maxPerAccount.clamp(1, 99);
        final maxPerPerson = (maxByStock < maxByAccount ? maxByStock : maxByAccount).clamp(1, 99);

        final subtotal = deal.discountPrice * _quantity;
        final discount = _promoResult?.calculatedDiscount ?? 0;
        final taxableAmount = subtotal - discount;
        // 从数据库动态读取税率（metro_tax_rates 表）
        final tax = (taxableAmount * taxRate * 100).roundToDouble() / 100;
        // 每张券收取 $0.99 服务费
        final serviceFee = 0.99 * _quantity;
        final total = taxableAmount + tax + serviceFee;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            leading: GestureDetector(
              behavior: HitTestBehavior.opaque,
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
                          behavior: HitTestBehavior.opaque,
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
                        height: 48,
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
                            padding: const EdgeInsets.symmetric(horizontal: 20),
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
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                    behavior: HitTestBehavior.opaque,
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
                      _PriceRow('Tax (${(taxRate * 100).toStringAsFixed(2)}%)', '\$${tax.toStringAsFixed(2)}'),
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
                // ── Store Credit 抵扣 ──────────────────────────
                if (_storeCreditBalance >= 0) ...[
                  const SizedBox(height: 12),
                  _buildStoreCreditRow(total),
                ],
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

  // ── Store Credit 抵扣行 ──────────────────────────────────────────

  Widget _buildStoreCreditRow(double totalAmount) {
    final creditUsed = _useStoreCredit
        ? (_storeCreditBalance > totalAmount ? totalAmount : _storeCreditBalance)
        : 0.0;
    final amountToPay = totalAmount - creditUsed;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _useStoreCredit
              ? AppColors.success.withValues(alpha: 0.4)
              : AppColors.surfaceVariant,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet,
                size: 20,
                color: _useStoreCredit ? AppColors.success : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Store Credit',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(
                      'Balance: \$${_storeCreditBalance.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _useStoreCredit,
                activeColor: AppColors.success,
                onChanged: (v) => setState(() => _useStoreCredit = v),
              ),
            ],
          ),
          if (_useStoreCredit) ...[
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Credit Applied', style: TextStyle(fontSize: 13, color: AppColors.success)),
                Text('-\$${creditUsed.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Amount to Pay', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Text('\$${amountToPay.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── 账单地址区域（Credit Card 模式专用） ──────────────────────────

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

          // ── 已保存地址列表 ──────────────────────────────────────
          if (_savedAddresses.isNotEmpty) ...[
            ..._savedAddresses.map((addr) {
              final isSelected = _selectedAddressId == addr.id && !_isAddingNewAddress;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _selectedAddressId = addr.id;
                    _isAddingNewAddress = false;
                    _fillFormFromAddress(addr);
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.05)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // 选中圆圈
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (addr.label.isNotEmpty)
                                  Text(
                                    addr.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                if (addr.isDefault) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Default',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              addr.summary,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 4),

            // ── Add New Address 按钮 ────────────────────────────
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _isAddingNewAddress = true;
                  _selectedAddressId = null;
                  _clearAddressForm();
                  _saveAsDefault = false;
                  _saveForFuture = true;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isAddingNewAddress
                        ? AppColors.primary
                        : AppColors.surfaceVariant,
                    width: _isAddingNewAddress ? 2 : 1,
                    style: _isAddingNewAddress
                        ? BorderStyle.solid
                        : BorderStyle.solid,
                  ),
                  color: _isAddingNewAddress
                      ? AppColors.primary.withValues(alpha: 0.05)
                      : Colors.transparent,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      size: 18,
                      color: _isAddingNewAddress
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Add New Address',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _isAddingNewAddress
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ── 新增地址表单（无已保存地址时始终显示，有地址时点击 Add New 后显示） ──
          if (_isAddingNewAddress || _savedAddresses.isEmpty) ...[
            if (_savedAddresses.isNotEmpty) const SizedBox(height: 12),
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
            const SizedBox(height: 12),

            // ── 两个勾选框 ──────────────────────────────────────
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _saveForFuture = !_saveForFuture),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _saveForFuture,
                      onChanged: (v) => setState(() => _saveForFuture = v ?? false),
                      activeColor: AppColors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Save for future use',
                    style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _saveAsDefault = !_saveAsDefault;
                // 设默认时自动勾选保存
                if (_saveAsDefault) _saveForFuture = true;
              }),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _saveAsDefault,
                      onChanged: (v) {
                        setState(() {
                          _saveAsDefault = v ?? false;
                          if (_saveAsDefault) _saveForFuture = true;
                        });
                      },
                      activeColor: AppColors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Save as default billing address',
                    style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          ],
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
      behavior: HitTestBehavior.opaque,
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
