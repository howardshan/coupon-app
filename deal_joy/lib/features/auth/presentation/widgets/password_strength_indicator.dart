import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// 密码强度等级
enum PasswordStrength { none, weak, medium, strong }

/// 计算密码强度
PasswordStrength calculatePasswordStrength(String password) {
  if (password.isEmpty) return PasswordStrength.none;
  if (password.length < 8) return PasswordStrength.weak;

  int score = 0;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  if (RegExp(r'[a-z]').hasMatch(password)) score++;
  if (RegExp(r'[A-Z]').hasMatch(password)) score++;
  if (RegExp(r'[0-9]').hasMatch(password)) score++;
  if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) score++;

  if (score <= 2) return PasswordStrength.weak;
  if (score <= 4) return PasswordStrength.medium;
  return PasswordStrength.strong;
}

/// 密码强度指示器 Widget
class PasswordStrengthIndicator extends StatelessWidget {
  final String password;

  const PasswordStrengthIndicator({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    final strength = calculatePasswordStrength(password);
    if (strength == PasswordStrength.none) return const SizedBox.shrink();

    final (color, label, fraction) = switch (strength) {
      PasswordStrength.weak => (AppColors.error, 'Weak', 0.33),
      PasswordStrength.medium => (AppColors.warning, 'Medium', 0.66),
      PasswordStrength.strong => (AppColors.success, 'Strong', 1.0),
      PasswordStrength.none => (Colors.transparent, '', 0.0),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fraction,
                backgroundColor: AppColors.surfaceVariant,
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
