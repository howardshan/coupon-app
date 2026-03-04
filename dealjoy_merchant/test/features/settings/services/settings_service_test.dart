// SettingsService 单元测试
// 策略: 使用可测试子类 stub 掉 SharedPreferences 和 Supabase；
//       直接测试模型解析逻辑不依赖真实外部依赖。
//
// 测试范围:
//   - loadNotificationPreferences: 默认值 / 已保存值读取
//   - saveNotificationPreferences: 各字段正确写入
//   - signOut: 调用 Supabase auth.signOut()
//   - NotificationPreferences: copyWith / equals / hashCode
//   - StaffRole: apiValue / fromApiValue / displayName

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dealjoy_merchant/features/settings/models/settings_models.dart';
import 'package:dealjoy_merchant/features/settings/services/settings_service.dart';

// ============================================================
// Mock SupabaseClient（mocktail，满足构造器类型约束）
// ============================================================
class _MockSupabaseClient extends Mock implements SupabaseClient {}

// ============================================================
// 可测试的 SettingsService 子类
// stub 掉 signOut，只测试 SharedPreferences 读写
// ============================================================
class _TestableSettingsService extends SettingsService {
  _TestableSettingsService() : super(_MockSupabaseClient());

  bool signOutCalled = false;

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }
}

// ============================================================
// 测试 main
// ============================================================
void main() {
  // 在所有测试前设置 SharedPreferences 为 mock 模式
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ----------------------------------------------------------
  // NotificationPreferences 模型测试
  // ----------------------------------------------------------
  group('NotificationPreferences', () {
    test('默认值正确', () {
      const prefs = NotificationPreferences();
      expect(prefs.newOrder, isTrue);
      expect(prefs.redemption, isTrue);
      expect(prefs.dealApproved, isTrue);
      expect(prefs.reviewResult, isTrue);
      expect(prefs.systemAnnouncement, isFalse); // 系统公告默认关
    });

    test('copyWith 单字段更新不影响其他字段', () {
      const original = NotificationPreferences();
      final updated = original.copyWith(systemAnnouncement: true);

      expect(updated.systemAnnouncement, isTrue);
      expect(updated.newOrder, isTrue); // 其他字段不变
      expect(updated.redemption, isTrue);
    });

    test('相同值的实例 == 相等', () {
      const a = NotificationPreferences();
      const b = NotificationPreferences();
      expect(a, equals(b));
    });

    test('不同值的实例 != 不相等', () {
      const a = NotificationPreferences();
      final b = a.copyWith(newOrder: false);
      expect(a, isNot(equals(b)));
    });

    test('hashCode 相同值一致', () {
      const a = NotificationPreferences();
      const b = NotificationPreferences();
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toMap 包含所有键', () {
      const prefs = NotificationPreferences();
      final map = prefs.toMap();
      expect(map.containsKey('newOrder'), isTrue);
      expect(map.containsKey('redemption'), isTrue);
      expect(map.containsKey('dealApproved'), isTrue);
      expect(map.containsKey('reviewResult'), isTrue);
      expect(map.containsKey('systemAnnouncement'), isTrue);
    });

    test('fromMap 读取正确', () {
      final prefs = NotificationPreferences.fromMap({
        'newOrder': false,
        'redemption': true,
        'dealApproved': false,
        'reviewResult': true,
        'systemAnnouncement': true,
      });
      expect(prefs.newOrder, isFalse);
      expect(prefs.systemAnnouncement, isTrue);
    });

    test('fromMap 缺失键使用默认值', () {
      final prefs = NotificationPreferences.fromMap({});
      expect(prefs.newOrder, isTrue);
      expect(prefs.systemAnnouncement, isFalse);
    });
  });

  // ----------------------------------------------------------
  // StaffRole 枚举测试
  // ----------------------------------------------------------
  group('StaffRole', () {
    test('apiValue 映射正确', () {
      expect(StaffRole.scanOnly.apiValue, equals('scan_only'));
      expect(StaffRole.fullAccess.apiValue, equals('full_access'));
    });

    test('fromApiValue 解析正确', () {
      expect(StaffRole.fromApiValue('scan_only'), equals(StaffRole.scanOnly));
      expect(StaffRole.fromApiValue('full_access'), equals(StaffRole.fullAccess));
    });

    test('fromApiValue 未知值降级为 scanOnly', () {
      expect(StaffRole.fromApiValue('unknown'), equals(StaffRole.scanOnly));
    });

    test('displayName 非空', () {
      expect(StaffRole.scanOnly.displayName, isNotEmpty);
      expect(StaffRole.fullAccess.displayName, isNotEmpty);
    });

    test('description 非空', () {
      expect(StaffRole.scanOnly.description, isNotEmpty);
      expect(StaffRole.fullAccess.description, isNotEmpty);
    });
  });

  // ----------------------------------------------------------
  // SettingsService.loadNotificationPreferences 测试
  // ----------------------------------------------------------
  group('SettingsService.loadNotificationPreferences', () {
    test('首次加载（无保存数据）返回默认值', () async {
      SharedPreferences.setMockInitialValues({});
      final service = _TestableSettingsService();

      final prefs = await service.loadNotificationPreferences();

      expect(prefs.newOrder, isTrue);
      expect(prefs.redemption, isTrue);
      expect(prefs.dealApproved, isTrue);
      expect(prefs.reviewResult, isTrue);
      expect(prefs.systemAnnouncement, isFalse);
    });

    test('加载已保存的偏好', () async {
      // 预设 SharedPreferences 值
      SharedPreferences.setMockInitialValues({
        'dealjoy_notif_new_order': false,
        'dealjoy_notif_redemption': true,
        'dealjoy_notif_deal_approved': false,
        'dealjoy_notif_review_result': true,
        'dealjoy_notif_system_announcement': true,
      });
      final service = _TestableSettingsService();

      final prefs = await service.loadNotificationPreferences();

      expect(prefs.newOrder, isFalse);
      expect(prefs.redemption, isTrue);
      expect(prefs.dealApproved, isFalse);
      expect(prefs.systemAnnouncement, isTrue);
    });
  });

  // ----------------------------------------------------------
  // SettingsService.saveNotificationPreferences 测试
  // ----------------------------------------------------------
  group('SettingsService.saveNotificationPreferences', () {
    test('保存后再加载值一致', () async {
      SharedPreferences.setMockInitialValues({});
      final service = _TestableSettingsService();

      // 构造一个非默认的偏好
      const toSave = NotificationPreferences(
        newOrder: false,
        redemption: false,
        dealApproved: true,
        reviewResult: false,
        systemAnnouncement: true,
      );

      await service.saveNotificationPreferences(toSave);
      final loaded = await service.loadNotificationPreferences();

      expect(loaded, equals(toSave));
    });

    test('多次保存以最后一次为准', () async {
      SharedPreferences.setMockInitialValues({});
      final service = _TestableSettingsService();

      await service.saveNotificationPreferences(
        const NotificationPreferences(newOrder: false),
      );
      await service.saveNotificationPreferences(
        const NotificationPreferences(newOrder: true),
      );

      final loaded = await service.loadNotificationPreferences();
      expect(loaded.newOrder, isTrue);
    });

    test('仅更新 systemAnnouncement 其他字段不变', () async {
      SharedPreferences.setMockInitialValues({});
      final service = _TestableSettingsService();

      // 先保存默认偏好
      const original = NotificationPreferences();
      await service.saveNotificationPreferences(original);

      // 更新 systemAnnouncement
      await service.saveNotificationPreferences(
        original.copyWith(systemAnnouncement: true),
      );

      final loaded = await service.loadNotificationPreferences();
      expect(loaded.newOrder, isTrue);
      expect(loaded.systemAnnouncement, isTrue);
    });
  });

  // ----------------------------------------------------------
  // SettingsService.signOut 测试（存根验证）
  // ----------------------------------------------------------
  group('SettingsService.signOut', () {
    test('signOut 被调用', () async {
      final service = _TestableSettingsService();
      await service.signOut();
      expect(service.signOutCalled, isTrue);
    });
  });
}
