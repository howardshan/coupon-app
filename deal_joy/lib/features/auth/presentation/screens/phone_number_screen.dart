import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/providers/auth_provider.dart';

/// 注册完成后的手机号填写页面
/// 用户首次登录且没有手机号时，路由会自动跳转到此页面
class PhoneNumberScreen extends ConsumerStatefulWidget {
  const PhoneNumberScreen({super.key});

  @override
  ConsumerState<PhoneNumberScreen> createState() => _PhoneNumberScreenState();
}

class _PhoneNumberScreenState extends ConsumerState<PhoneNumberScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  bool _isLoading = false;

  // 北美手机号正则：10 位数字（去掉格式符号后）
  static final _phoneDigitsRegex = RegExp(r'^\d{10}$');

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  String? _validatePhone(String? v) {
    if (v == null || v.trim().isEmpty) {
      return 'Phone number is required';
    }
    // 提取纯数字
    final digits = v.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    // 如果以 1 开头且 11 位，去掉国家码
    final normalized = digits.startsWith('1') && digits.length == 11
        ? digits.substring(1)
        : digits;
    if (!_phoneDigitsRegex.hasMatch(normalized)) {
      return 'Please enter a valid 10-digit phone number';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final rawPhone = _phoneCtrl.text.trim();
      // 标准化为 +1XXXXXXXXXX 格式
      final digits = rawPhone.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
      final normalized = digits.startsWith('1') && digits.length == 11
          ? digits.substring(1)
          : digits;
      final phone = '+1$normalized';

      final client = Supabase.instance.client;
      final userId = client.auth.currentUser!.id;

      await client.from('users').update({
        'phone': phone,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      // 刷新 currentUserProvider 使路由重新检查
      ref.invalidate(currentUserProvider);

      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save phone number: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _skip() async {
    // 跳过时写入占位值，避免每次登录都弹出
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser!.id;
      await client.from('users').update({
        'phone': 'skipped',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    } catch (_) {
      // 即使写入失败也允许跳过
    }
    ref.invalidate(currentUserProvider);
    if (mounted) {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),

                // 图标
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.phone_android,
                      size: 40,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // 标题
                Center(
                  child: Text(
                    'Add Your Phone Number',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'We\'ll use this to send you order updates\nand important notifications.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                  ),
                ),
                const SizedBox(height: 36),

                // 手机号输入框
                AppTextField(
                  controller: _phoneCtrl,
                  label: 'Phone Number',
                  hint: '(214) 555-0123',
                  keyboardType: TextInputType.phone,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 12, right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🇺🇸 +1', style: TextStyle(fontSize: 14)),
                        SizedBox(width: 4),
                        SizedBox(
                          height: 20,
                          child: VerticalDivider(width: 1, thickness: 1),
                        ),
                      ],
                    ),
                  ),
                  validator: _validatePhone,
                ),
                const SizedBox(height: 32),

                // 保存按钮
                AppButton(
                  label: 'Continue',
                  isLoading: _isLoading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 16),

                // 跳过按钮
                Center(
                  child: TextButton(
                    onPressed: _isLoading ? null : _skip,
                    child: Text(
                      'Skip for now',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
