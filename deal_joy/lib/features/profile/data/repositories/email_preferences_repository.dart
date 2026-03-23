import 'package:supabase_flutter/supabase_flutter.dart';

/// 单条邮件偏好数据（展示层使用）
class EmailPreferenceItem {
  final String code;
  final String name;
  final bool enabled;

  const EmailPreferenceItem({
    required this.code,
    required this.name,
    required this.enabled,
  });

  EmailPreferenceItem copyWith({bool? enabled}) {
    return EmailPreferenceItem(
      code: code,
      name: name,
      enabled: enabled ?? this.enabled,
    );
  }
}

/// 客户端邮件偏好 Repository
/// - 读取全局启用且用户可配置的邮件类型（来自 email_type_settings）
/// - 读写用户当前偏好（user_email_preferences 表）
class EmailPreferencesRepository {
  final SupabaseClient _supabase;

  EmailPreferencesRepository(this._supabase);

  /// 获取当前用户的邮件偏好列表
  /// 只返回 global_enabled=true 且 user_configurable=true 的类型
  Future<List<EmailPreferenceItem>> fetchPreferences(String userId) async {
    // 查询全局启用且用户可配置的邮件类型
    final settingsRes = await _supabase
        .from('email_type_settings')
        .select('email_code, email_name')
        .eq('recipient_type', 'customer')
        .eq('global_enabled', true)
        .eq('user_configurable', true)
        .order('email_code');

    if (settingsRes.isEmpty) return [];

    final codes = settingsRes.map((e) => e['email_code'] as String).toList();

    // 查询用户当前偏好记录
    final prefsRes = await _supabase
        .from('user_email_preferences')
        .select('email_code, enabled')
        .eq('user_id', userId)
        .inFilter('email_code', codes);

    final prefsMap = {
      for (final p in prefsRes) p['email_code'] as String: p['enabled'] as bool
    };

    // 合并：无记录时默认开启
    return settingsRes.map((s) {
      final code = s['email_code'] as String;
      return EmailPreferenceItem(
        code: code,
        name: s['email_name'] as String? ?? code,
        enabled: prefsMap[code] ?? true,
      );
    }).toList();
  }

  /// 更新单条邮件偏好（upsert）
  Future<void> setPreference(
    String userId,
    String emailCode,
    bool enabled,
  ) async {
    await _supabase.from('user_email_preferences').upsert(
      {
        'user_id': userId,
        'email_code': emailCode,
        'enabled': enabled,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id,email_code',
    );
  }
}
