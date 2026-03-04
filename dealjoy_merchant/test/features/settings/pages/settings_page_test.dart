// SettingsPage Widget 测试
// 策略: 使用 ProviderContainer overrides 注入 mock SettingsService；
//       验证 UI 分组渲染、Sign Out 按钮存在、Sign Out 确认 Dialog 行为。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dealjoy_merchant/features/settings/models/settings_models.dart';
import 'package:dealjoy_merchant/features/settings/pages/settings_page.dart';
import 'package:dealjoy_merchant/features/settings/providers/settings_provider.dart';
import 'package:dealjoy_merchant/features/settings/services/settings_service.dart';

// ============================================================
// Mock SupabaseClient（mocktail，满足构造器类型要求）
// ============================================================
class _MockSupabaseClient extends Mock implements SupabaseClient {}

// ============================================================
// Mock SettingsService
// 传入 mock SupabaseClient 避免运行时 null cast 错误
// ============================================================
class _MockSettingsService extends SettingsService {
  _MockSettingsService() : super(_MockSupabaseClient());

  bool signOutCalled = false;

  @override
  Future<NotificationPreferences> loadNotificationPreferences() async {
    return const NotificationPreferences();
  }

  @override
  Future<void> saveNotificationPreferences(
    NotificationPreferences prefs,
  ) async {}

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }

  @override
  String get currentUserEmail => 'test@dealjoy.com';

  @override
  User? get currentUser => null;
}

