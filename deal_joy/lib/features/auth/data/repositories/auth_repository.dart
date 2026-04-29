import 'dart:convert' show utf8;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../../../core/config/env.dart';
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
      // 邮箱未验证时：登出并提示用户去验证
      if (response.user!.emailConfirmedAt == null) {
        await _client.auth.signOut();
        throw const AppAuthException(
          'Please verify your email before signing in. Check your inbox for the verification link.',
          code: 'email_not_confirmed',
        );
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

  // ---- 检查用户名是否已被占用 ----
  Future<bool> isUsernameTaken(String username) async {
    final result = await _client
        .from('users')
        .select('id')
        .eq('username', username)
        .maybeSingle();
    return result != null;
  }

  // ---- 检查邮箱是否已被注册（查 auth.users，含商家账号）----
  Future<bool> isEmailTaken(String email) async {
    try {
      final result = await _client
          .rpc('is_email_registered', params: {'p_email': email.trim().toLowerCase()});
      return result == true;
    } catch (_) {
      // RPC 失败时回退查 users 表
      final row = await _client
          .from('users')
          .select('id')
          .eq('email', email.trim().toLowerCase())
          .maybeSingle();
      return row != null;
    }
  }

  // ---- 邮箱注册 ----
  Future<UserModel> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String username,
    required String dateOfBirth,
    bool marketingOptIn = false,
    bool analyticsOptIn = false,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'username': username,
          'date_of_birth': dateOfBirth,
          'marketing_opt_in': marketingOptIn,
          'analytics_opt_in': analyticsOptIn,
        },
      );
      if (response.user == null) {
        throw const AppAuthException('Sign up failed');
      }
      // Supabase 对已存在邮箱返回 fake 用户，identities 为空
      final identities = response.user!.identities;
      if (identities == null || identities.isEmpty) {
        throw const AppAuthException(
          'This email is already registered. Please sign in instead.',
        );
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
      // 从 .env 读取 Web Client ID（运行时配置，非编译时常量）
      // 没有 serverClientId 时 Google 返回的 idToken 为 null
      final webClientId = Env.googleWebClientId;
      if (webClientId.isEmpty) {
        throw const AppAuthException(
          'Google sign-in is not configured. Please contact support.',
        );
      }
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

  // ---- Apple 登录（iOS 原生：sign_in_with_apple + Supabase idToken）----
  // See https://supabase.com/docs/guides/auth/social-login/auth-apple?platform=flutter
  Future<UserModel> signInWithApple() async {
    try {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
        throw const AppAuthException(
          'Apple sign in is only available on the iOS app.',
        );
      }

      final rawNonce = _client.auth.generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AppAuthException(
          'Apple sign in failed: no identity token.',
        );
      }

      final response = await _client.auth.signInWithIdToken(
        provider: sb.OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      if (response.user == null) {
        throw const AppAuthException('Apple sign in failed');
      }

      if (credential.givenName != null || credential.familyName != null) {
        final nameParts = <String>[];
        if (credential.givenName != null &&
            credential.givenName!.trim().isNotEmpty) {
          nameParts.add(credential.givenName!.trim());
        }
        if (credential.familyName != null &&
            credential.familyName!.trim().isNotEmpty) {
          nameParts.add(credential.familyName!.trim());
        }
        if (nameParts.isNotEmpty) {
          try {
            await _client.auth.updateUser(
              sb.UserAttributes(
                data: {
                  'full_name': nameParts.join(' '),
                  'given_name': credential.givenName,
                  'family_name': credential.familyName,
                },
              ),
            );
          } catch (_) {
            // First sign-in only; metadata update must not block login.
          }
        }
      }

      return _fetchUserProfile(response.user!.id);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AppAuthException('Apple sign in cancelled');
      }
      throw AppAuthException(e.message);
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
    try {
      // 使用 Edge Function 中间页作为 redirectTo：
      // Chrome 会阻止服务端 302 直接跳转自定义协议（io.supabase.crunchyplum://），
      // 但 Edge Function 返回的 HTML 页面可以通过 Android intent:// URL 可靠唤起 App。
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo:
            'https://kqyolvmgrdekybjrwizx.supabase.co/functions/v1/auth-redirect',
      );
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
