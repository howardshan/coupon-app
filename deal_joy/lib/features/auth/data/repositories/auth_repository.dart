import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../../../core/errors/app_exception.dart';
import '../models/user_model.dart';

class AuthRepository {
  final sb.SupabaseClient _client;

  AuthRepository(this._client);

  Stream<sb.AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  sb.User? get currentUser => _client.auth.currentUser;

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
        throw const AppAuthException('Sign in failed');
      }
      return _fetchUserProfile(response.user!.id);
    } on sb.AuthException catch (e) {
      throw AppAuthException(e.message, code: e.statusCode?.toString());
    } catch (e) {
      throw AppException(e.toString());
    }
  }

  Future<UserModel> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );
      if (response.user == null) {
        throw const AppAuthException('Sign up failed');
      }
      return _fetchUserProfile(response.user!.id);
    } on sb.AuthException catch (e) {
      throw AppAuthException(e.message, code: e.statusCode?.toString());
    } catch (e) {
      throw AppException(e.toString());
    }
  }

  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(sb.OAuthProvider.google);
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  Future<UserModel> _fetchUserProfile(String userId) async {
    final data =
        await _client.from('users').select().eq('id', userId).single();
    return UserModel.fromJson(data);
  }

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
