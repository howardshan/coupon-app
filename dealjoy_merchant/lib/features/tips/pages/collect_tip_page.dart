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

  List<int> _availablePresetIndexes() {
    final c = widget.tip;
    final values = [c.preset1, c.preset2, c.preset3];
    return [
      for (var i = 0; i < values.length; i++)
        if (values[i] != null) i,
    ];
  }

  /// 第一步：校验金额后弹出签名板，确认后再走支付
  Future<void> _onNextPressed() async {
    if (_busy) return;
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

    final signaturePngBase64 = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      builder: (ctx) => const _TipSignatureSheet(),
    );
    if (!mounted || signaturePngBase64 == null || signaturePngBase64.isEmpty) {
      return;
    }

    await _submitPayment(signaturePngBase64: signaturePngBase64);
  }

  Future<void> _submitPayment({required String signaturePngBase64}) async {
    // 签名确认后再次读取金额（防止极端情况下输入被改动）
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

    setState(() => _payPhase = _CollectTipPayPhase.creatingIntent);
    try {
      final svc = ref.read(tipPaymentServiceProvider);
      final presetChoice = _useCustom
          ? 'custom'
          : _selectedPresetIndex != null
              ? 'preset_${_selectedPresetIndex! + 1}'
              : null;
      if (kDebugMode) {
        debugPrint('[CollectTip] _submitPayment: invoking createPaymentIntent amountCents=$amount');
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
    final presetIndexes = _availablePresetIndexes();
    final cardBorder = Border.all(color: Colors.grey.shade200);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAF8),
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
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: cardBorder,
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFFF6B35), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.dealTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(modeLabel, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: cardBorder,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tip options',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 10),
                if (presetIndexes.isNotEmpty)
                  Row(
                    children: [
                      for (var i = 0; i < presetIndexes.length; i++) ...[
                        Expanded(
                          child: _TipOptionButton(
                            title: _tipOptionLabel(presetIndexes[i]).$1,
                            subtitle: _tipOptionLabel(presetIndexes[i]).$2,
                            selected: !_useCustom && _selectedPresetIndex == presetIndexes[i],
                            onTap: _busy
                                ? null
                                : () {
                                    setState(() {
                                      _useCustom = false;
                                      _selectedPresetIndex = presetIndexes[i];
                                    });
                                  },
                          ),
                        ),
                        if (i != presetIndexes.length - 1) const SizedBox(width: 10),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: cardBorder,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Custom amount',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _customController,
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    labelText: 'Custom amount (USD)',
                    border: const OutlineInputBorder(),
                    hintText: 'e.g. 2.50',
                    filled: true,
                    fillColor: const Color(0xFFFFFBFA),
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
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _onNextPressed,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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

  (String, String) _tipOptionLabel(int index) {
    final c = widget.tip;
    final p = [c.preset1, c.preset2, c.preset3][index];
    if (p == null) return ('', '');
    if (c.tipsMode == 'percent') {
      final ps = p == p.floorToDouble() ? p.toInt().toString() : p.toString();
      return ('$ps%', '(\$${(_presetCents(index) / 100).toStringAsFixed(2)})');
    }
    return (_chipLabel(index), '');
  }
}

/// 第二步：底部弹层内完成顾客签名，确认后返回 PNG base64
class _TipSignatureSheet extends StatefulWidget {
  const _TipSignatureSheet();

  @override
  State<_TipSignatureSheet> createState() => _TipSignatureSheetState();
}

class _TipSignatureSheetState extends State<_TipSignatureSheet> {
  final GlobalKey<TipSignaturePadState> _padKey = GlobalKey<TipSignaturePadState>();

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Customer signature',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TipSignaturePad(
                key: _padKey,
                onChanged: (_) => setState(() {}),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    _padKey.currentState?.clear();
                    setState(() {});
                  },
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: shape,
                        side: BorderSide(color: Colors.grey.shade300, width: 1.2),
                        foregroundColor: Colors.black87,
                        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 7,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: shape,
                        backgroundColor: const Color(0xFFFF6B35),
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      onPressed: () async {
                        final s = _padKey.currentState;
                        if (s == null || !s.hasSignature) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please sign in the box above to confirm the tip.'),
                            ),
                          );
                          return;
                        }
                        try {
                          final b64 = await s.toPngBase64();
                          if (context.mounted) Navigator.pop(context, b64);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Could not capture signature: $e')),
                            );
                          }
                        }
                      },
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Continue to payment'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TipOptionButton extends StatelessWidget {
  const _TipOptionButton({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = const Color(0xFFFF6B35);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFF8A5E), Color(0xFFFF6B35)],
                  )
                : null,
            color: selected ? null : Colors.white,
            border: Border.all(
              color: selected ? activeColor : Colors.grey.shade300,
              width: selected ? 1.5 : 1.1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.22),
                      blurRadius: 9,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          // 勾选图标用 Stack 叠在角上，避免塞进 Column 导致固定高度内溢出（如 BOTTOM OVERFLOWED BY 2.0）
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white.withValues(alpha: 0.94) : Colors.black54,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.check_circle_rounded, size: 16, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
