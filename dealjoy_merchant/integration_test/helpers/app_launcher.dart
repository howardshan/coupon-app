// App 启动辅助函数
// 在集成测试中统一启动商家端 App

import 'package:flutter_test/flutter_test.dart';
import 'package:dealjoy_merchant/main.dart' as app;
import 'package:dealjoy_merchant/router/app_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_config.dart';

/// 启动商家端 App 并等待帧稳定
///
/// [timeout]: 等待 pumpAndSettle 的最长时间，默认 [TestConfig.appLaunchTimeout]
/// 每次测试开始时调用，确保 App 从干净状态启动
Future<void> launchApp(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  app.main();
  // 等待所有帧渲染完成（Supabase 初始化 + 路由 redirect 需要时间）
  await tester.pumpAndSettle(timeout);
}

/// 启动 App 前先确保 Supabase Auth 已退出（清理上一个测试的会话）
///
/// 如果 Supabase 已经初始化过，直接 signOut；
/// 否则由 main() 初始化后自然处于未登录状态
Future<void> launchAppSignedOut(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  // 尝试退出当前会话，忽略未初始化的错误
  try {
    await Supabase.instance.client.auth.signOut();
  } catch (_) {
    // Supabase 尚未初始化时会抛出，忽略
  }

  // 清除路由层的商家状态缓存，避免上一个测试的缓存影响路由跳转
  MerchantStatusCache.clear();

  await launchApp(tester, timeout: timeout);
}

/// 等待异步登录流程完成（适用于登录后需等待多个网络请求 + 路由跳转的场景）
///
/// pumpAndSettle 不会等待网络请求完成（signIn、查 role、查 status），
/// 所以需要反复 pump 直到目标 Widget 出现。
///
/// [finder]: 目标页面的 Finder（出现即视为导航完成）
/// [maxWait]: 最大等待秒数，默认 15 秒
Future<void> waitForNavigation(
  WidgetTester tester,
  Finder finder, {
  int maxWait = 15,
}) async {
  for (int i = 0; i < maxWait * 2; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (finder.evaluate().isNotEmpty) {
      // 找到目标后再 settle 一次确保 UI 稳定
      await tester.pumpAndSettle();
      return;
    }
  }
  // 超时后最后 settle 一次，让后续断言报出有意义的错误
  await tester.pumpAndSettle();
}

/// 等待路由跳转完成（简单版：用 pumpAndSettle）
///
/// 适用于不涉及网络请求的路由跳转（如 context.go 直接跳）
Future<void> waitForRouteTransition(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  await tester.pumpAndSettle(timeout);
}
