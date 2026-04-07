import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/models/user_model.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

// Supabase auth 状态流
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

// 当前用户 Profile
final currentUserProvider = FutureProvider<UserModel?>((ref) async {
  final authState = await ref.watch(authStateProvider.future);
  if (authState.session == null) return null;

  final userId = authState.session!.user.id;

  try {
    final client = ref.watch(supabaseClientProvider);
    final data =
        await client.from('users').select().eq('id', userId).single();
    return UserModel.fromJson(data);
  } catch (_) {
    return null;
  }
});

// 邮箱是否已验证
final isEmailVerifiedProvider = Provider<bool>((ref) {
  return ref.watch(authRepositoryProvider).isEmailVerified;
});

// ---- Auth 操作 Notifier ----
class AuthNotifier extends Notifier<AsyncValue<UserModel?>> {
  @override
  AsyncValue<UserModel?> build() => const AsyncValue.data(null);

  Future<void> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signInWithEmail(
            email: email,
            password: password,
          ),
    );
    if (state.hasError) {
      debugPrint('[Auth] signIn error: ${state.error}');
    } else {
      ref.read(authRepositoryProvider).recordLogin(provider: 'email');
    }
  }

  Future<void> signUp(
    String email,
    String password,
    String fullName, {
    required String username,
    required String dateOfBirth,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signUpWithEmail(
            email: email,
            password: password,
            fullName: fullName,
            username: username,
            dateOfBirth: dateOfBirth,
          ),
    );
    if (state.hasError) {
      debugPrint('[Auth] signUp error: ${state.error}');
    }
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signInWithGoogle(),
    );
    if (state.hasError) {
      debugPrint('[Auth] Google signIn error: ${state.error}');
    } else {
      ref.read(authRepositoryProvider).recordLogin(provider: 'google');
    }
  }

  Future<void> signInWithApple() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signInWithApple(),
    );
    if (state.hasError) {
      debugPrint('[Auth] Apple signIn error: ${state.error}');
    } else {
      ref.read(authRepositoryProvider).recordLogin(provider: 'apple');
    }
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncValue.data(null);
  }
}

final authNotifierProvider =
    NotifierProvider<AuthNotifier, AsyncValue<UserModel?>>(AuthNotifier.new);

// ---- 密码重置 Notifier（替代 setState） ----
class ForgotPasswordNotifier extends Notifier<ForgotPasswordState> {
  @override
  ForgotPasswordState build() => const ForgotPasswordState();

  Future<void> sendResetLink(String email) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await ref.read(authRepositoryProvider).resetPassword(email);
      state = state.copyWith(isLoading: false, isSent: true, email: email);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void reset() {
    state = const ForgotPasswordState();
  }
}

class ForgotPasswordState {
  final bool isLoading;
  final bool isSent;
  final String? email;
  final String? error;

  const ForgotPasswordState({
    this.isLoading = false,
    this.isSent = false,
    this.email,
    this.error,
  });

  ForgotPasswordState copyWith({
    bool? isLoading,
    bool? isSent,
    String? email,
    String? error,
  }) =>
      ForgotPasswordState(
        isLoading: isLoading ?? this.isLoading,
        isSent: isSent ?? this.isSent,
        email: email ?? this.email,
        error: error,
      );
}

final forgotPasswordProvider =
    NotifierProvider<ForgotPasswordNotifier, ForgotPasswordState>(
        ForgotPasswordNotifier.new);

// ---- 重置密码 Notifier ----
class ResetPasswordNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<bool> updatePassword(String newPassword) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).updatePassword(newPassword),
    );
    return !state.hasError;
  }
}

final resetPasswordProvider =
    NotifierProvider<ResetPasswordNotifier, AsyncValue<void>>(
        ResetPasswordNotifier.new);
