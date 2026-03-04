# Flutter + Riverpod 代码模式参考

> 本文件是前端开发 Agent 的核心参考。生成代码时必须遵循这些模式。

## 1. Riverpod AsyncNotifier 标准模式

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_notifier.g.dart';

/// 认证状态
enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

/// 认证状态数据
class AuthState {
  final AuthStatus status;
  final String? userId;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.initial,
    this.userId,
    this.errorMessage,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? userId,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  AuthState build() {
    // 初始状态
    return const AuthState();
  }

  /// 登录
  Future<void> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final authService = ref.read(authServiceProvider);
      final userId = await authService.login(email, password);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        userId: userId,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}
```

## 2. Service 层标准模式

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_service.g.dart';

/// Supabase 客户端 Provider
@riverpod
SupabaseClient supabaseClient(SupabaseClientRef ref) {
  return Supabase.instance.client;
}

/// 认证服务
@riverpod
AuthService authService(AuthServiceRef ref) {
  return AuthService(ref.watch(supabaseClientProvider));
}

class AuthService {
  final SupabaseClient _client;

  AuthService(this._client);

  /// 邮箱注册
  Future<String> register({
    required String email,
    required String password,
    required String username,
  }) async {
    // 调用 Edge Function
    final response = await _client.functions.invoke(
      'auth-register',
      body: {
        'email': email,
        'password': password,
        'username': username,
      },
    );

    if (response.status != 200) {
      final error = response.data['error'];
      throw AppException(
        code: error['code'],
        message: _mapErrorMessage(error['code']),
      );
    }

    return response.data['data']['user_id'];
  }

  /// 错误码映射为英文用户提示
  String _mapErrorMessage(String code) {
    switch (code) {
      case 'EMAIL_EXISTS':
        return 'This email is already registered';
      case 'WEAK_PASSWORD':
        return 'Password must be at least 8 characters with uppercase, lowercase and numbers';
      case 'USERNAME_TAKEN':
        return 'This username is already taken';
      case 'INVALID_EMAIL':
        return 'Please enter a valid email address';
      case 'RATE_LIMITED':
        return 'Too many attempts. Please try again later';
      default:
        return 'Something went wrong. Please try again';
    }
  }
}

/// 统一异常类
class AppException implements Exception {
  final String code;
  final String message;

  AppException({required this.code, required this.message});

  @override
  String toString() => message;
}
```

## 3. Page 页面标准模式

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 注册页面
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.status == AuthStatus.loading;

    // 监听状态变化
    ref.listen(authNotifierProvider, (prev, next) {
      if (next.status == AuthStatus.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!)),
        );
      }
      if (next.status == AuthStatus.authenticated) {
        context.go('/home');
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 邮箱输入
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'Enter your email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: _validateEmail,
                  enabled: !isLoading,
                ),
                const SizedBox(height: 16),

                // 密码输入
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'At least 8 characters',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  validator: _validatePassword,
                  enabled: !isLoading,
                ),
                const SizedBox(height: 24),

                // 提交按钮
                FilledButton(
                  onPressed: isLoading ? null : _handleSubmit,
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign Up'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) return 'Please enter a valid email';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Password must be at least 8 characters';
    if (!value.contains(RegExp(r'[A-Z]'))) return 'Must include an uppercase letter';
    if (!value.contains(RegExp(r'[0-9]'))) return 'Must include a number';
    return null;
  }

  void _handleSubmit() {
    if (_formKey.currentState!.validate()) {
      ref.read(authNotifierProvider.notifier).register(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    }
  }
}
```

## 4. go_router 路由配置

```dart
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@riverpod
GoRouter router(RouterRef ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final isAuthenticated = authState.status == AuthStatus.authenticated;
      final isAuthRoute = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/register');

      // 已登录用户不能访问登录/注册页
      if (isAuthenticated && isAuthRoute) return '/home';
      // 未登录用户只能访问登录/注册页
      if (!isAuthenticated && !isAuthRoute) return '/login';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomePage(),
      ),
    ],
  );
}
```

## 5. 目录命名约定

```
lib/
├── core/
│   ├── theme/
│   │   └── app_theme.dart          # 全局主题
│   ├── constants/
│   │   └── app_constants.dart      # 常量
│   ├── utils/
│   │   └── validators.dart         # 通用校验器
│   └── providers/
│       └── supabase_providers.dart # Supabase Provider
├── features/
│   └── auth/
│       ├── models/
│       │   └── user_profile.dart
│       ├── providers/
│       │   └── auth_notifier.dart
│       ├── services/
│       │   └── auth_service.dart
│       ├── pages/
│       │   ├── login_page.dart
│       │   └── register_page.dart
│       └── widgets/
│           ├── social_login_button.dart
│           └── password_strength_indicator.dart
└── shared/
    └── widgets/
        ├── loading_overlay.dart
        └── error_snackbar.dart
```

## 6. pubspec.yaml 核心依赖

```yaml
dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^2.3.0
  flutter_riverpod: ^2.4.0
  riverpod_annotation: ^2.3.0
  go_router: ^13.0.0
  google_sign_in: ^6.2.0
  sign_in_with_apple: ^6.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  riverpod_generator: ^2.3.0
  build_runner: ^2.4.0
  mocktail: ^1.0.0
```
