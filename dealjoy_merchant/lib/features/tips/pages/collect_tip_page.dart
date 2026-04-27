// Collect optional post-redemption tip (merchant tablet → customer pays via Stripe PaymentSheet).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/stripe_merchant_config.dart';
import '../../orders/providers/orders_provider.dart';
import '../models/tip_models.dart';
import '../providers/tip_payment_provider.dart';
import '../services/tip_payment_service.dart';
import '../widgets/tip_signature_pad.dart';

/// 小费支付流程阶段：便于区分「等 Edge」与「等 Stripe」
enum _CollectTipPayPhase { idle, creatingIntent, openingPaymentSheet }

class CollectTipPage extends ConsumerStatefulWidget {
  const CollectTipPage({
    super.key,
    required this.couponId,
    required this.dealTitle,
    required this.tip,
    this.orderIdForRefresh,
  });

  final String couponId;
  final String dealTitle;
  final TipDealConfig tip;

  /// 关联 `orders.id`，收小费成功后 `invalidate` 订单列表/详情
  final String? orderIdForRefresh;

  @override
  ConsumerState<CollectTipPage> createState() => _CollectTipPageState();
}

class _CollectTipPageState extends ConsumerState<CollectTipPage> {
  final GlobalKey<TipSignaturePadState> _signatureKey =
      GlobalKey<TipSignaturePadState>();
  int? _selectedPresetIndex;
  final _customController = TextEditingController();
  bool _useCustom = false;
  _CollectTipPayPhase _payPhase = _CollectTipPayPhase.idle;

  bool get _busy => _payPhase != _CollectTipPayPhase.idle;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  int _presetCents(int index) {
    final c = widget.tip;
    final p = [c.preset1, c.preset2, c.preset3][index];
    if (p == null) return 0;
    if (c.tipsMode == 'percent') {
      return ((c.tipBaseCents * p) / 100).round();
    }
    return (p * 100).round();
  }

  int _maxTipCents() {
    final c = widget.tip;
    if (c.tipsMode == 'percent') {
      return c.tipBaseCents;
    }
    final cents = [
      if (c.preset1 != null) (c.preset1! * 100).round(),
      if (c.preset2 != null) (c.preset2! * 100).round(),
      if (c.preset3 != null) (c.preset3! * 100).round(),
    ];
    if (cents.isEmpty) return c.tipBaseCents;
    return cents.reduce((a, b) => a > b ? a : b);
  }

