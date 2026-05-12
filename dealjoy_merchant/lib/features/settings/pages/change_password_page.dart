// 商家端修改密码页
// 逻辑与用户端 ChangePasswordScreen 对齐：旧密码 signInWithPassword 校验身份后 updateUser
// 成功时先 pop 再在下一帧用根 ScaffoldMessenger 提示，避免与 SnackBar/Shell 重建叠帧导致「闪回改密页」

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../router/app_router.dart';

const _primaryOrange = Color(0xFFFF6B35);

/// 修改登录密码（Supabase Auth，与客户端同一套凭证）
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _oldVisible = false;
  bool _newVisible = false;
  bool _confirmVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  void _clearError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  @override
  void initState() {
    super.initState();
    _oldPasswordCtrl.addListener(_clearError);
    _newPasswordCtrl.addListener(_clearError);
    _confirmPasswordCtrl.addListener(_clearError);
  }

  @override
  void dispose() {
    _oldPasswordCtrl.removeListener(_clearError);
    _newPasswordCtrl.removeListener(_clearError);
    _confirmPasswordCtrl.removeListener(_clearError);
    _oldPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  String _friendlyPasswordError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login') || lower.contains('invalid credentials')) {
      return 'Current password is incorrect.';
    }
    if (lower.contains('same password') || lower.contains('different password')) {
      return 'New password must be different from your current password.';
    }
    if (lower.contains('rate limit') || lower.contains('too many requests')) {
      return 'Too many attempts. Please try again later.';
    }
    if (lower.contains('weak') || lower.contains('too short')) {
      return 'Password is too weak. Please choose a stronger one.';
    }
    if (lower.contains('network') || lower.contains('connection')) {
      return 'Network error. Please check your connection.';
    }
    return 'Failed to update password. Please try again.';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    var didPopForSuccess = false;
    try {
      final client = Supabase.instance.client;
      final email = client.auth.currentUser?.email;

      if (email == null) {
        if (mounted) {
          setState(() => _errorMessage = 'Unable to identify current user. Please log in again.');
        }
        return;
      }

      await client.auth.signInWithPassword(
        email: email,
        password: _oldPasswordCtrl.text,
      );

      await client.auth.updateUser(
        UserAttributes(password: _newPasswordCtrl.text),
      );

      if (!mounted) return;
      // 先关闭子路由，再在下一帧用根 navigator 的 SnackBar，避免与当前页 dispose 冲突
      context.pop();
      didPopForSuccess = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final rootCtx = merchantAppRootNavigatorKey.currentContext;
        if (rootCtx == null || !rootCtx.mounted) return;
        ScaffoldMessenger.of(rootCtx).showSnackBar(
          const SnackBar(
            content: Text('Password updated successfully!'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyPasswordError(e.message));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      // 成功并已 pop 时不再 setState，避免在 dispose 边界重建当前页
      if (mounted && !didPopForSuccess) {
        setState(() => _isLoading = false);
      }
    }
  }

  String? _validateNewPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a new password';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain at least one number';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\\/~`]').hasMatch(value)) {
      return 'Password must contain at least one special character (!@#\$%...)';
    }
    return null;
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required IconData prefixIcon,
    required bool visible,
    required VoidCallback onToggleVisibility,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(prefixIcon),
      suffixIcon: IconButton(
        icon: Icon(
          visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
        onPressed: onToggleVisibility,
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Change Password'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF90CAF9).withValues(alpha: 0.5)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF1565C0), size: 22),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Enter your current password to verify your identity, then set a new password.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF424242),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _oldPasswordCtrl,
                obscureText: !_oldVisible,
                decoration: _fieldDecoration(
                  label: 'Current Password',
                  hint: 'Enter your current password',
                  prefixIcon: Icons.lock_outlined,
                  visible: _oldVisible,
                  onToggleVisibility: () => setState(() => _oldVisible = !_oldVisible),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'Please enter your current password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newPasswordCtrl,
                obscureText: !_newVisible,
                decoration: _fieldDecoration(
                  label: 'New Password',
                  hint: 'At least 8 chars, mixed case, number & symbol',
                  prefixIcon: Icons.lock_reset_outlined,
                  visible: _newVisible,
                  onToggleVisibility: () => setState(() => _newVisible = !_newVisible),
                ),
                validator: _validateNewPassword,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordCtrl,
                obscureText: !_confirmVisible,
                decoration: _fieldDecoration(
                  label: 'Confirm New Password',
                  hint: 'Re-enter your new password',
                  prefixIcon: Icons.lock_outlined,
                  visible: _confirmVisible,
                  onToggleVisibility: () =>
                      setState(() => _confirmVisible = !_confirmVisible),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'Please confirm your new password';
                  }
                  if (v != _newPasswordCtrl.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, size: 18, color: Color(0xFFC62828)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFC62828),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Update Password',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
