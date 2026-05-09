import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/account_deletion_self_initiated.dart';

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

    AccountDeletionSelfInitiated.active = true;
    try {
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

      // 服务端已删除 Auth 用户：立即清本地会话，避免默认 signOut 远程 revoke 挂死或抛错
      try {
        await _client.auth.signOut(scope: SignOutScope.local);
      } catch (e) {
        debugPrint('[AccountDeletionRepository] local signOut: $e');
      }
    } finally {
      AccountDeletionSelfInitiated.active = false;
    }
  }
}
