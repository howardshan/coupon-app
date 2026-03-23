import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/repositories/email_preferences_repository.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';

// ── Repository Provider ─────────────────────────────────────────────────────

final emailPreferencesRepositoryProvider =
    Provider<EmailPreferencesRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return EmailPreferencesRepository(supabase);
});

// ── Notifier ────────────────────────────────────────────────────────────────

class EmailPreferencesNotifier
    extends AsyncNotifier<List<EmailPreferenceItem>> {
  @override
  Future<List<EmailPreferenceItem>> build() async {
    final supabase = ref.watch(supabaseClientProvider);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final repo = ref.watch(emailPreferencesRepositoryProvider);
    return repo.fetchPreferences(userId);
  }

  /// 切换某条邮件偏好开关（乐观更新）
  Future<void> toggle(String emailCode, bool enabled) async {
    final supabase = ref.read(supabaseClientProvider);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // 乐观更新 UI
    final current = state.valueOrNull ?? [];
    state = AsyncData(
      current.map((item) {
        return item.code == emailCode ? item.copyWith(enabled: enabled) : item;
      }).toList(),
    );

    // 写入 Supabase
    try {
      final repo = ref.read(emailPreferencesRepositoryProvider);
      await repo.setPreference(userId, emailCode, enabled);
    } catch (_) {
      // 写入失败时回滚
      state = AsyncData(current);
    }
  }
}

final emailPreferencesProvider =
    AsyncNotifierProvider<EmailPreferencesNotifier, List<EmailPreferenceItem>>(
  EmailPreferencesNotifier.new,
);
