// 修改邮箱页面 — 两步：输入新邮箱 → 邮件内确认链接（与 Supabase 默认换绑邮件一致）
// 深度链接须与 Authentication → URL Configuration 中的 Redirect URLs 白名单一致

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/domain/providers/auth_provider.dart';

/// 与 auth_repository 中 OAuth / 密码重置一致，便于 Supabase 回调打开 App
const _emailChangeRedirectTo = 'io.supabase.dealjoy://login-callback/';

class ChangeEmailScreen extends ConsumerStatefulWidget {
  const ChangeEmailScreen({super.key});

  @override
  ConsumerState<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends ConsumerState<ChangeEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newEmailCtrl = TextEditingController();

  late final String _currentEmail;
  late final TextEditingController _currentEmailCtrl;

  bool _isLoading = false;
  String? _errorMessage;

  /// false = 输入邮箱；true = 已发送确认邮件，等待用户点击邮件内链接
  bool _confirmationEmailSent = false;
  bool _emailChangeCompleted = false;

  StreamSubscription<AuthState>? _authSub;

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
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _newEmailCtrl.removeListener(_clearError);
    _newEmailCtrl.dispose();
    _currentEmailCtrl.dispose();
    super.dispose();
  }

  /// 监听会话：用户在新邮箱点击确认链接后，Supabase 会通过深度链接刷新 session，email 即变为新地址
  void _startListeningForConfirmedEmail() {
    _authSub?.cancel();
    _authSub =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      if (!mounted || !_confirmationEmailSent || _emailChangeCompleted) {
        return;
      }
      final target = _newEmailCtrl.text.trim().toLowerCase();
      if (target.isEmpty) return;
      final got = user?.email?.toLowerCase();
      if (got == target) {
        _emailChangeCompleted = true;
        unawaited(_persistNewEmailAndFinish(newEmail: target));
      }
    });
  }

  /// 第一步：请求换绑，服务端向新邮箱发送「确认链接」邮件（非数字验证码）
  Future<void> _sendConfirmationEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(email: _newEmailCtrl.text.trim()),
        emailRedirectTo: _emailChangeRedirectTo,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _confirmationEmailSent = true;
          _emailChangeCompleted = false;
        });
        _startListeningForConfirmedEmail();
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

  /// 将 auth 侧已生效的新邮箱写入 public.users，与 currentUserProvider 一致
  Future<void> _persistNewEmailAndFinish({required String newEmail}) async {
    _authSub?.cancel();
    _authSub = null;

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client.from('users').update({
          'email': newEmail,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);
      }

      ref.invalidate(currentUserProvider);

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email updated successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Email was confirmed but profile sync failed. Pull to refresh or contact support.';
        });
      }
    }
  }

  String _friendlyEmailError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('already registered') ||
        lower.contains('already been registered')) {
      return 'This email address is already registered.';
    }
    if (lower.contains('rate limit') || lower.contains('too many')) {
      return 'Too many attempts. Please try again later.';
    }
    if (lower.contains('invalid') && lower.contains('email')) {
      return 'Please enter a valid email address.';
    }
    return 'Failed to send confirmation email. Please try again.';
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
          child: _confirmationEmailSent
              ? _buildConfirmLinkStep()
              : _buildEmailStep(),
        ),
      ),
    );
  }

  /// 第一步 UI：输入新邮箱
  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              borderSide:
                  BorderSide(color: AppColors.textHint.withValues(alpha: 0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide:
                  BorderSide(color: AppColors.textHint.withValues(alpha: 0.5)),
            ),
          ),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),

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

        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.error_outline, size: 16, color: AppColors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_errorMessage!,
                    style:
                        const TextStyle(fontSize: 13, color: AppColors.error)),
              ),
            ],
          ),
        ],
        const SizedBox(height: 32),

        AppButton(
          label: 'Send Confirmation Email',
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _sendConfirmationEmail,
        ),

        const SizedBox(height: 16),
        Text(
          'We will email a confirmation link to your new address. '
          'Tap the link in that email to finish (it opens this app).',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary.withValues(alpha: 0.8),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// 第二步 UI：说明使用邮件链接，而非输入验证码
  Widget _buildConfirmLinkStep() {
    return Column(
      children: [
        const SizedBox(height: 20),
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
        const Text(
          'Confirm in your inbox',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          'We sent a link to\n${_newEmailCtrl.text.trim()}\n\n'
          'Open the email and tap the confirmation link (e.g. "Change Email"). '
          'It should open DealJoy and complete the update.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 14, color: AppColors.textSecondary, height: 1.5),
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 16, color: AppColors.error),
              const SizedBox(width: 6),
              Flexible(
                child: Text(_errorMessage!,
                    style:
                        const TextStyle(fontSize: 13, color: AppColors.error)),
              ),
            ],
          ),
        ],

        const SizedBox(height: 28),
        AppButton(
          label: "I've tapped the link",
          isLoading: _isLoading,
          onPressed: _isLoading
              ? null
              : () {
                  final user = Supabase.instance.client.auth.currentUser;
                  final target = _newEmailCtrl.text.trim().toLowerCase();
                  if (user?.email?.toLowerCase() == target) {
                    unawaited(_persistNewEmailAndFinish(newEmail: target));
                  } else {
                    setState(() => _errorMessage =
                        'Not updated yet. Tap the link in the email, then return here.');
                  }
                },
        ),

        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _isLoading ? null : _sendConfirmationEmail,
              child: const Text('Resend email',
                  style: TextStyle(color: AppColors.primary, fontSize: 14)),
            ),
            const Text('·', style: TextStyle(color: AppColors.textHint)),
            TextButton(
              onPressed: () {
                _authSub?.cancel();
                _authSub = null;
                setState(() {
                  _confirmationEmailSent = false;
                  _emailChangeCompleted = false;
                  _errorMessage = null;
                });
              },
              child: const Text('Change email address',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            ),
          ],
        ),
      ],
    );
  }
}
