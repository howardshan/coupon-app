import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  bool _scanned = false;
  bool _validating = false;
  String? _resultMessage;
  bool? _isSuccess;

  Future<void> _validateCoupon(String couponId) async {
    if (_validating || _scanned) return;
    setState(() {
      _scanned = true;
      _validating = true;
    });

    try {
      final client = ref.read(supabaseClientProvider);
      final coupon = await client
          .from('coupons')
          .select('id, status, expires_at')
          .eq('id', couponId)
          .maybeSingle();

      if (coupon == null) {
        _showResult(false, 'Invalid coupon');
        return;
      }

      final status = coupon['status'] as String;
      final expiresAt = DateTime.parse(coupon['expires_at'] as String);

      if (status == 'used') {
        _showResult(false, 'Coupon already used');
      } else if (DateTime.now().isAfter(expiresAt)) {
        _showResult(false, 'Coupon expired');
      } else {
        // Mark as used
        await client
            .from('coupons')
            .update({'status': 'used', 'used_at': DateTime.now().toIso8601String()})
            .eq('id', couponId);
        await client
            .from('orders')
            .update({'status': 'used'})
            .eq('coupon_id', couponId);

        _showResult(true, 'Coupon redeemed successfully!');
      }
    } catch (e) {
      _showResult(false, 'Error: $e');
    } finally {
      setState(() => _validating = false);
    }
  }

  void _showResult(bool success, String message) {
    setState(() {
      _isSuccess = success;
      _resultMessage = message;
    });
  }

  void _reset() {
    setState(() {
      _scanned = false;
      _resultMessage = null;
      _isSuccess = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Coupon')),
      body: _resultMessage != null
          ? _ResultView(
              message: _resultMessage!,
              isSuccess: _isSuccess!,
              onReset: _reset,
            )
          : Stack(
              children: [
                MobileScanner(
                  onDetect: (capture) {
                    final barcode = capture.barcodes.firstOrNull;
                    if (barcode?.rawValue != null) {
                      _validateCoupon(barcode!.rawValue!);
                    }
                  },
                ),
                // Scan overlay
                Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                if (_validating)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: const Text(
                    'Point camera at customer\'s QR code',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final String message;
  final bool isSuccess;
  final VoidCallback onReset;

  const _ResultView({
    required this.message,
    required this.isSuccess,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.cancel,
              size: 100,
              color: isSuccess ? AppColors.success : AppColors.error,
            ),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isSuccess ? AppColors.success : AppColors.error,
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan Another'),
            ),
          ],
        ),
      ),
    );
  }
}