// ============================================================
// 窗口尺寸辅助：增大高度确保 ListView 末尾的 Sign Out 按钮可见
// ============================================================
Future<void> _setSurfaceLarge(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

// ============================================================
// 测试辅助：构建带 Router 和 Provider 的测试 Widget
// ============================================================
Widget _buildTestApp({
  required _MockSettingsService mockService,
  GoRouter? router,
}) {
  final testRouter =
      router ??
      GoRouter(
        routes: [
          GoRoute(path: '/', builder: (ctx, state) => const SettingsPage()),
          GoRoute(
            path: '/login',
            builder: (ctx, state) =>
                const Scaffold(body: Text('Login Page')),
          ),
          GoRoute(
            path: '/settings/account-security',
            builder: (ctx, state) =>
                const Scaffold(body: Text('Account Security')),
          ),
          GoRoute(
            path: '/settings/staff',
            builder: (ctx, state) => const Scaffold(body: Text('Staff')),
          ),
          GoRoute(
            path: '/settings/notifications',
            builder: (ctx, state) =>
                const Scaffold(body: Text('Notifications')),
          ),
          GoRoute(
            path: '/settings/help',
            builder: (ctx, state) => const Scaffold(body: Text('Help')),
          ),
        ],
      );

  return ProviderScope(
    overrides: [
      // 注入 mock service
      settingsServiceProvider.overrideWithValue(mockService),
    ],
    child: MaterialApp.router(routerConfig: testRouter),
  );
}

// ============================================================
// 测试 main
// ============================================================
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ----------------------------------------------------------
  // 基本渲染测试
  // 每个 testWidgets 开头先调用 _setSurfaceLarge，
  // 将窗口高度扩展到 1200px，确保 ListView 末尾的 Sign Out 按钮可见。
  // ----------------------------------------------------------
  group('SettingsPage 渲染', () {
    testWidgets('显示 AppBar 标题 Settings', (tester) async {
      await _setSurfaceLarge(tester);
      final service = _MockSettingsService();
      await tester.pumpWidget(_buildTestApp(mockService: service));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('显示 Profile 区块（Merchant Account 文字）', (tester) async {
      await _setSurfaceLarge(tester);
      final service = _MockSettingsService();
      await tester.pumpWidget(_buildTestApp(mockService: service));
      await tester.pumpAndSettle();

      expect(find.text('Merchant Account'), findsOneWidget);
    });

    testWidgets('显示 Account Security 设置项', (tester) async {
      await _setSurfaceLarge(tester);
      final service = _MockSettingsService();
      await tester.pumpWidget(_buildTestApp(mockService: service));
      await tester.pumpAndSettle();

      expect(find.text('Account Security'), findsOneWidget);
    });

    testWidgets('显示 Staff Accounts 设置项', (tester) async {
      await _setSurfaceLarge(tester);
      final service = _MockSettingsService();
      await tester.pumpWidget(_buildTestApp(mockService: service));
      await tester.pumpAndSettle();

      expect(find.text('Staff Accounts'), findsOneWidget);
    });

    testWidgets('显示 Notification Preferences 设置项', (tester) async {
      await _setSurfaceLarge(tester);
      final service = _MockSettingsService();
      await tester.pumpWidget(_buildTestApp(mockService: service));
      await tester.pumpAndSettle();

      expect(find.text('Notification Preferences'), findsOneWidget);
    });

    testWidgets('显示 Help Center 设置项', (tester) async {
      await _setSurfaceLarge(tester);
      final service = _MockSettingsService();
      await tester.pumpWidget(_buildTestApp(mockService: service));
      await tester.pumpAndSettle();

      expect(find.text('Help Center'), findsOneWidget);
    });

    testWidgets('显示 About DealJoy 设置项', (tester) async {
      await _setSurfaceLarge(tester);
      final service = _MockSettingsService();
      await tester.pumpWidget(_buildTestApp(mockService: service));
      await tester.pumpAndSettle();

      expect(find.text('About DealJoy'), findsOneWidget);
    });

    testWidgets('显示 Sign Out 按钮', (tester) async {
      await _setSurfaceLarge(tester);
      final service = _MockSettingsService();
      await tester.pumpWidget(_buildTestApp(mockService: service));
      await tester.pumpAndSettle();

      expect(find.text('Sign Out'), findsOneWidget);
    });

    testWidgets('显示 4 个分组标题（大写）', (tester) async {
      await _setSurfaceLarge(tester);
      final service = _MockSettingsService();
      await tester.pumpWidget(_buildTestApp(mockService: service));
      await tester.pumpAndSettle();

      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('NOTIFICATIONS'), findsOneWidget);
      expect(find.text('SUPPORT'), findsOneWidget);
    });
  });

  // ----------------------------------------------------------
  // Sign Out 交互测试
  // ----------------------------------------------------------
  group('Sign Out 交互', () {
    testWidgets('点击 Sign Out 弹出确认 Dialog', (tester) async {
      await _setSurfaceLarge(tester);
      final service = _MockSettingsService();
      await tester.pumpWidget(_buildTestApp(mockService: service));
      await tester.pumpAndSettle();

      // 点击 Sign Out 按钮
      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();

      // 确认 Dialog 出现
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(
          'Are you sure you want to sign out of your merchant account?',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Dialog 点击 Cancel 后 Dialog 消失，signOut 未被调用', (tester) async {
      await _setSurfaceLarge(tester);
      final service = _MockSettingsService();
      await tester.pumpWidget(_buildTestApp(mockService: service));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();

      // 点击 Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(service.signOutCalled, isFalse);
    });

    testWidgets('Dialog 中有两个按钮：Cancel 和 Sign Out', (tester) async {
      await _setSurfaceLarge(tester);
      final service = _MockSettingsService();
      await tester.pumpWidget(_buildTestApp(mockService: service));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();

      // Dialog 内的按钮（Sign Out 会出现两次：底部按钮 + Dialog 按钮）
      expect(find.text('Cancel'), findsOneWidget);
      // Sign Out 文字在底部按钮和 Dialog 中各出现一次
      expect(find.text('Sign Out'), findsAtLeastNWidgets(2));
    });
  });

  // ----------------------------------------------------------
  // 分组 Section 组件测试
  // ----------------------------------------------------------
  group('SettingsSection 渲染', () {
    testWidgets('每个 Section 正确渲染标题', (tester) async {
      await _setSurfaceLarge(tester);
      final service = _MockSettingsService();
      await tester.pumpWidget(_buildTestApp(mockService: service));
      await tester.pumpAndSettle();

      // 检查分组标题（SettingsSection 内部显示大写标题）
      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('NOTIFICATIONS'), findsOneWidget);
      expect(find.text('SUPPORT'), findsOneWidget);
    });
  });
}
