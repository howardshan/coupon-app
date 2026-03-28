import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/presentation/widgets/password_strength_indicator.dart';

/// 修改密码页面
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  /// 是否正在提交
  bool _isLoading = false;
  String? _errorMessage;

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  @override
  void initState() {
    super.initState();
    _oldPasswordCtrl.addListener(_clearError);
    _newPasswordCtrl.addListener(_clearError);
    _confirmPasswordCtrl.addListener(_clearError);
  }

  @override
  void dispose() {
    _oldPasswordCtrl.removeListener(_clearError);
    _newPasswordCtrl.removeListener(_clearError);
    _confirmPasswordCtrl.removeListener(_clearError);
    _oldPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  /// 将 Supabase AuthException 转为用户友好提示
  String _friendlyPasswordError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login') || lower.contains('invalid credentials')) {
      return 'Current password is incorrect.';
    }
    if (lower.contains('same password') || lower.contains('different password')) {
      return 'New password must be different from your current password.';
    }
    if (lower.contains('rate limit') || lower.contains('too many requests')) {
      return 'Too many attempts. Please try again later.';
    }
    if (lower.contains('weak') || lower.contains('too short')) {
      return 'Password is too weak. Please choose a stronger one.';
    }
    if (lower.contains('network') || lower.contains('connection')) {
      return 'Network error. Please check your connection.';
    }
    return 'Failed to update password. Please try again.';
  }

  /// 验证旧密码并更新为新密码
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final client = Supabase.instance.client;
      final email = client.auth.currentUser?.email;

      if (email == null) {
        setState(() => _errorMessage = 'Unable to identify current user. Please log in again.');
        return;
      }

      // 第一步：用旧密码重新登录以验证身份
      await client.auth.signInWithPassword(
        email: email,
        password: _oldPasswordCtrl.text,
      );

      // 第二步：更新为新密码
      await client.auth.updateUser(
        UserAttributes(password: _newPasswordCtrl.text),
      );

      if (!mounted) return;

      // 成功提示并返回上一页
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop();
    } on AuthException catch (e) {
      // Supabase 认证错误（旧密码错误等）
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyPasswordError(e.message));
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 验证密码策略：最少 8 字符、含大写、小写、数字、符号
  String? _validateNewPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a new password';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain at least one number';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\\/~`]').hasMatch(value)) {
      return 'Password must contain at least one special character (!@#\$%...)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Change Password'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 页面说明文字
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.info,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Enter your current password to verify your identity, then set a new password.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // 当前密码
              AppTextField(
                controller: _oldPasswordCtrl,
                label: 'Current Password',
                hint: 'Enter your current password',
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your current password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // 新密码（含强度指示器）
              AppTextField(
                controller: _newPasswordCtrl,
                label: 'New Password',
                hint: 'At least 8 chars, uppercase, lowercase & number',
                obscureText: true,
                validator: _validateNewPassword,
              ),
              // 实时更新密码强度（onChanged 通过监听 controller 实现）
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _newPasswordCtrl,
                builder: (_, value, _) {
                  return PasswordStrengthIndicator(password: value.text);
                },
              ),
              const SizedBox(height: 20),

              // 确认新密码
              AppTextField(
                controller: _confirmPasswordCtrl,
                label: 'Confirm New Password',
                hint: 'Re-enter your new password',
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your new password';
                  }
                  if (value != _newPasswordCtrl.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),

              // 内联错误提示
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: AppColors.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.error,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 36),

              // 提交按钮
              AppButton(
                label: 'Update Password',
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
