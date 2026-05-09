import 'package:supabase_flutter/supabase_flutter.dart';

// 用户端整账号删除：仅调用后端 full 分支，与商家端共用 Edge Function
class AccountDeletionRepository {
  AccountDeletionRepository(this._client);

  final SupabaseClient _client;

  Future<void> deleteFullAccount() async {
    if (_client.auth.currentSession == null) {
      throw StateError('Not signed in');
    }
    try {
      await _client.auth.refreshSession();
    } catch (_) {}
    final response = await _client.functions.invoke(
      'account-delete',
      body: {'scope': 'full'},
    );
    if (response.status != 200) {
      final data = response.data;
      final msg = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Request failed (${response.status})';
      throw Exception(msg);
    }
  }
}
