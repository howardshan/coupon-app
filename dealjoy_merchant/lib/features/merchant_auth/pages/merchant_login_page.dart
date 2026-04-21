// 商家登录页
// 邮箱 + 密码登录，或 iOS 上 Apple 登录；成功后根据 merchant 状态跳转：
//   无记录 → /auth/register
//   pending/rejected → /auth/review
//   approved → /dashboard

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../router/app_router.dart';
import '../providers/merchant_auth_provider.dart';

const _primaryOrange = Color(0xFFFF6B35);

class MerchantLoginPage extends ConsumerStatefulWidget {
  const MerchantLoginPage({super.key});

  @override
  ConsumerState<MerchantLoginPage> createState() => _MerchantLoginPageState();
}

class _MerchantLoginPageState extends ConsumerState<MerchantLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _passwordVisible = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// 邮箱密码或 Apple 登录成功后：校验角色与 merchant 状态并跳转。
  Future<void> _continueAfterAuthenticatedSession() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      if (mounted) context.go('/dashboard');
      return;
    }

    final roleRow = await client
        .from('users')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    final role = roleRow?['role'] as String?;
    if (role != 'merchant' && role != 'admin') {
      await client.auth.signOut();
      if (!mounted) return;
      setState(() => _error = 'Your account is not a merchant account.');
      return;
    }

    if (role == 'admin') {
      final brandAdmin = await client
          .from('brand_admins')
          .select('brand_id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (brandAdmin == null) {
        await client.auth.signOut();
        setState(() => _error = 'Your account is not a merchant account.');
        return;
      }
      MerchantStatusCache.setStatus('approved', user.id, roleType: 'brand_admin');
      context.go('/store-selector');
      return;
    }

    final data = await client
        .from('merchants')
        .select('status')
        .eq('user_id', user.id)
        .maybeSingle();

    if (!mounted) return;

    if (data == null) {
      context.go('/auth/register');
      return;
    }
    if (data['status'] == 'approved') {
      MerchantStatusCache.setStatus('approved', user.id);
      context.go('/dashboard');
    } else {
      MerchantStatusCache.setStatus(
        data['status'] as String? ?? 'pending',
        user.id,
      );
      context.go('/auth/review');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      await _continueAfterAuthenticatedSession();
    } on AuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e));
    } catch (_) {
      setState(() => _error = 'Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(merchantAuthServiceProvider).signInWithApple();
      if (!mounted) return;
      await _continueAfterAuthenticatedSession();
    } on AuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e));
    } catch (_) {
      setState(() => _error = 'Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyAuthError(AuthException e) {
    final code = e.code ?? e.message;
    if (code.contains('invalid_credentials') ||
        code.contains('Invalid login credentials')) {
      return 'No account found with this email, or the password is incorrect.';
    }
    if (code.contains('email_not_confirmed')) {
      return 'Please verify your email before signing in.';
    }
    if (code.contains('too_many_requests')) {
      return 'Too many attempts. Please try again later.';
    }
    if (e.message.contains('Apple sign in cancelled')) {
      return 'Apple sign in was cancelled.';
    }
    return e.message;
  }

  @override
  Widget build(BuildContext context) {
    final showApple = defaultTargetPlatform == TargetPlatform.iOS;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                const Icon(Icons.storefront, size: 64, color: _primaryOrange),
                const SizedBox(height: 16),
                const Text(
                  'Welcome back',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in to your merchant account',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Color(0xFF757575)),
                ),
                const SizedBox(height: 40),

                TextFormField(
                  key: const ValueKey('login_email_field'),
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'you@business.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Email is required';
                    }
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  key: const ValueKey('login_password_field'),
                  controller: _passwordCtrl,
                  obscureText: !_passwordVisible,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: '••••••••',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_passwordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Password is required' : null,
                ),
                const SizedBox(height: 16),

                if (showApple) ...[
                  Row(
                    children: [
                      const Expanded(child: Divider(thickness: 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider(thickness: 1)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    key: const ValueKey('login_apple_btn'),
                    onPressed: _loading ? null : _signInWithApple,
                    icon: const Icon(Icons.apple, size: 22),
                    label: const Text('Continue with Apple'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A1A2E),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 24),

                ElevatedButton(
                  key: const ValueKey('login_submit_btn'),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Sign In',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Don't have an account? ",
                      style: TextStyle(color: Color(0xFF757575)),
                    ),
                    GestureDetector(
                      onTap: () => context.go('/auth/register'),
                      child: const Text(
                        'Register',
                        style: TextStyle(
                          color: _primaryOrange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