  /// 等待若干帧布局完成后再由 Stripe present sheet，避免 iOS 报错：
  /// "Attempt to present ... whose view is not in the window hierarchy"
  ///（常见于 go_router push 到本页后立即点 Continue）。
  Future<void> _waitForNativePresentationReady() async {
    for (var i = 0; i < 2; i++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
  }

  int? _selectedAmountCents() {
    if (_useCustom) {
      final raw = _customController.text.trim();
      if (raw.isEmpty) return null;
      final v = double.tryParse(raw);
      if (v == null || v < 0) return null;
      return (v * 100).round();
    }
    if (_selectedPresetIndex == null) return null;
    return _presetCents(_selectedPresetIndex!);
  }

  Future<void> _pay() async {
    final amount = _selectedAmountCents();
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a tip amount or enter a valid custom amount.')),
      );
      return;
    }
    final maxC = _maxTipCents();
    if (amount > maxC) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Amount exceeds maximum (\$${(maxC / 100).toStringAsFixed(2)}).')),
      );
      return;
    }

    final sig = _signatureKey.currentState;
    if (sig == null || !sig.hasSignature) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in the box above to confirm the tip.'),
        ),
      );
      return;
    }

    String signaturePngBase64;
    try {
      signaturePngBase64 = await sig.toPngBase64();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not capture signature: $e')),
        );
      }
      return;
    }

    setState(() => _payPhase = _CollectTipPayPhase.creatingIntent);
    try {
      final svc = ref.read(tipPaymentServiceProvider);
      final presetChoice = _useCustom
          ? 'custom'
          : _selectedPresetIndex != null
              ? 'preset_${_selectedPresetIndex! + 1}'
              : null;
      if (kDebugMode) {
        debugPrint('[CollectTip] _pay: invoking createPaymentIntent amountCents=$amount');
      }
      final res = await svc.createPaymentIntent(
        couponId: widget.couponId,
        amountCents: amount,
        presetChoice: presetChoice,
        signaturePngBase64: signaturePngBase64,
      );
      if (kDebugMode) {
        final pi = res['stripe_payment_intent_id'] as String?;
        final fl = res['flow'] as String?;
        debugPrint(
          '[CollectTip] createPaymentIntent flow=$fl (pi=${pi ?? "?"})',
        );
      }

      String? flow = res['flow'] as String?;
      final clientSecretRaw = res['client_secret'];
      if (flow == null &&
          clientSecretRaw is String &&
          clientSecretRaw.isNotEmpty) {
        flow = 'merchant_fallback';
      }
      flow ??= 'merchant_fallback';

      if (flow == 'completed') {
        if (mounted) {
          _invalidateOrderData();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tip payment received. Thank you!')),
          );
          context.pop(true);
        }
        return;
      }
      if (flow == 'processing') {
        if (mounted) {
          _invalidateOrderData();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tip payment is processing. Thank you!'),
            ),
          );
          context.pop(true);
        }
        return;
      }
      if (flow == 'requires_customer_action') {
        if (mounted) {
          _invalidateOrderData();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Payment request sent to the customer's phone. Ask them to approve in the Crunchy Plum app.",
              ),
            ),
          );
          context.pop(true);
        }
        return;
      }

      if (flow != 'merchant_fallback') {
        throw TipPaymentException('Unexpected payment flow from server');
      }

      final secret = res['client_secret'] as String?;
      if (secret == null || secret.isEmpty) {
        throw TipPaymentException('Missing payment client secret');
      }

      if (mounted) {
        setState(() => _payPhase = _CollectTipPayPhase.openingPaymentSheet);
      }
      if (kDebugMode) {
        debugPrint('[CollectTip] calling Stripe.initPaymentSheet');
      }
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: secret,
          merchantDisplayName: 'Crunchy Plum',
          style: ThemeMode.light,
          // 显式 returnURL，否则 iOS analytics 常为 return_url:false，且部分支付方式无法正确回跳
          returnURL: StripeMerchantConfig.paymentSheetReturnUrl,
          // 小费场景仅需要卡；收窄列表可减少无关 LPM 与 present 链路复杂度
          paymentMethodOrder: const ['card'],
        ),
      );
      if (kDebugMode) {
        debugPrint(
          '[CollectTip] PaymentSheet returnURL=${StripeMerchantConfig.paymentSheetReturnUrl}',
        );
      }
      if (kDebugMode) {
        debugPrint('[CollectTip] initPaymentSheet done → wait frames + delay then presentPaymentSheet');
      }
      await _waitForNativePresentationReady();
      if (!mounted) return;
      // 根 Navigator push 后仍可能与转场动画重叠，短延迟降低 iOS present 失败概率
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('[CollectTip] calling presentPaymentSheet');
      }
      await Stripe.instance.presentPaymentSheet();
      if (kDebugMode) {
        debugPrint('[CollectTip] presentPaymentSheet completed');
      }

      if (mounted) {
        _invalidateOrderData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tip payment successful. Thank you!')),
        );
        context.pop(true);
      }
    } on TipPaymentException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        if (mounted) context.pop(false);
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.error.message ?? 'Payment failed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _payPhase = _CollectTipPayPhase.idle);
    }
  }

  void _invalidateOrderData() {
    ref.invalidate(ordersNotifierProvider);
    final oid = widget.orderIdForRefresh;
    if (oid != null && oid.isNotEmpty) {
      ref.invalidate(orderDetailProvider(oid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.tip;
    final modeLabel = c.tipsMode == 'fixed' ? 'Fixed amount presets' : 'Percentage of purchase';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collect Tip'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : () => context.pop(false),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(widget.dealTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(modeLabel, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < 3; i++)
                if ([c.preset1, c.preset2, c.preset3][i] != null)
                  ChoiceChip(
                    label: Text(_chipLabel(i)),
                    selected: !_useCustom && _selectedPresetIndex == i,
                    onSelected: _busy
                        ? null
                        : (sel) {
                            setState(() {
                              _useCustom = false;
                              _selectedPresetIndex = sel ? i : null;
                            });
                          },
                  ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _customController,
            decoration: const InputDecoration(
              labelText: 'Custom amount (USD)',
              border: OutlineInputBorder(),
              hintText: 'e.g. 2.50',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onTap: () => setState(() {
              _useCustom = true;
              _selectedPresetIndex = null;
            }),
            onChanged: (_) => setState(() => _useCustom = true),
          ),
          const SizedBox(height: 20),
          Text(
            'Customer signature',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          TipSignaturePad(
            key: _signatureKey,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      _signatureKey.currentState?.clear();
                      setState(() {});
                    },
              child: const Text('Clear'),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _pay,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Continue to payment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          if (_payPhase == _CollectTipPayPhase.openingPaymentSheet) ...[
            const SizedBox(height: 12),
            Text(
              'Opening secure payment form…',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  String _chipLabel(int index) {
    final c = widget.tip;
    final p = [c.preset1, c.preset2, c.preset3][index];
    if (p == null) return '';
    if (c.tipsMode == 'percent') {
      final cents = _presetCents(index);
      final ps = p == p.floorToDouble() ? p.toInt().toString() : p.toString();
      return '$ps% (\$${(cents / 100).toStringAsFixed(2)})';
    }
    return '\$${p.toStringAsFixed(2)}';
  }
}
