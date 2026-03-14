import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:deal_joy/main.dart' as app;
import 'test_config.dart';

/// App 启动辅助函数
/// 集成测试中统一通过此模块启动 App，确保 Supabase 和 Stripe 正确初始化

/// 启动 App 并等待初始化完成
/// 调用 deal_joy 的 main()，等待 Supabase 初始化 + 路由完成第一次跳转
Future<void> launchApp(WidgetTester tester) async {
  // 确保 binding 初始化（如果上层没有调用可以在此保障）
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 调用 App 的 main() 函数，触发 Supabase + Stripe 初始化
  app.main();

  // 等待 App 完全渲染：包含 Supabase 初始化 + 路由决策（未登录跳 /auth/login）
  await tester.pumpAndSettle(TestConfig.appLaunchTimeout);
}

/// 启动 App 并等待，使用自定义超时时间
Future<void> launchAppWithTimeout(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  app.main();
  await tester.pumpAndSettle(timeout);
}

/// 等待路由跳转完成（适用于点击按钮后的页面切换）
Future<void> waitForRoute(WidgetTester tester) async {
  await tester.pumpAndSettle(TestConfig.routeTransitionTimeout);
}

/// 等待网络请求完成（适用于登录/注册等异步操作）
Future<void> waitForNetwork(WidgetTester tester) async {
  await tester.pumpAndSettle(TestConfig.networkTimeout);
}
