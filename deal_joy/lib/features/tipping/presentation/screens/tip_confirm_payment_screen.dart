// 小费 3DS / SCA：持券人在此用同一 PaymentIntent 完成 PaymentSheet

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/stripe_app_config.dart';

class TipConfirmPaymentScreen extends ConsumerStatefulWidget {
  const TipConfirmPaymentScreen({super.key, required this.tipId});

  final String tipId;

  @override
  ConsumerState<TipConfirmPaymentScreen> createState() =>
      _TipConfirmPaymentScreenState();
}

class _TipConfirmPaymentScreenState extends ConsumerState<TipConfirmPaymentScreen> {
  bool _loading = true;
  bool _presenting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _waitForNativePresentationReady() async {
    for (var i = 0; i < 2; i++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
  }

  Future<void> _start() async {
    if (widget.tipId.isEmpty) {
      setState(() {
        _loading = false;
        _errorMessage = 'Invalid tip link';
      });
      return;
    }
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      Map<String, dynamic> data;
      try {
        final res = await Supabase.instance.client.functions.invoke(
          'confirm-tip-payment-session',
          body: {'tip_id': widget.tipId},
        );
        final raw = res.data;
        if (raw is Map<String, dynamic>) {
          data = raw;
        } else if (raw is String) {
          data = jsonDecode(raw) as Map<String, dynamic>;
        } else {
          throw Exception('Invalid response from server');
        }
      } on FunctionException catch (fe) {
        final parsed = _parseFnDetails(fe.details);
        final msg = parsed?['message'] as String? ??
            fe.reasonPhrase ??
            'Request failed';
        setState(() {
          _loading = false;
          _errorMessage = msg;
        });
        return;
      }

      final errCode = data['error'] as String?;
      if (errCode != null) {
        final msg = data['message'] as String? ?? 'Request failed';
        setState(() {
          _loading = false;
          _errorMessage = msg;
        });
        return;
      }

      final flow = data['flow'] as String? ?? '';
      if (flow == 'completed' || flow == 'processing') {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tip payment completed. Thank you!')),
          );
          context.pop(true);
        }
        return;
      }

      if (flow != 'ready') {
        setState(() {
          _loading = false;
          _errorMessage = 'This tip cannot be paid from the app right now.';
        });
        return;
      }

      final secret = data['client_secret'] as String?;
      if (secret == null || secret.isEmpty) {
        setState(() {
          _loading = false;
          _errorMessage = 'Missing payment session';
        });
        return;
      }

      if (mounted) {
        setState(() {
          _loading = false;
          _presenting = true;
        });
      }

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: secret,
          merchantDisplayName: 'Crunchy Plum',
          style: ThemeMode.light,
          returnURL: StripeAppConfig.paymentSheetReturnUrl,
          paymentMethodOrder: const ['card'],
        ),
      );

      await _waitForNativePresentationReady();
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      await Stripe.instance.presentPaymentSheet();
      if (mounted) {
        setState(() => _presenting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you! Your tip is processing.')),
        );
        context.pop(true);
      }
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        if (mounted) {
          setState(() {
            _loading = false;
            _presenting = false;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _presenting = false;
          _errorMessage = e.error.message ?? 'Payment failed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _presenting = false;
          _errorMessage = '$e';
        });
      }
    }
  }

  Map<String, dynamic>? _parseFnDetails(dynamic details) {
    try {
      if (details is Map<String, dynamic>) return details;
      if (details is String) return jsonDecode(details) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm tip'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _presenting ? null : () => context.pop(false),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _loading || _presenting
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Opening secure payment…',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _start,
                      child: const Text('Try again'),
                    ),
                  ] else
                    FilledButton(
                      onPressed: _start,
                      child: const Text('Continue'),
                    ),
                ],
              ),
      ),
    );
  }
}
