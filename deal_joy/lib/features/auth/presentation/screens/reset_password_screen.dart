import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../widgets/password_strength_indicator.dart';

/// 重置密码页面 — 用户点击邮件链接后落地此页，设置新密码
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  // 表单 key 用于统一校验
  final _formKey = GlobalKey<FormState>();

  // 密码输入控制器
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  // 用于驱动密码强度指示器的实时密码文本
  String _passwordText = '';

  @override
  void initState() {
    super.initState();
    // 监听密码输入变化，驱动强度指示器和要求列表实时更新
    _passwordCtrl.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    if (_passwordText != _passwordCtrl.text) {
      setState(() => _passwordText = _passwordCtrl.text);
    }
  }

  // 成功状态及倒计时
  bool _success = false;
  int _countdown = 3;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _passwordCtrl.removeListener(_onPasswordChanged);
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  // 启动倒计时，结束后跳转登录页
  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown <= 1) {
        timer.cancel();
        context.go('/auth/login');
      } else {
        setState(() => _countdown--);
      }
    });
  }

  // 提交新密码
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref
        .read(resetPasswordProvider.notifier)
        .updatePassword(_passwordCtrl.text);

    if (!mounted) return;

    if (success) {
      // 切换到成功视图并开始倒计时
      setState(() {
        _success = true;
        _countdown = 3;
      });
      _startCountdown();
    }
    // 失败时由 ref.listen 显示 SnackBar
  }

  // 密码规则校验：最少 8 位，包含大写、小写、数字、符号
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'At least 8 characters required';
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Must contain an uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Must contain a lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Must contain a digit';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\\/~`]').hasMatch(value)) {
      return 'Must contain a special character (!@#\$%...)';
    }
    return null;
  }

  // 确认密码校验
  String? _validateConfirm(String? value) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != _passwordCtrl.text) return 'Passwords do not match';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final resetState = ref.watch(resetPasswordProvider);
    final isLoading = resetState is AsyncLoading;

    // 监听错误，以 SnackBar 显示（如链接过期或无效）
    ref.listen<AsyncValue<void>>(resetPasswordProvider, (_, next) {
      if (next is AsyncError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              next.error.toString().contains('expired') ||
                      next.error.toString().contains('invalid')
                  ? 'Reset link has expired or is invalid. Please request a new one.'
                  : next.error.toString(),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set New Password'),
        // 成功后隐藏返回按钮，避免用户回到表单
        automaticallyImplyLeading: !_success,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _success ? _buildSuccessView() : _buildFormView(isLoading),
        ),
      ),
    );
  }

  // 成功视图：图标 + 文字 + 倒计时提示
  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 绿色勾选图标
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                size: 60,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Password reset successful!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Your password has been updated.\nYou can now sign in with your new password.',
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // 倒计时提示文字
            Text(
              'Redirecting to Sign In in $_countdown seconds...',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: 8),
            // 进度条视觉反馈
            LinearProgressIndicator(
              value: _countdown / 3,
              backgroundColor: AppColors.surfaceVariant,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.success),
            ),
          ],
        ),
      ),
    );
  }

  // 表单视图：新密码 + 确认密码 + 强度指示器 + 提交按钮
  Widget _buildFormView(bool isLoading) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 说明文字
          const Text(
            'Create a strong new password for your account.',
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),

          // 新密码输入框
          AppTextField(
            key: const ValueKey('reset_password_field'),
            controller: _passwordCtrl,
            label: 'New Password',
            hint: '••••••••',
            obscureText: true,
            validator: _validatePassword,
          ),

          // 密码强度指示器，随输入实时更新（由 initState 中的 listener 驱动）
          PasswordStrengthIndicator(password: _passwordText),

          const SizedBox(height: 20),

          // 确认密码输入框
          AppTextField(
            key: const ValueKey('reset_confirm_password_field'),
            controller: _confirmCtrl,
            label: 'Confirm Password',
            hint: '••••••••',
            obscureText: true,
            validator: _validateConfirm,
          ),

          const SizedBox(height: 12),

          // 密码要求提示列表
          _buildRequirementHints(),

          const SizedBox(height: 32),

          // 提交按钮
          AppButton(
            label: 'Reset Password',
            isLoading: isLoading,
            onPressed: isLoading ? null : _submit,
          ),
        ],
      ),
    );
  }

  // 显示密码要求列表，颜色随输入变化给予实时反馈
  Widget _buildRequirementHints() {
    final pw = _passwordText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Password requirements:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        _RequirementRow(
          label: 'At least 8 characters',
          met: pw.length >= 8,
        ),
        _RequirementRow(
          label: 'One uppercase letter (A–Z)',
          met: RegExp(r'[A-Z]').hasMatch(pw),
        ),
        _RequirementRow(
          label: 'One lowercase letter (a–z)',
          met: RegExp(r'[a-z]').hasMatch(pw),
        ),
        _RequirementRow(
          label: 'One digit (0–9)',
          met: RegExp(r'[0-9]').hasMatch(pw),
        ),
      ],
    );
  }
}

/// 单条密码要求行：根据是否满足显示不同颜色和图标
class _RequirementRow extends StatelessWidget {
  final String label;
  final bool met;

  const _RequirementRow({required this.label, required this.met});

  @override
  Widget build(BuildContext context) {
    final color = met ? AppColors.success : AppColors.textHint;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }
}
