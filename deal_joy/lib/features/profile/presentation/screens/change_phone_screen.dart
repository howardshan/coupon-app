import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/domain/providers/auth_provider.dart';

/// 修改手机号页面
/// 显示当前手机号（只读）+ 新手机号输入框，保存到 users 表的 phone 字段
class ChangePhoneScreen extends ConsumerStatefulWidget {
  const ChangePhoneScreen({super.key});

  @override
  ConsumerState<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends ConsumerState<ChangePhoneScreen> {
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

  /// 验证手机号格式
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

  /// 提交保存新手机号
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      // 标准化为 +1XXXXXXXXXX 格式
      final rawPhone = _phoneCtrl.text.trim();
      final digits = rawPhone.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
      final normalized = digits.startsWith('1') && digits.length == 11
          ? digits.substring(1)
          : digits;
      final phone = '+1$normalized';

      final client = Supabase.instance.client;
      await client.from('users').update({
        'phone': phone,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);

      // 刷新用户信息
      ref.invalidate(currentUserProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phone number updated'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update phone number: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    // 获取当前手机号，过滤掉占位值 'skipped'
    final currentPhone = userAsync.valueOrNull?.phone;
    final hasPhone = currentPhone != null &&
        currentPhone.isNotEmpty &&
        currentPhone != 'skipped';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Change Phone Number'),
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
              // 当前手机号卡片（只读）
              if (hasPhone) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.textHint.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Phone Number',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentPhone,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // 新手机号输入框
              AppTextField(
                controller: _phoneCtrl,
                label: 'New Phone Number',
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
              const SizedBox(height: 8),

              // 格式提示
              Text(
                'Enter a 10-digit US phone number',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textHint,
                ),
              ),
              const SizedBox(height: 32),

              // 保存按钮
              AppButton(
                label: 'Save Phone Number',
                isLoading: _isLoading,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
