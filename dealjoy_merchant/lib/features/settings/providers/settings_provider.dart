// 设置模块状态管理
// 包含: SettingsService Provider / 通知偏好 StateNotifier / 员工列表 FutureProvider（V2）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/settings_models.dart';
import '../services/settings_service.dart';

// ============================================================
// SettingsService Provider
// ============================================================
final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService(Supabase.instance.client);
});

// ============================================================
// NotificationPrefsNotifier — 通知偏好状态机
// state: AsyncValue<NotificationPreferences>
//   - AsyncLoading: 初始化从 SharedPreferences 读取中
//   - AsyncData: 正常运行状态，保存最新偏好值
//   - AsyncError: 读取/写入失败（实际场景极罕见）
// ============================================================
class NotificationPrefsNotifier
    extends StateNotifier<AsyncValue<NotificationPreferences>> {
  NotificationPrefsNotifier(this._service)
      : super(const AsyncLoading()) {
    // 构造时立即从 SharedPreferences 加载
    _load();
  }

  final SettingsService _service;

  // ----------------------------------------------------------
  // 初始化：从本地存储读取已保存的偏好
  // ----------------------------------------------------------
  Future<void> _load() async {
    try {
      final prefs = await _service.loadNotificationPreferences();
      state = AsyncData(prefs);
    } catch (e, st) {
      // 读取失败时降级为默认值，避免 UI 卡在 loading
      state = AsyncData(const NotificationPreferences());
      // 同时记录错误（生产环境可接入 Sentry）
      // ignore: avoid_print
      print('[SettingsProvider] Failed to load notification prefs: $e\n$st');
    }
  }

  // ----------------------------------------------------------
  // 更新单条通知开关，并立即持久化
  // ----------------------------------------------------------
  Future<void> update(NotificationPreferences newPrefs) async {
    // 乐观更新：先更新 UI
    state = AsyncData(newPrefs);
    // 后台持久化（失败时记录日志，不回滚 UI——偏好类数据丢失代价低）
    try {
      await _service.saveNotificationPreferences(newPrefs);
    } catch (e) {
      // ignore: avoid_print
      print('[SettingsProvider] Failed to save notification prefs: $e');
    }
  }

  // ----------------------------------------------------------
  // 重新从本地存储加载（用于下拉刷新场景）
  // ----------------------------------------------------------
  Future<void> refresh() => _load();
}

// ============================================================
// 通知偏好 Provider（对外暴露）
// ============================================================
final notificationPrefsProvider = StateNotifierProvider<
    NotificationPrefsNotifier, AsyncValue<NotificationPreferences>>(
  (ref) {
    final service = ref.watch(settingsServiceProvider);
    return NotificationPrefsNotifier(service);
  },
);

// ============================================================
// 员工列表 FutureProvider（V2 存根）
// 使用 .family 支持按 merchantId 缓存
// ============================================================
final staffMembersProvider =
    FutureProvider.family<List<StaffMember>, String>((ref, merchantId) async {
  final service = ref.watch(settingsServiceProvider);
  return service.fetchStaffMembers(merchantId);
});
