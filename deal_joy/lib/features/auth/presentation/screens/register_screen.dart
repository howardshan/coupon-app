import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../widgets/password_strength_indicator.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  // 各字段控制器
  final _usernameCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  // 用于实时监听密码强度和确认密码匹配
  String _passwordValue = '';
  String _confirmPasswordValue = '';

  // 服务条款是否勾选
  bool _tosAccepted = false;

  // 邮箱正则：标准 RFC-5322 简化版
  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  );

  // 用户名正则：只允许字母和数字
  static final _usernameRegex = RegExp(r'^[a-zA-Z0-9]+$');

  @override
  void initState() {
    super.initState();
    // 监听密码字段变化，用于实时更新强度指示器和确认密码校验
    _passwordCtrl.addListener(() {
      setState(() {
        _passwordValue = _passwordCtrl.text;
      });
    });
    // 监听确认密码字段变化，用于实时显示不匹配错误
    _confirmPasswordCtrl.addListener(() {
      setState(() {
        _confirmPasswordValue = _confirmPasswordCtrl.text;
      });
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // 注册按钮是否可用：表单合法 + 服务条款已勾选
  bool get _canSubmit => _tosAccepted;

  // 密码策略校验：最少 8 字符、含大写、小写、数字
  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'At least 8 characters required';
    if (!RegExp(r'[A-Z]').hasMatch(v)) {
      return 'Must contain at least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(v)) {
      return 'Must contain at least one lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(v)) {
      return 'Must contain at least one digit';
    }
    return null;
  }

  // 确认密码校验：必须与密码字段匹配
  String? _validateConfirmPassword(String? v) {
    if (v == null || v.isEmpty) return 'Please confirm your password';
    if (v != _passwordCtrl.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_tosAccepted) return;

    await ref.read(authNotifierProvider.notifier).signUp(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
          _fullNameCtrl.text.trim(),
          username: _usernameCtrl.text.trim(),
        );

    // signUp 成功后（无错误）显示验证邮件提示
    if (mounted) {
      final state = ref.read(authNotifierProvider);
      if (!state.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Verification email sent! Please check your inbox.',
            ),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState is AsyncLoading;

    // 监听 auth 状态，错误时弹出 SnackBar
    ref.listen(authNotifierProvider, (_, next) {
      if (next is AsyncError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    // 确认密码与密码字段是否实时不匹配（用于红色提示）
    final confirmMismatch = _confirmPasswordValue.isNotEmpty &&
        _confirmPasswordValue != _passwordValue;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 页面标题区
                Text(
                  'Join DealJoy',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Get the best local deals in Dallas',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 28),

                // ---- Username 字段 ----
                AppTextField(
                  controller: _usernameCtrl,
                  label: 'Username',
                  hint: 'e.g. john_doe123',
                  prefixIcon: const Icon(Icons.alternate_email, size: 20),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Username is required';
                    }
                    final trimmed = v.trim();
                    if (trimmed.length < 2) {
                      return 'At least 2 characters required';
                    }
                    if (trimmed.length > 30) {
                      return 'Maximum 30 characters allowed';
                    }
                    if (!_usernameRegex.hasMatch(trimmed)) {
                      return 'Only letters and numbers allowed';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ---- Full Name 字段 ----
                AppTextField(
                  controller: _fullNameCtrl,
                  label: 'Full Name',
                  hint: 'John Doe',
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Full name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ---- Email 字段 ----
                AppTextField(
                  controller: _emailCtrl,
                  label: 'Email',
                  hint: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: const Icon(Icons.email_outlined, size: 20),
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

                // ---- Password 字段 + 强度指示器 ----
                AppTextField(
                  controller: _passwordCtrl,
                  label: 'Password',
                  hint: '••••••••',
                  obscureText: true,
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  validator: _validatePassword,
                ),
                // 密码强度指示器（实时响应输入）
                PasswordStrengthIndicator(password: _passwordValue),
                const SizedBox(height: 16),

                // ---- Confirm Password 字段 ----
                AppTextField(
                  controller: _confirmPasswordCtrl,
                  label: 'Confirm Password',
                  hint: '••••••••',
                  obscureText: true,
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  validator: _validateConfirmPassword,
                ),
                // 实时不匹配红色提示（独立于表单 validate 触发时机）
                if (confirmMismatch)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'Passwords do not match',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                const SizedBox(height: 20),

                // ---- Terms of Service 复选框 ----
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _tosAccepted,
                        activeColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _tosAccepted = val ?? false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                          children: [
                            const TextSpan(text: 'I agree to the '),
                            TextSpan(
                              text: 'Terms of Service',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                              // 预留 Terms of Service 跳转（暂未实现）
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  // TODO: 跳转到服务条款页面
                                },
                            ),
                            const TextSpan(text: ' and '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                              // 预留隐私政策跳转（暂未实现）
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  // TODO: 跳转到隐私政策页面
                                },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ---- 注册按钮（未勾选 ToS 时禁用） ----
                AppButton(
                  label: 'Create Account',
                  isLoading: isLoading,
                  // 未勾选服务条款时传 null 使按钮呈禁用态
                  onPressed: _canSubmit ? _submit : null,
                ),
                const SizedBox(height: 20),

                // ---- 已有账号跳回登录 ----
                Center(
                  child: Text.rich(
                    TextSpan(
                      style: Theme.of(context).textTheme.bodyMedium,
                      children: [
                        TextSpan(
                          text: 'Already have an account? ',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        TextSpan(
                          text: 'Sign In',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => context.pop(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
