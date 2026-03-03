import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/domain/providers/auth_provider.dart';

/// 忘记密码页面：支持发送重置链接 + 60 秒倒计时重发 + Riverpod 状态管理
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  // 表单 key，用于校验
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  // 倒计时相关：60 秒冷却
  Timer? _cooldownTimer;
  int _secondsRemaining = 0;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  /// 启动 60 秒倒计时，期间禁用重发按钮
  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _secondsRemaining = 60);

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsRemaining--;
        if (_secondsRemaining <= 0) {
          timer.cancel();
        }
      });
    });
  }

  /// 发送重置链接，成功后启动倒计时
  Future<void> _sendResetLink() async {
    if (!_formKey.currentState!.validate()) return;

    await ref
        .read(forgotPasswordProvider.notifier)
        .sendResetLink(_emailCtrl.text.trim());

    // 检查是否成功发送（无 error）
    final state = ref.read(forgotPasswordProvider);
    if (state.isSent) {
      _startCooldown();
    }
  }

  /// 重发：重置 provider 状态后重新发送
  Future<void> _resendLink() async {
    if (_secondsRemaining > 0) return;

    // 重置 provider 以允许重新发送（保留 email）
    ref.read(forgotPasswordProvider.notifier).reset();

    await ref
        .read(forgotPasswordProvider.notifier)
        .sendResetLink(_emailCtrl.text.trim());

    // 无论成功与否都重启倒计时，防止用户频繁点击
    _startCooldown();
  }

  @override
  Widget build(BuildContext context) {
    final fpState = ref.watch(forgotPasswordProvider);

    // 监听 error，用 SnackBar 提示
    ref.listen<ForgotPasswordState>(forgotPasswordProvider, (_, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password'),
        // 返回时重置 provider 状态
        leading: BackButton(
          onPressed: () {
            ref.read(forgotPasswordProvider.notifier).reset();
            context.pop();
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: fpState.isSent
              ? _SuccessView(
                  secondsRemaining: _secondsRemaining,
                  onResend: _resendLink,
                  isResending: fpState.isLoading,
                )
              : _EmailFormView(
                  formKey: _formKey,
                  emailCtrl: _emailCtrl,
                  isLoading: fpState.isLoading,
                  onSubmit: _sendResetLink,
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 表单视图：输入邮箱并发送重置链接
// ---------------------------------------------------------------------------
class _EmailFormView extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final bool isLoading;
  final VoidCallback onSubmit;

  const _EmailFormView({
    required this.formKey,
    required this.emailCtrl,
    required this.isLoading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // 说明文字
          Text(
            "Enter your email and we'll send you a reset link.",
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 32),

          // 邮箱输入框
          AppTextField(
            controller: emailCtrl,
            label: 'Email',
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            prefixIcon: const Icon(Icons.email_outlined),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              // 简单 @ 校验
              if (!v.contains('@') || !v.contains('.')) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 32),

          // 发送按钮
          AppButton(
            label: 'Send Reset Link',
            isLoading: isLoading,
            onPressed: onSubmit,
            icon: Icons.send_outlined,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 成功视图：显示图标、隐私安全提示、倒计时重发按钮
// ---------------------------------------------------------------------------
class _SuccessView extends StatelessWidget {
  final int secondsRemaining;
  final VoidCallback onResend;
  final bool isResending;

  const _SuccessView({
    required this.secondsRemaining,
    required this.onResend,
    required this.isResending,
  });

  @override
  Widget build(BuildContext context) {
    // 倒计时是否仍在进行
    final isCoolingDown = secondsRemaining > 0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 48),

        // 成功图标（绿色）
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            size: 52,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: 24),

        // 标题
        Text(
          'Check your email',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
        ),
        const SizedBox(height: 12),

        // 隐私安全提示：不显示真实邮箱地址
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "If this email is registered, you'll receive a reset link shortly. "
            'Please also check your spam folder.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
          ),
        ),
        const SizedBox(height: 40),

        // 重发按钮：冷却期间禁用并显示倒计时
        AppButton(
          label: isCoolingDown
              ? 'Resend Link (${secondsRemaining}s)'
              : 'Resend Link',
          isLoading: isResending,
          // 冷却期内传 null 禁用按钮
          onPressed: isCoolingDown ? null : onResend,
          isOutlined: true,
          icon: Icons.refresh,
        ),
        const SizedBox(height: 16),

        // 返回登录的文字按钮
        TextButton.icon(
          onPressed: () => context.go('/auth/login'),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back to Sign In'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
