import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../widgets/password_strength_indicator.dart';
import '../../../../shared/widgets/legal_document_screen.dart';
import '../../../../shared/providers/legal_provider.dart';

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

  // 生日
  DateTime? _dateOfBirth;

  // 服务条款是否勾选
  bool _tosAccepted = false;

  // 邮箱查重状态: null=未检查, true=已占用, false=可用
  bool? _emailTaken;
  bool _emailChecking = false;
  Timer? _emailDebounce;

  // Username 查重状态: null=未检查, true=已占用, false=可用
  bool? _usernameTaken;
  bool _usernameChecking = false;
  Timer? _usernameDebounce;

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
    // 监听邮箱变化，防抖查重
    _emailCtrl.addListener(_onEmailChanged);
    // 监听用户名变化，防抖查重
    _usernameCtrl.addListener(_onUsernameChanged);
  }

  // 邮箱输入变化时，防抖 500ms 后查询是否已被注册
  void _onEmailChanged() {
    _emailDebounce?.cancel();
    final trimmed = _emailCtrl.text.trim();
    if (!_emailRegex.hasMatch(trimmed)) {
      setState(() {
        _emailTaken = null;
        _emailChecking = false;
      });
      return;
    }
    setState(() => _emailChecking = true);
    _emailDebounce = Timer(const Duration(milliseconds: 500), () async {
      final taken = await ref
          .read(authRepositoryProvider)
          .isEmailTaken(trimmed);
      if (mounted && _emailCtrl.text.trim() == trimmed) {
        setState(() {
          _emailTaken = taken;
          _emailChecking = false;
        });
      }
    });
  }

  // 用户名输入变化时，防抖 500ms 后查询是否已被占用
  void _onUsernameChanged() {
    _usernameDebounce?.cancel();
    final trimmed = _usernameCtrl.text.trim();
    // 不满足基本格式要求时重置状态
    if (trimmed.length < 2 || !_usernameRegex.hasMatch(trimmed)) {
      setState(() {
        _usernameTaken = null;
        _usernameChecking = false;
      });
      return;
    }
    setState(() => _usernameChecking = true);
    _usernameDebounce = Timer(const Duration(milliseconds: 500), () async {
      final taken = await ref
          .read(authRepositoryProvider)
          .isUsernameTaken(trimmed);
      if (mounted && _usernameCtrl.text.trim() == trimmed) {
        setState(() {
          _usernameTaken = taken;
          _usernameChecking = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _emailDebounce?.cancel();
    _emailCtrl.removeListener(_onEmailChanged);
    _usernameDebounce?.cancel();
    _usernameCtrl.removeListener(_onUsernameChanged);
    _usernameCtrl.dispose();
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // 注册按钮是否可用：表单合法 + 生日满 18 岁 + 服务条款已勾选
  bool get _canSubmit {
    if (!_tosAccepted) return false;
    if (_dateOfBirth == null) return false;
    final age = DateTime.now().difference(_dateOfBirth!).inDays ~/ 365;
    if (age < 18) return false;
    return true;
  }

  // 密码策略校验：最少 8 字符、含大写、小写、数字、符号
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
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\\/~`]').hasMatch(v)) {
      return 'Must contain at least one special character (!@#\$%...)';
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
    if (_usernameTaken == true || _usernameChecking) return;
    if (_emailTaken == true || _emailChecking) return;

    // 验证生日已填写且满 18 岁
    if (_dateOfBirth == null) return;
    final age = DateTime.now().difference(_dateOfBirth!).inDays ~/ 365;
    if (age < 18) return;

    await ref.read(authNotifierProvider.notifier).signUp(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
          _fullNameCtrl.text.trim(),
          username: _usernameCtrl.text.trim(),
          dateOfBirth: _dateOfBirth!.toIso8601String().split('T').first,
        );

    if (mounted) {
      final state = ref.read(authNotifierProvider);
      if (state.hasError) {
        // 邮箱已注册错误 → 设置状态并刷新表单
        final errMsg = state.error.toString();
        if (errMsg.contains('already registered')) {
          setState(() => _emailTaken = true);
          _formKey.currentState!.validate();
        }
      } else {
        // signUp 成功：记录用户对法律文档的同意（不阻塞注册流程）
        try {
          final legalRepo = ref.read(legalRepositoryProvider);
          await legalRepo.recordConsent(
            documentSlug: 'terms-of-service',
            consentMethod: 'registration',
            triggerContext: 'registration',
          );
          await legalRepo.recordConsent(
            documentSlug: 'privacy-policy',
            consentMethod: 'registration',
            triggerContext: 'registration',
          );
        } catch (_) {
          // 不阻塞注册流程
        }

        // 登出 session，跳转到 OTP 验证码页面
        await ref.read(authNotifierProvider.notifier).signOut();

        if (mounted) {
          context.pushReplacement(
            '/auth/verify-otp?email=${Uri.encodeComponent(_emailCtrl.text.trim())}',
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState is AsyncLoading;

    // 监听 auth 状态，非邮箱重复的错误用 SnackBar 提示
    ref.listen(authNotifierProvider, (_, next) {
      if (next is AsyncError) {
        final errMsg = next.error.toString();
        // 邮箱重复错误已在 email 字段下方显示，不再弹 SnackBar
        if (errMsg.contains('already registered')) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errMsg),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.go('/auth/login'),
        ),
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
                  'Join Crunchy Plum',
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
                  key: const ValueKey('register_username_field'),
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
                    if (_usernameTaken == true) {
                      return 'This username is already taken';
                    }
                    return null;
                  },
                ),
                // 用户名查重实时状态提示
                if (_usernameChecking)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Checking availability...',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_usernameTaken == false)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 14, color: AppColors.success),
                        SizedBox(width: 4),
                        Text(
                          'Username is available',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_usernameTaken == true)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Row(
                      children: [
                        Icon(Icons.cancel, size: 14, color: AppColors.error),
                        SizedBox(width: 4),
                        Text(
                          'This username is already taken',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // ---- Full Name 字段 ----
                AppTextField(
                  key: const ValueKey('register_full_name_field'),
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

                // ---- Date of Birth 字段 ----
                GestureDetector(
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dateOfBirth ?? DateTime(now.year - 18, now.month, now.day),
                      firstDate: DateTime(1900),
                      lastDate: now,
                      helpText: 'SELECT YOUR DATE OF BIRTH',
                    );
                    if (picked != null) {
                      setState(() => _dateOfBirth = picked);
                    }
                  },
                  child: AbsorbPointer(
                    child: TextFormField(
                      key: const ValueKey('register_dob_field'),
                      decoration: InputDecoration(
                        labelText: 'Date of Birth',
                        hintText: 'MM/DD/YYYY',
                        prefixIcon: const Icon(Icons.cake_outlined, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      controller: TextEditingController(
                        text: _dateOfBirth != null
                            ? '${_dateOfBirth!.month.toString().padLeft(2, '0')}/${_dateOfBirth!.day.toString().padLeft(2, '0')}/${_dateOfBirth!.year}'
                            : '',
                      ),
                      validator: (_) {
                        if (_dateOfBirth == null) {
                          return 'Date of birth is required';
                        }
                        final age = DateTime.now().difference(_dateOfBirth!).inDays ~/ 365;
                        if (age < 18) {
                          return 'You must be at least 18 years old to register';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                // 未满 18 岁警告
                if (_dateOfBirth != null &&
                    DateTime.now().difference(_dateOfBirth!).inDays ~/ 365 < 18)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.error),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'You must be at least 18 years old to use Crunchy Plum.',
                            style: TextStyle(fontSize: 12, color: AppColors.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // ---- Email 字段 ----
                AppTextField(
                  key: const ValueKey('register_email_field'),
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
                    if (_emailTaken == true) {
                      return 'This email is already registered';
                    }
                    return null;
                  },
                ),
                // 邮箱查重实时状态提示
                if (_emailChecking)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Checking availability...',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_emailTaken == false)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 14, color: AppColors.success),
                        SizedBox(width: 4),
                        Text(
                          'Email is available',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_emailTaken == true)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Row(
                      children: [
                        Icon(Icons.cancel, size: 14, color: AppColors.error),
                        SizedBox(width: 4),
                        Text(
                          'This email is already registered',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // ---- Password 字段 + 强度指示器 ----
                AppTextField(
                  key: const ValueKey('register_password_field'),
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
                  key: const ValueKey('register_confirm_password_field'),
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
                                  // 跳转到服务条款页面
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const LegalDocumentScreen(
                                        slug: 'terms-of-service',
                                        title: 'Terms of Service',
                                      ),
                                    ),
                                  );
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
                                  // 跳转到隐私政策页面
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const LegalDocumentScreen(
                                        slug: 'privacy-policy',
                                        title: 'Privacy Policy',
                                      ),
                                    ),
                                  );
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
                            ..onTap = () => context.pushReplacement('/auth/login'),
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
