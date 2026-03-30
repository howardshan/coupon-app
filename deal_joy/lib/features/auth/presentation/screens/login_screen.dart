import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/domain/providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  // "Remember me" 复选框状态，默认不勾选
  bool _rememberMe = false;

  // 登录错误信息（显示在密码框下方）
  String? _loginError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // 邮箱格式正则验证
  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  );

  // 表单提交：验证后调用 signIn，清除旧错误
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loginError = null);
    await ref.read(authNotifierProvider.notifier).signIn(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
        );
  }

  // Google 登录
  Future<void> _signInWithGoogle() async {
    await ref.read(authNotifierProvider.notifier).signInWithGoogle();
  }

  // Apple 登录（仅 iOS）
  Future<void> _signInWithApple() async {
    await ref.read(authNotifierProvider.notifier).signInWithApple();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState is AsyncLoading;

    // 监听 auth 状态：成功时跳转首页，出错时显示错误信息
    ref.listen(authNotifierProvider, (_, next) {
      if (next is AsyncData && next.value != null) {
        // 登录成功，跳转首页
        context.go('/home');
      } else if (next is AsyncError) {
        final err = next.error!;
        // 直接取 AppException.message，避免显示 "AppException:" 前缀
        final msg = err is AppException ? err.message : err.toString();
        setState(() => _loginError = msg);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // ---- 返回浏览按钮（允许用户跳过登录） ----
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.go('/home'),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                    label: const Text('Browse as Guest'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ---- 品牌区域 ----
                Center(
                  child: Column(
                    children: [
                      // Logo 文字
                      Text(
                        'Crunchy Plum',
                        style: Theme.of(context)
                            .textTheme
                            .headlineLarge
                            ?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                      ),
                      const SizedBox(height: 6),
                      // 副标题
                      Text(
                        'Best local deals in Dallas',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),

                // ---- 欢迎语 ----
                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sign in to continue',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),

                const SizedBox(height: 32),

                // ---- 邮箱输入框（正则验证）----
                AppTextField(
                  key: const ValueKey('login_email_field'),
                  controller: _emailCtrl,
                  label: 'Email',
                  hint: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: const Icon(Icons.email_outlined),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Email is required';
                    }
                    if (!_emailRegex.hasMatch(v.trim())) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // ---- 密码输入框（最小 8 位，show/hide 内置于 AppTextField）----
                AppTextField(
                  key: const ValueKey('login_password_field'),
                  controller: _passwordCtrl,
                  label: 'Password',
                  hint: '••••••••',
                  obscureText: true,
                  prefixIcon: const Icon(Icons.lock_outline),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Password is required';
                    }
                    if (v.length < 8) {
                      return 'Password must be at least 8 characters';
                    }
                    return null;
                  },
                ),

                // ---- 登录错误提示（密码框下方）----
                if (_loginError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _loginError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.error,
                          ),
                    ),
                  ),

                const SizedBox(height: 4),

                // ---- Forgot password 链接（右对齐）----
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('login_forgot_password_btn'),
                    onPressed: () => context.push('/auth/forgot-password'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ---- Remember me 复选框 ----
                GestureDetector(
                  onTap: () => setState(() => _rememberMe = !_rememberMe),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _rememberMe,
                          onChanged: (v) =>
                              setState(() => _rememberMe = v ?? false),
                          activeColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Keep me signed in for 30 days',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textPrimary,
                            ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ---- Sign In 按钮 ----
                AppButton(
                  label: 'Sign In',
                  isLoading: isLoading,
                  onPressed: isLoading ? null : _submit,
                ),

                const SizedBox(height: 28),

                // ---- "or continue with" 分割线 ----
                Row(
                  children: [
                    const Expanded(child: Divider(thickness: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'or continue with',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ),
                    const Expanded(child: Divider(thickness: 1)),
                  ],
                ),

                const SizedBox(height: 20),

                // ---- Google 登录按钮 ----
                AppButton(
                  label: 'Continue with Google',
                  isOutlined: true,
                  isLoading: false,
                  onPressed: isLoading ? null : _signInWithGoogle,
                  // AppButton 的 icon 参数只接受 IconData，改用自定义 widget 包装
                  icon: Icons.g_mobiledata,
                ),

                const SizedBox(height: 12),

                // ---- Apple 登录按钮（仅 iOS 平台显示）----
                if (defaultTargetPlatform == TargetPlatform.iOS)
                  AppButton(
                    label: 'Continue with Apple',
                    isOutlined: true,
                    isLoading: false,
                    onPressed: isLoading ? null : _signInWithApple,
                    icon: Icons.apple,
                  ),

                if (defaultTargetPlatform == TargetPlatform.iOS) const SizedBox(height: 12),

                const SizedBox(height: 28),

                // ---- 跳转注册页链接 ----
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    TextButton(
                      key: const ValueKey('login_signup_btn'),
                      onPressed: () => context.pushReplacement('/auth/register'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
