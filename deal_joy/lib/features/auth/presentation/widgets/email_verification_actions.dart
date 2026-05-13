import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// 未验证邮箱时的两个主操作（英文 UI）
/// 使用卡片 + 主次按钮，与全宽主按钮视觉层级对齐
class EmailVerificationActions extends StatelessWidget {
  const EmailVerificationActions({
    super.key,
    required this.emailEmpty,
    required this.resendLoading,
    required this.onEnterCode,
    required this.onResend,
    this.showHeader = true,
  });

  final bool emailEmpty;
  final bool resendLoading;
  final VoidCallback onEnterCode;
  final Future<void> Function() onResend;

  /// 为 false 时仅展示按钮区（注册页上方已有说明文案）
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader) ...[
              Text(
                'Verify your email',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Use the code we sent you, or request a new one.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
            ],
            FilledButton.icon(
              onPressed: emailEmpty ? null : onEnterCode,
              icon: const Icon(Icons.pin_outlined, size: 20),
              label: const Text('Enter verification code'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.surfaceVariant,
                disabledForegroundColor: AppColors.textHint,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: emailEmpty || resendLoading
                  ? null
                  : () async {
                      await onResend();
                    },
              icon: resendLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(Icons.mark_email_read_outlined, size: 20),
              label: Text(resendLoading ? 'Sending…' : 'Resend code'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 50),
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.55),
                  width: 1.25,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
