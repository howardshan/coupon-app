import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';

/// 被推荐人注册成功后弹出的恭喜弹窗
/// 由 app.dart 的 authStateProvider signedIn 事件触发
void showReferralWelcomeDialog(BuildContext context, double bonusAmount) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => ReferralWelcomeDialog(bonusAmount: bonusAmount),
  );
}

class ReferralWelcomeDialog extends StatelessWidget {
  const ReferralWelcomeDialog({super.key, required this.bonusAmount});
  final double bonusAmount;

  @override
  Widget build(BuildContext context) {
    final amtStr = '\$${bonusAmount.toStringAsFixed(bonusAmount.truncateToDouble() == bonusAmount ? 0 : 2)}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 庆祝图标
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: AppColors.primaryGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.card_giftcard, size: 36, color: Colors.white),
            ),

            const SizedBox(height: 16),

            const Text(
              "You've Been Referred!",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),

            const SizedBox(height: 8),

            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                children: [
                  const TextSpan(text: 'You\'ve earned '),
                  TextSpan(
                    text: amtStr,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const TextSpan(
                    text: ' store credit!\n\nYour friend invited you to CrunchyPlum. '
                        'Your credit has been added to your account — '
                        'use it on your next purchase!',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // View My Credit 按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/profile/store-credit');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'View My Credit',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),

            const SizedBox(height: 8),

            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Continue',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
