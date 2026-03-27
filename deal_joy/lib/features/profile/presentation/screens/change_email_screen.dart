// 修改邮箱页面 — 两步流程：输入新邮箱 → 填写验证码

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _otpCtrl = TextEditingController();

  late final String _currentEmail;
  late final TextEditingController _currentEmailCtrl;

  bool _isLoading = false;
  String? _errorMessage;

  // 两步状态：false = 输入邮箱，true = 输入验证码
  bool _otpSent = false;

  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  );

  @override
  void initState() {
    super.initState();
    _currentEmail =
        Supabase.instance.client.auth.currentUser?.email ?? '';
    _currentEmailCtrl = TextEditingController(text: _currentEmail);
    _newEmailCtrl.addListener(_clearError);
    _otpCtrl.addListener(_clearError);
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  @override
  void dispose() {
    _newEmailCtrl.removeListener(_clearError);
    _otpCtrl.removeListener(_clearError);
    _newEmailCtrl.dispose();
    _otpCtrl.dispose();
    _currentEmailCtrl.dispose();
    super.dispose();
  }

  /// 第一步：发送验证码到新邮箱
  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 调用 updateUser 触发 Supabase 向新邮箱发送验证码
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(email: _newEmailCtrl.text.trim()),
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _otpSent = true;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = _friendlyEmailError(e.message);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  /// 第二步：验证 OTP 并完成邮箱更换
  Future<void> _verifyOtp() async {
    final code = _otpCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'Please enter the verification code');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final newEmail = _newEmailCtrl.text.trim();

      // 验证 OTP（email_change 类型）
      await Supabase.instance.client.auth.verifyOTP(
        email: newEmail,
        token: code,
        type: OtpType.emailChange,
      );

      // 同步更新 users 表
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client.from('users').update({
          'email': newEmail,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);
      }

      ref.invalidate(currentUserProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email updated successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = _friendlyOtpError(e.message);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Verification failed. Please try again.';
        });
      }
    }
  }

  String _friendlyEmailError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('already registered') || lower.contains('already been registered')) {
      return 'This email address is already registered.';
    }
    if (lower.contains('rate limit') || lower.contains('too many')) {
      return 'Too many attempts. Please try again later.';
    }
    if (lower.contains('invalid') && lower.contains('email')) {
      return 'Please enter a valid email address.';
    }
    return 'Failed to send verification code. Please try again.';
  }

  String _friendlyOtpError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('expired') || lower.contains('invalid')) {
      return 'Invalid or expired code. Please try again.';
    }
    if (lower.contains('rate limit') || lower.contains('too many')) {
      return 'Too many attempts. Please wait and try again.';
    }
    return 'Verification failed. Please try again.';
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
          child: _otpSent ? _buildOtpStep() : _buildEmailStep(),
        ),
      ),
    );
  }

  /// 第一步 UI：输入新邮箱
  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 当前邮箱（只读）
        const Text('Current Email',
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        const SizedBox(height: 6),
        TextFormField(
          controller: _currentEmailCtrl,
          readOnly: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceVariant,
            border: const OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.textHint.withValues(alpha: 0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.textHint.withValues(alpha: 0.5)),
            ),
          ),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),

        // 新邮箱输入
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
            if (value.trim().toLowerCase() == _currentEmail.toLowerCase()) {
              return 'New email must be different from current email';
            }
            return null;
          },
        ),

        // 内联错误
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.error_outline, size: 16, color: AppColors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_errorMessage!,
                    style: const TextStyle(fontSize: 13, color: AppColors.error)),
              ),
            ],
          ),
        ],
        const SizedBox(height: 32),

        // 发送验证码按钮
        AppButton(
          label: 'Send Verification Code',
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _sendOtp,
        ),

        const SizedBox(height: 16),
        Text(
          'A verification code will be sent to your new email address.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary.withValues(alpha: 0.8),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// 第二步 UI：输入验证码
  Widget _buildOtpStep() {
    return Column(
      children: [
        const SizedBox(height: 20),

        // 邮件图标
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.mark_email_read_outlined,
              size: 32, color: AppColors.primary),
        ),
        const SizedBox(height: 20),

        const Text('Enter Verification Code',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(
          'We sent a code to\n${_newEmailCtrl.text.trim()}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 28),

        // 验证码输入框
        TextField(
          controller: _otpCtrl,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: 6,
            color: AppColors.textPrimary,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: InputDecoration(
            hintText: 'Enter code',
            hintStyle: TextStyle(
              fontSize: 18, fontWeight: FontWeight.normal,
              letterSpacing: 0, color: AppColors.textHint,
            ),
            filled: true,
            fillColor: AppColors.surfaceVariant,
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),

        // 错误提示
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 16, color: AppColors.error),
              const SizedBox(width: 6),
              Flexible(
                child: Text(_errorMessage!,
                    style: const TextStyle(fontSize: 13, color: AppColors.error)),
              ),
            ],
          ),
        ],

        const SizedBox(height: 28),

        // 验证按钮
        AppButton(
          label: 'Verify & Update Email',
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _verifyOtp,
        ),

        const SizedBox(height: 12),

        // 重发 + 返回修改
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _isLoading ? null : _sendOtp,
              child: const Text('Resend Code',
                  style: TextStyle(color: AppColors.primary, fontSize: 14)),
            ),
            const Text('·', style: TextStyle(color: AppColors.textHint)),
            TextButton(
              onPressed: () => setState(() {
                _otpSent = false;
                _otpCtrl.clear();
                _errorMessage = null;
              }),
              child: const Text('Change Email',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            ),
          ],
        ),
      ],
    );
  }
}
