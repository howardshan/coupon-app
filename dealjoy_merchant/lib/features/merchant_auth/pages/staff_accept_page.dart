// 员工接受邀请页面
// 流程：输入邀请码 → 预览门店/角色信息 → 创建账号（或已登录直接接受）→ Dashboard

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../router/app_router.dart';

const _primaryOrange = Color(0xFFFF6B35);

class StaffAcceptPage extends StatefulWidget {
  const StaffAcceptPage({super.key, this.invitationId});

  /// 从 URL 参数传入的邀请 ID（可为 null，用户手动输入）
  final String? invitationId;

  @override
  State<StaffAcceptPage> createState() => _StaffAcceptPageState();
}

class _StaffAcceptPageState extends State<StaffAcceptPage> {
  // 步骤：0=输入邀请码，1=预览+操作
  int _step = 0;

  // 邀请信息
  final _codeCtrl = TextEditingController();
  bool _lookingUp = false;
  String? _lookupError;
  Map<String, dynamic>? _invitation;

  // 创建账号表单（仅未登录时显示）
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _passwordVisible = false;
  bool _submitting = false;
  String? _submitError;

  // 当前已登录用户
  User? get _currentUser => Supabase.instance.client.auth.currentUser;

  @override
  void initState() {
    super.initState();
    if (widget.invitationId != null) {
      _codeCtrl.text = widget.invitationId!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookupInvitation());
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ─── 查询邀请信息 ─────────────────────────────────────────────

  Future<void> _lookupInvitation() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _lookingUp = true;
      _lookupError = null;
    });
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'merchant-staff-mgmt/preview-invitation/$code',
        method: HttpMethod.get,
      );
      if (response.status == 200) {
        setState(() {
          _invitation = response.data as Map<String, dynamic>;
          _step = 1;
        });
      } else {
        final msg = (response.data as Map<String, dynamic>?)?['error'] as String?;
        setState(() => _lookupError = msg ?? 'Invitation not found or expired.');
      }
    } catch (e) {
      setState(() => _lookupError = 'Failed to look up invitation. Please try again.');
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  // ─── 接受邀请（已登录用户，直接用 session） ─────────────────────

  Future<void> _acceptWithCurrentSession() async {
    setState(() { _submitting = true; _submitError = null; });
    final invitationId = _invitation!['invitation_id'] as String;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'merchant-staff-mgmt/accept',
        method: HttpMethod.post,
        body: {'invitation_id': invitationId},
      );
      if (res.status != 200 && res.status != 201) {
        final msg = (res.data as Map<String, dynamic>?)?['error'] as String?;
        throw Exception(msg ?? 'Failed to accept invitation.');
      }
      if (!mounted) return;
      MerchantStatusCache.clear();
      context.go('/dashboard');
    } catch (e) {
      setState(() => _submitError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ─── 接受邀请（新账号：服务端创建用户） ─────────────────────────

  Future<void> _createAccountAndAccept() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _submitting = true; _submitError = null; });
    final invitationId = _invitation!['invitation_id'] as String;
    final client = Supabase.instance.client;
    try {
      // 把 email+password 传给 Edge Function，服务端创建用户（email_confirm=true）
      final acceptRes = await client.functions.invoke(
        'merchant-staff-mgmt/accept',
        method: HttpMethod.post,
        body: {
          'invitation_id': invitationId,
          'email': _emailCtrl.text.trim(),
          'password': _passwordCtrl.text,
        },
      );
      if (acceptRes.status != 200 && acceptRes.status != 201) {
        final data = acceptRes.data as Map<String, dynamic>?;
        if (data?['code'] == 'user_already_exists') {
          // 邮箱已注册 → 引导去登录页
          if (!mounted) return;
          context.go(
            '/auth/login?invitation_id=$invitationId',
          );
          return;
        }
        throw Exception(data?['error'] as String? ?? 'Failed to create account.');
      }
      // 账号已由服务端创建（email_confirm=true），直接登录
      await client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      MerchantStatusCache.clear();
      context.go('/dashboard');
    } on AuthException catch (e) {
      setState(() => _submitError = _friendlyError(e));
    } catch (e) {
      setState(() => _submitError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _friendlyError(AuthException e) {
    final code = e.code ?? e.message;
    if (code.contains('invalid_credentials')) return 'Incorrect email or password.';
    if (code.contains('email_not_confirmed')) return 'Please verify your email first.';
    if (code.contains('user_already_exists')) return 'An account with this email already exists.';
    if (code.contains('too_many_requests')) return 'Too many attempts. Please try again later.';
    return e.message;
  }

  String _roleLabel(String? role) {
    const labels = {
      'regional_manager': 'Regional Manager',
      'manager': 'Manager',
      'finance': 'Finance',
      'cashier': 'Cashier',
      'service': 'Service',
      'trainee': 'Trainee',
    };
    return labels[role] ?? (role ?? 'Staff');
  }

  // ─── UI ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text('Join as Staff'),
        leading: BackButton(onPressed: () {
          if (_step == 1) {
            setState(() { _step = 0; _invitation = null; });
          } else {
            context.go('/auth/login');
          }
        }),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: _step == 0 ? _buildStep0() : _buildStep1(),
        ),
      ),
    );
  }

  // ─── Step 0: 输入邀请码 ───────────────────────────────────────

  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: _primaryOrange.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person_add_outlined, size: 36, color: _primaryOrange),
        ),
        const SizedBox(height: 20),
        const Text(
          'Accept Staff Invitation',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the invitation code from your email to join a store as a staff member.',
          style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.5),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _codeCtrl,
          decoration: InputDecoration(
            labelText: 'Invitation Code',
            hintText: 'Paste the code from your email',
            border: const OutlineInputBorder(),
            suffixIcon: _lookingUp
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ),
          onSubmitted: (_) => _lookupInvitation(),
        ),
        if (_lookupError != null) ...[
          const SizedBox(height: 8),
          Text(_lookupError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _lookingUp ? null : _lookupInvitation,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryOrange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  // ─── Step 1: 预览邀请 + 操作 ──────────────────────────────────

  Widget _buildStep1() {
    final inv = _invitation!;
    final user = _currentUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 邀请卡片
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _primaryOrange.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _primaryOrange.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.storefront, color: _primaryOrange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    inv['store_name'] as String? ?? '',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              _invRow(Icons.badge_outlined, 'Role', _roleLabel(inv['role'] as String?)),
              const SizedBox(height: 4),
              _invRow(Icons.email_outlined, 'Invited to', inv['invited_email_masked'] as String? ?? ''),
            ],
          ),
        ),
        const SizedBox(height: 28),

        if (user != null) ...[
          // 已登录：显示当前账号并直接接受
          _buildLoggedInAccept(user),
        ] else ...[
          // 未登录：创建账号表单
          _buildCreateAccountForm(inv['invitation_id'] as String),
        ],
      ],
    );
  }

  // ─── 已登录：直接接受 ─────────────────────────────────────────

  Widget _buildLoggedInAccept(User user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(children: [
            const Icon(Icons.account_circle_outlined, color: Color(0xFF757575)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                user.email ?? '',
                style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Text(
          'You are signed in. Tap below to accept the invitation with this account.',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
        if (_submitError != null) ...[
          const SizedBox(height: 10),
          Text(_submitError!, style: const TextStyle(color: Colors.red, fontSize: 13), textAlign: TextAlign.center),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _submitting ? null : _acceptWithCurrentSession,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryOrange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _submitting
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Accept Invitation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  // ─── 未登录：创建账号 ─────────────────────────────────────────

  Widget _buildCreateAccountForm(String invitationId) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Create your account',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
          ),
          const SizedBox(height: 4),
          Text(
            'Use the email address this invitation was sent to.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              hintText: 'Must match the invitation email',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: !_passwordVisible,
            decoration: InputDecoration(
              labelText: 'Set Password',
              hintText: '••••••••',
              prefixIcon: const Icon(Icons.lock_outlined),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (v.length < 8) return 'At least 8 characters';
              return null;
            },
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 10),
            Text(_submitError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _submitting ? null : _createAccountAndAccept,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _submitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Create Account & Accept', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Already have an account?  ', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
              GestureDetector(
                onTap: () => context.go('/auth/login?invitation_id=$invitationId'),
                child: const Text(
                  'Sign In →',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryOrange),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _invRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 16, color: Colors.grey[600]),
      const SizedBox(width: 6),
      Text('$label: ', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
    ]);
  }
}
