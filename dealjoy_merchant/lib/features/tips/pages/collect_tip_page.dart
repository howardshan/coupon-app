// Collect optional post-redemption tip (merchant tablet → customer pays via Stripe PaymentSheet).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';

import '../models/tip_models.dart';
import '../providers/tip_payment_provider.dart';
import '../services/tip_payment_service.dart';

class CollectTipPage extends ConsumerStatefulWidget {
  const CollectTipPage({
    super.key,
    required this.couponId,
    required this.dealTitle,
    required this.tip,
  });

  final String couponId;
  final String dealTitle;
  final TipDealConfig tip;

  @override
  ConsumerState<CollectTipPage> createState() => _CollectTipPageState();
}

class _CollectTipPageState extends ConsumerState<CollectTipPage> {
  int? _selectedPresetIndex;
  final _customController = TextEditingController();
  bool _useCustom = false;
  bool _busy = false;

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

    setState(() => _busy = true);
    try {
      final svc = ref.read(tipPaymentServiceProvider);
      final presetChoice = _useCustom
          ? 'custom'
          : _selectedPresetIndex != null
              ? 'preset_${_selectedPresetIndex! + 1}'
              : null;
      final res = await svc.createPaymentIntent(
        couponId: widget.couponId,
        amountCents: amount,
        presetChoice: presetChoice,
      );
      final secret = res['client_secret'] as String?;
      if (secret == null || secret.isEmpty) {
        throw TipPaymentException('Missing payment client secret');
      }

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: secret,
          merchantDisplayName: 'Crunchy Plum',
          style: ThemeMode.light,
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      if (mounted) {
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
      if (mounted) setState(() => _busy = false);
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
          const SizedBox(height: 28),
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
