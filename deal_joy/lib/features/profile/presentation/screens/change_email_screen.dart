import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/domain/providers/auth_provider.dart';

class ChangeEmailScreen extends ConsumerStatefulWidget {
  const ChangeEmailScreen({super.key});

  @override
  ConsumerState<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends ConsumerState<ChangeEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newEmailCtrl = TextEditingController();

  // 当前邮箱（只读展示）
  late final String _currentEmail;
  late final TextEditingController _currentEmailCtrl;

  bool _isLoading = false;
  String? _errorMessage;

  // 邮箱正则校验规则
  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  );

  @override
  void initState() {
    super.initState();
    // 初始化当前邮箱（只读）
    _currentEmail =
        Supabase.instance.client.auth.currentUser?.email ?? '';
    _currentEmailCtrl = TextEditingController(text: _currentEmail);
    // 用户输入时清除错误提示
    _newEmailCtrl.addListener(_clearError);
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  @override
  void dispose() {
    _newEmailCtrl.removeListener(_clearError);
    _newEmailCtrl.dispose();
    _currentEmailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Change Email'),
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
              // 当前邮箱（只读，灰色背景提示）
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Email',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _currentEmailCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: 'Current email',
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.textHint.withValues(alpha: 0.5),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.textHint.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 新邮箱输入框
              AppTextField(
                controller: _newEmailCtrl,
                label: 'New Email',
                hint: 'Enter your new email address',
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a new email address';
                  }
                  if (!_emailRegex.hasMatch(value.trim())) {
                    return 'Please enter a valid email address';
                  }
                  if (value.trim().toLowerCase() ==
                      _currentEmail.toLowerCase()) {
                    return 'New email must be different from current email';
                  }
                  return null;
                },
              ),

              // 内联错误提示
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
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
              const SizedBox(height: 32),

              // 提交按钮
              AppButton(
                label: 'Update Email',
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _submit,
              ),

              const SizedBox(height: 16),

              // 提示说明文字
              Text(
                'A verification email will be sent to your new address. '
                'You must verify it before the change takes effect.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 将 Supabase AuthException 转为用户友好提示
  String _friendlyEmailError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('already registered') || lower.contains('already been registered')) {
      return 'This email address is already registered.';
    }
    if (lower.contains('rate limit') || lower.contains('too many requests')) {
      return 'Too many attempts. Please try again later.';
    }
    if (lower.contains('invalid') && lower.contains('email')) {
      return 'Please enter a valid email address.';
    }
    if (lower.contains('network') || lower.contains('connection')) {
      return 'Network error. Please check your connection.';
    }
    return 'Failed to update email. Please try again.';
  }

  Future<void> _submit() async {
    // 表单验证
    if (!_formKey.currentState!.validate()) return;

    final newEmail = _newEmailCtrl.text.trim();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      // 更新 Supabase Auth 邮箱（会触发验证邮件）
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(email: newEmail),
      );

      // 同步更新 users 表的 email 字段
      await Supabase.instance.client.from('users').update({
        'email': newEmail,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      // 刷新当前用户数据缓存
      ref.invalidate(currentUserProvider);

      if (!mounted) return;

      // 成功提示并返回上一页
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Verification email sent to your new address. Please check your inbox.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyEmailError(e.message);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
