import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../../../core/errors/app_exception.dart';
import '../models/user_model.dart';

class AuthRepository {
  final sb.SupabaseClient _client;

  AuthRepository(this._client);

  Stream<sb.AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  sb.User? get currentUser => _client.auth.currentUser;

  // ---- 邮箱密码登录 ----
  Future<UserModel> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user == null) {
        throw const AppAuthException('Invalid email or password');
      }
      return _fetchUserProfile(response.user!.id);
    } on sb.AuthException catch (e) {
      // 区分"邮箱未验证"和"凭证错误"，其他统一为通用消息
      final msg = e.message.toLowerCase();
      if (msg.contains('email not confirmed') ||
          msg.contains('not confirmed')) {
        throw const AppAuthException(
          'Please verify your email before signing in. Check your inbox for the verification link.',
          code: 'email_not_confirmed',
        );
      }
      throw const AppAuthException('Invalid email or password');
    } catch (e) {
      if (e is AppAuthException) rethrow;
      throw AppException(e.toString());
    }
  }

  // ---- 邮箱注册 ----
  Future<UserModel> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String username,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'username': username,
        },
      );
      if (response.user == null) {
        throw const AppAuthException('Sign up failed');
      }
      return _fetchUserProfile(response.user!.id);
    } on sb.AuthException catch (e) {
      throw AppAuthException(e.message, code: e.statusCode?.toString());
    } catch (e) {
      if (e is AppAuthException) rethrow;
      throw AppException(e.toString());
    }
  }

  // ---- Google OAuth 登录 ----
  Future<UserModel> signInWithGoogle() async {
    try {
      // 使用 google_sign_in 获取 idToken
      const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
      final googleSignIn = GoogleSignIn(
        serverClientId: webClientId,
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw const AppAuthException('Google sign in cancelled');
      }
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        throw const AppAuthException('Google sign in failed: no ID token');
      }

      // 用 idToken 登录 Supabase
      final response = await _client.auth.signInWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      if (response.user == null) {
        throw const AppAuthException('Google sign in failed');
      }
      return _fetchUserProfile(response.user!.id);
    } on sb.AuthException catch (e) {
      throw AppAuthException(e.message, code: e.statusCode?.toString());
    } catch (e) {
      if (e is AppAuthException) rethrow;
      throw AppException(e.toString());
    }
  }

  // ---- Apple OAuth 登录（iOS 必须） ----
  Future<UserModel> signInWithApple() async {
    try {
      final response = await _client.auth.signInWithOAuth(
        sb.OAuthProvider.apple,
        redirectTo: 'io.supabase.dealjoy://login-callback/',
      );
      // OAuth 方式会在浏览器中处理，此处返回 bool
      // 实际用户数据通过 authStateChanges 流获取
      if (!response) {
        throw const AppAuthException('Apple sign in failed');
      }
      // 等待 auth state 变化，获取用户
      await Future.delayed(const Duration(seconds: 2));
      final user = _client.auth.currentUser;
      if (user == null) {
        throw const AppAuthException('Apple sign in failed');
      }
      return _fetchUserProfile(user.id);
    } on sb.AuthException catch (e) {
      throw AppAuthException(e.message, code: e.statusCode?.toString());
    } catch (e) {
      if (e is AppAuthException) rethrow;
      throw AppException(e.toString());
    }
  }

  // ---- 登出 ----
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // ---- 发送密码重置邮件 ----
  Future<void> resetPassword(String email) async {
    // 不管邮箱是否存在都不抛异常（隐私安全）
    try {
      await _client.auth.resetPasswordForEmail(email);
    } catch (_) {
      // 静默处理，不泄露邮箱存在性
    }
  }

  // ---- 重置密码（用户点击重置链接后设置新密码） ----
  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(
        sb.UserAttributes(password: newPassword),
      );
    } on sb.AuthException catch (e) {
      throw AppAuthException(e.message, code: e.statusCode?.toString());
    }
  }

  // ---- 重发验证邮件 ----
  Future<void> resendVerificationEmail() async {
    final user = _client.auth.currentUser;
    if (user == null || user.email == null) return;
    try {
      await _client.auth.resend(
        type: sb.OtpType.signup,
        email: user.email!,
      );
    } on sb.AuthException catch (e) {
      throw AppAuthException(e.message, code: e.statusCode?.toString());
    }
  }

  // ---- 检查邮箱是否已验证 ----
  bool get isEmailVerified {
    final user = _client.auth.currentUser;
    return user?.emailConfirmedAt != null;
  }

  // ---- 获取用户 Profile（不存在则自动创建）----
  Future<UserModel> _fetchUserProfile(String userId) async {
    // 没有 session 时（邮件验证未完成），无法查询 RLS 保护的表，返回临时对象
    if (_client.auth.currentSession == null) {
      final authUser = _client.auth.currentUser;
      final now = DateTime.now().toIso8601String();
      return UserModel(
        id: userId,
        email: authUser?.email ?? '',
        fullName: authUser?.userMetadata?['full_name'] as String?,
        username: authUser?.userMetadata?['username'] as String?,
        avatarUrl: null,
        role: 'user',
        createdAt: DateTime.parse(now),
        updatedAt: DateTime.parse(now),
      );
    }
    final rows =
        await _client.from('users').select().eq('id', userId);
    if (rows.isNotEmpty) {
      return UserModel.fromJson(rows.first);
    }
    // trigger 未生效时回退：用 auth user 信息手动插入
    final authUser = _client.auth.currentUser;
    final now = DateTime.now().toIso8601String();
    final provider = authUser?.appMetadata['provider'] as String? ?? 'email';
    final data = await _client.from('users').insert({
      'id': userId,
      'email': authUser?.email ?? '',
      'full_name': authUser?.userMetadata?['full_name'],
      'username': authUser?.userMetadata?['username'],
      'avatar_url': authUser?.userMetadata?['avatar_url'],
      'role': 'user',
      'registration_source': provider,
      'created_at': now,
      'updated_at': now,
    }).select().single();
    return UserModel.fromJson(data);
  }

  // ---- 记录登录（调用 Supabase RPC） ----
  Future<void> recordLogin({String provider = 'email'}) async {
    try {
      await _client.rpc('record_login', params: {
        'p_provider': provider,
      });
    } catch (e) {
      // 登录记录失败不应阻塞用户体验，仅打印日志
      debugPrint('[Auth] recordLogin failed: $e');
    }
  }

  // ---- 更新用户 Profile ----
  Future<UserModel> updateProfile(UserModel user) async {
    final data = await _client
        .from('users')
        .update(user.toJson())
        .eq('id', user.id)
        .select()
        .single();
    return UserModel.fromJson(data);
  }
}
