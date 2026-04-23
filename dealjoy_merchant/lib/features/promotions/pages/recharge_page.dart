// 充值页面
// 当前余额展示
// 快速选择金额：$50, $100, $200, $500
// 自定义金额输入（Min $20 · Max $5,000）
// 内嵌 Stripe CardField 输入卡号，调用 confirmPayment 完成支付

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import '../providers/promotions_provider.dart';

// =============================================================
// RechargePage — 充值页面（ConsumerStatefulWidget）
// =============================================================
class RechargePage extends ConsumerStatefulWidget {
  const RechargePage({super.key});

  @override
  ConsumerState<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends ConsumerState<RechargePage> {
  static const _presetAmounts = [50, 100, 200, 500];

  double _selectedAmount = 100.0;
  bool _isCustom         = false;
  bool _isProcessing     = false;
  bool _cardComplete     = false;

  final _customController = TextEditingController();
  final _formKey           = GlobalKey<FormState>();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------
  // 处理支付流程：获取 clientSecret → confirmPayment
  // ----------------------------------------------------------
  Future<void> _pay() async {
    if (_isCustom && !_formKey.currentState!.validate()) return;

    if (_selectedAmount < 20 || _selectedAmount > 5000) {
      _showError('Amount must be between \$20 and \$5,000');
      return;
    }

    if (!_cardComplete) {
      _showError('Please enter complete card details');
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final service = ref.read(promotionsServiceProvider);

      // 1. 后端创建 PaymentIntent，返回 clientSecret + paymentIntentId
      final session = await service.createRecharge(_selectedAmount);

      // 2. 用 CardField 中输入的卡片信息直接确认支付
      await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: session.clientSecret,
        data: const PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(),
        ),
      );

      // 3. 支付成功后立即通知服务端触发余额更新（不等 webhook）
      await service.completeRecharge(session.paymentIntentId);

      // 4. 刷新本地余额和充值记录
      await ref.read(adAccountProvider.notifier).refresh();
      ref.read(rechargesProvider.notifier).refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment successful! Ad balance updated.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return;
      _showError(e.error.localizedMessage ?? e.error.message ?? 'Payment failed');
    } catch (e) {
      _showError('Recharge failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(adAccountProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ------------------------------------------------
              // 当前余额展示
              // ------------------------------------------------
              _CurrentBalanceCard(accountAsync: accountAsync),
              const SizedBox(height: 28),

              // ------------------------------------------------
              // 快速金额选择
              // ------------------------------------------------
              const _SectionLabel(label: 'Select Amount'),
              const SizedBox(height: 12),
              _PresetAmountGrid(
                presets: _presetAmounts,
                selected: _isCustom ? null : _selectedAmount.toInt(),
                onTap: (amount) {
                  setState(() {
                    _selectedAmount = amount.toDouble();
                    _isCustom       = false;
                    _customController.clear();
                  });
                },
              ),
              const SizedBox(height: 20),

              // ------------------------------------------------
              // 自定义金额输入
              // ------------------------------------------------
              const _SectionLabel(label: 'Custom Amount'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _customController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  hintText: 'Enter amount',
                  prefixText: '\$ ',
                  helperText: 'Min \$20 · Max \$5,000',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: Color(0xFFFF6B35)),
                  ),
                ),
                validator: _isCustom
                    ? (val) {
                        final v = double.tryParse(val ?? '');
                        if (v == null) return 'Enter a valid amount';
                        if (v < 20)   return 'Minimum \$20';
                        if (v > 5000) return 'Maximum \$5,000';
                        return null;
                      }
                    : null,
                onChanged: (val) {
                  final parsed = double.tryParse(val);
                  if (parsed != null) {
                    setState(() {
                      _selectedAmount = parsed;
                      _isCustom       = true;
                    });
                  } else if (val.isEmpty) {
                    setState(() => _isCustom = false);
                  }
                },
              ),
              const SizedBox(height: 28),

              // ------------------------------------------------
              // 卡片信息输入（Stripe CardField）
              // ------------------------------------------------
              const _SectionLabel(label: 'Card Details'),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                child: CardField(
                  onCardChanged: (card) {
                    setState(() => _cardComplete = card?.complete ?? false);
                  },
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ------------------------------------------------
              // 金额确认卡片
              // ------------------------------------------------
              _AmountSummaryCard(amount: _selectedAmount),
              const SizedBox(height: 24),

              // ------------------------------------------------
              // 支付按钮
              // ------------------------------------------------
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_isProcessing || !_cardComplete) ? null : _pay,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.lock_outlined, size: 18),
                  label: Text(
                    _isProcessing
                        ? 'Processing...'
                        : 'Pay \$${_selectedAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade200,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 安全提示
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user_outlined,
                        size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text(
                      'Secured by Stripe',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        color: const Color(0xFF1A1A2E),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text(
        'Recharge Ad Balance',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A2E),
        ),
      ),
    );
  }
}

// =============================================================
// 私有辅助组件
// =============================================================

class _CurrentBalanceCard extends StatelessWidget {
  final AsyncValue<dynamic> accountAsync;
  const _CurrentBalanceCard({required this.accountAsync});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: accountAsync.when(
        loading: () => const SizedBox(
          height: 48,
          child: Center(
            child: CircularProgressIndicator(
                color: Colors.white54, strokeWidth: 2),
          ),
        ),
        error: (e, s) => const Text('Balance unavailable',
            style: TextStyle(color: Colors.white54, fontSize: 14)),
        data: (account) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Current Ad Balance',
                style: TextStyle(fontSize: 13, color: Colors.white54)),
            const SizedBox(height: 8),
            Text(
              '\$${(account.balance as num).toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A2E),
        ));
  }
}

class _PresetAmountGrid extends StatelessWidget {
  final List<int> presets;
  final int? selected;
  final ValueChanged<int> onTap;

  const _PresetAmountGrid({
    required this.presets,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      children: presets.map((amount) {
        final isSelected = selected == amount;
        return GestureDetector(
          onTap: () => onTap(amount),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFFF6B35)
                  : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFFF6B35)
                    : const Color(0xFFE0E0E0),
              ),
            ),
            child: Center(
              child: Text(
                '\$$amount',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? Colors.white
                      : const Color(0xFF1A1A2E),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _AmountSummaryCard extends StatelessWidget {
  final double amount;
  const _AmountSummaryCard({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F0FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Recharge Amount',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF5E35B1),
              )),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF5E35B1),
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}
