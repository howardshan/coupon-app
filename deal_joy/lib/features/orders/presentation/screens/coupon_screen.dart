import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/orders_provider.dart';

class CouponScreen extends ConsumerWidget {
  final String couponId;

  const CouponScreen({super.key, required this.couponId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final couponAsync = ref.watch(couponDataProvider(couponId));

    return Scaffold(
      appBar: AppBar(title: const Text('Your Coupon')),
      body: couponAsync.when(
        data: (coupon) => _CouponBody(coupon: coupon),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _CouponBody extends StatelessWidget {
  final Map<String, dynamic> coupon;

  const _CouponBody({required this.coupon});

  @override
  Widget build(BuildContext context) {
    final qrData = coupon['qr_code'] as String? ?? coupon['id'] as String;
    final status = coupon['status'] as String? ?? 'unused';
    final isUsed = status == 'used';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isUsed
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isUsed ? 'USED' : 'READY TO USE',
                style: TextStyle(
                  color: isUsed ? AppColors.success : AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // QR Code
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ColorFiltered(
                colorFilter: isUsed
                    ? const ColorFilter.mode(
                        Colors.grey, BlendMode.saturation)
                    : const ColorFilter.mode(
                        Colors.transparent, BlendMode.saturation),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 240,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: AppColors.textPrimary,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Coupon ID
            Text(
              'Coupon ID',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              coupon['id'] as String,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, letterSpacing: 1.2),
            ),
            const SizedBox(height: 32),

            if (!isUsed)
              const Text(
                'Show this QR code to the merchant to redeem your deal.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
