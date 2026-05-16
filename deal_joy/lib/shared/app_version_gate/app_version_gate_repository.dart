import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_version_gate_row.dart';

class AppVersionGateRepository {
  AppVersionGateRepository(this._client);

  final SupabaseClient _client;

  /// 拉取失败或表不存在时返回 `null`（调用方视为不拦截）。
  Future<AppVersionGateRow?> fetchRow(String appKey) async {
    try {
      final row = await _client
          .from('app_version_gate')
          .select(
            'app_key, force_update_enabled, min_supported_version, '
            'message_title, message_body, ios_store_url, android_store_url',
          )
          .eq('app_key', appKey)
          .maybeSingle();
      if (row == null) return null;
      return AppVersionGateRow.fromJson(Map<String, dynamic>.from(row));
    } catch (e, st) {
      debugPrint('[AppVersionGate] fetch failed: $e\n$st');
      return null;
    }
  }
}
