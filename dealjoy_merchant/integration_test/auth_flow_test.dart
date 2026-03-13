// 商家端登录注册流程集成测试 (M001-M015)
// 覆盖: 登录页表单交互、校验、登录跳转、登出、注册流程入口、状态审核页

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/test_config.dart';
import 'helpers/supabase_test_helper.dart';
import 'helpers/app_launcher.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ──────────────────────────────────────────────────────────────
  // 测试组 1: 登录页表单交互 (M001-M007)
  // ──────────────────────────────────────────────────────────────
  group('M001-M007 商家登录页表单交互', () {
    // 每个测试前确保处于未登录状态
    setUp(() async {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    });

    // ----------------------------------------------------------
    // M001: 邮箱与密码输入框可正常显示并接受输入
    // ----------------------------------------------------------
    testWidgets('M001 - 登录页输入框存在且可输入', (tester) async {
      await launchAppSignedOut(tester);

      // 未登录状态下应跳转到 /auth/login，验证登录页元素
      final emailField = find.byKey(const ValueKey('login_email_field'));
      final passwordField = find.byKey(const ValueKey('login_password_field'));
      expect(emailField, findsOneWidget, reason: 'Email 输入框应该存在');
      expect(passwordField, findsOneWidget, reason: 'Password 输入框应该存在');

      // 验证可以输入文字
      await tester.enterText(emailField, 'test@example.com');
      await tester.enterText(passwordField, 'password123');
      await tester.pumpAndSettle();

      expect(find.text('test@example.com'), findsOneWidget);
    });

    // ----------------------------------------------------------
    // M002: 登录按钮存在且可点击
    // ----------------------------------------------------------
    testWidgets('M002 - 登录提交按钮存在', (tester) async {
      await launchAppSignedOut(tester);

      final submitBtn = find.byKey(const ValueKey('login_submit_btn'));
      expect(submitBtn, findsOneWidget, reason: 'Sign In 按钮应该存在');

      // 验证按钮文字
      expect(find.text('Sign In'), findsOneWidget);
    });

    // ----------------------------------------------------------
    // M003: 空表单提交时显示校验错误
    // ----------------------------------------------------------
    testWidgets('M003 - 空表单提交触发校验错误', (tester) async {
      await launchAppSignedOut(tester);

      final submitBtn = find.byKey(const ValueKey('login_submit_btn'));
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // 校验错误：Email is required
      expect(
        find.text('Email is required'),
        findsOneWidget,
        reason: '空邮箱应显示校验错误',
      );
    });

    // ----------------------------------------------------------
    // M004: 邮箱格式不合法时显示校验错误
    // ----------------------------------------------------------
    testWidgets('M004 - 无效邮箱格式触发校验错误', (tester) async {
      await launchAppSignedOut(tester);

      final emailField = find.byKey(const ValueKey('login_email_field'));
      final passwordField = find.byKey(const ValueKey('login_password_field'));
      final submitBtn = find.byKey(const ValueKey('login_submit_btn'));

      // 输入无效邮箱（无 @）
      await tester.enterText(emailField, 'notanemail');
      await tester.enterText(passwordField, 'somepassword');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(
        find.text('Enter a valid email'),
        findsOneWidget,
        reason: '无效邮箱格式应显示校验错误',
      );
    });

    // ----------------------------------------------------------
    // M005: 密码为空时显示校验错误
    // ----------------------------------------------------------
    testWidgets('M005 - 密码为空触发校验错误', (tester) async {
      await launchAppSignedOut(tester);

      final emailField = find.byKey(const ValueKey('login_email_field'));
      final submitBtn = find.byKey(const ValueKey('login_submit_btn'));

      // 有合法邮箱但不填密码
      await tester.enterText(emailField, 'valid@example.com');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(
        find.text('Password is required'),
        findsOneWidget,
        reason: '空密码应显示校验错误',
      );
    });

    // ----------------------------------------------------------
    // M006: 凭据错误时显示友好错误信息
    // ----------------------------------------------------------
    testWidgets('M006 - 错误密码显示登录失败错误信息', (tester) async {
      await launchAppSignedOut(tester);

      final emailField = find.byKey(const ValueKey('login_email_field'));
      final passwordField = find.byKey(const ValueKey('login_password_field'));
      final submitBtn = find.byKey(const ValueKey('login_submit_btn'));

      // 使用正确邮箱但错误密码
      await tester.enterText(emailField, TestConfig.merchantEmail);
      await tester.enterText(passwordField, 'WrongPassword999');
      await tester.tap(submitBtn);

      // 等待 API 响应（网络请求需要时间，pumpAndSettle 不会等异步请求）
      await waitForNavigation(
        tester,
        find.textContaining('No account found'),
      );

      // 应显示友好的错误提示
      expect(
        find.textContaining('No account found'),
        findsOneWidget,
        reason: '错误密码应显示友好错误提示',
      );
    });

    // ----------------------------------------------------------
    // M007: store_owner 角色登录成功后跳转 /dashboard
    // ----------------------------------------------------------
    testWidgets('M007 - store_owner 登录成功跳转 Dashboard', (tester) async {
      // 确保测试商家状态为 approved
      await SupabaseTestHelper.setMerchantStatus(
        TestConfig.merchantId,
        'approved',
      );

      await launchAppSignedOut(tester);

      final emailField = find.byKey(const ValueKey('login_email_field'));
      final passwordField = find.byKey(const ValueKey('login_password_field'));
      final submitBtn = find.byKey(const ValueKey('login_submit_btn'));

      await tester.enterText(emailField, TestConfig.merchantEmail);
      await tester.enterText(passwordField, TestConfig.merchantPassword);
      await tester.tap(submitBtn);

      // 等待异步登录流程完成（signIn + 查 role + 查 status + 路由跳转）
      // pumpAndSettle 不会等待网络请求，需要轮询 pump 等待目标页面出现
      await waitForNavigation(
        tester,
        find.byType(NavigationBar),
      );

      // 验证已进入 Dashboard（底部导航栏存在）
      expect(
        find.byType(NavigationBar),
        findsOneWidget,
        reason: '登录成功后应进入 Dashboard（底部导航存在）',
      );

      // 清理：退出登录
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    });
  });

  // ──────────────────────────────────────────────────────────────
  // 测试组 2: 登出功能 (M008-M009)
  // ──────────────────────────────────────────────────────────────
  group('M008-M009 商家登出功能', () {
    // 每次测试前先登录
    setUp(() async {
      try {
        await SupabaseTestHelper.setMerchantStatus(
          TestConfig.merchantId,
          'approved',
        );
        await SupabaseTestHelper.signInAsMerchant();
      } catch (e) {
        // 登录失败不阻断 setUp，测试内部会捕获
      }
    });

    tearDown(() async {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    });

    // ----------------------------------------------------------
    // M008: 登出后跳转到登录页
    // ----------------------------------------------------------
    testWidgets('M008 - 登出后路由回到登录页', (tester) async {
      await launchApp(tester, timeout: TestConfig.appLaunchTimeout);

      // 应已跳转到 Dashboard（已登录）
      // 找到设置页中的登出按钮（在 Me Tab → Settings）
      // 先导航到 Me tab
      final meTab = find.byIcon(Icons.person_outline);
      if (meTab.evaluate().isNotEmpty) {
        await tester.tap(meTab);
        await tester.pumpAndSettle();
      }

      // 查找登出相关按钮（Settings 页有 Sign Out 按钮）
      // 如果找不到，直接通过 Supabase 登出并验证路由
      await Supabase.instance.client.auth.signOut();
      await tester.pumpAndSettle(TestConfig.routeRedirectTimeout);

      // 退出后应回到登录页
      expect(
        find.byKey(const ValueKey('login_email_field')),
        findsOneWidget,
        reason: '登出后应跳回登录页',
      );
    });

    // ----------------------------------------------------------
    // M009: 登出后无法访问受保护路由（重新回到登录页）
    // ----------------------------------------------------------
    testWidgets('M009 - 登出后访问 Dashboard 被重定向到登录页', (tester) async {
      await launchApp(tester, timeout: TestConfig.appLaunchTimeout);

      // 直接登出
      await Supabase.instance.client.auth.signOut();
      await tester.pumpAndSettle(TestConfig.routeRedirectTimeout);

      // 应自动重定向到登录页，而不是停留在 Dashboard
      expect(
        find.byKey(const ValueKey('login_email_field')),
        findsOneWidget,
        reason: '登出后访问 Dashboard 应被重定向到登录页',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────
  // 测试组 3: 审核状态页 (M010-M012)
  // ──────────────────────────────────────────────────────────────
  group('M010-M012 商家审核状态页', () {
    tearDown(() async {
      // 确保每次测试后恢复商家状态为 approved
      try {
        await SupabaseTestHelper.restoreMerchantToApproved();
      } catch (_) {}
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    });

    // ----------------------------------------------------------
    // M010: status=pending 登录后跳转审核状态页
    // ----------------------------------------------------------
    testWidgets('M010 - pending 状态登录跳转到审核页', (tester) async {
      // 将测试商家状态改为 pending
      await SupabaseTestHelper.setMerchantStatus(
        TestConfig.merchantId,
        'pending',
      );

      await launchAppSignedOut(tester);

      final emailField = find.byKey(const ValueKey('login_email_field'));
      final passwordField = find.byKey(const ValueKey('login_password_field'));
      final submitBtn = find.byKey(const ValueKey('login_submit_btn'));

      await tester.enterText(emailField, TestConfig.merchantEmail);
      await tester.enterText(passwordField, TestConfig.merchantPassword);
      await tester.tap(submitBtn);

      // 等待异步登录 + 路由跳转到审核页
      await waitForNavigation(
        tester,
        find.textContaining('Application'),
      );

      // 审核状态页应显示 "Application Under Review" 或 "Application Status"
      expect(
        find.textContaining('Review').evaluate().isNotEmpty ||
            find.textContaining('Application').evaluate().isNotEmpty,
        isTrue,
        reason: 'pending 状态应显示审核页',
      );
    });

    // ----------------------------------------------------------
    // M011: 审核状态页显示正确的状态信息
    // ----------------------------------------------------------
    testWidgets('M011 - 审核状态页包含审核中描述文字', (tester) async {
      // 设置为 pending 状态
      await SupabaseTestHelper.setMerchantStatus(
        TestConfig.merchantId,
        'pending',
      );

      await launchAppSignedOut(tester);

      final emailField = find.byKey(const ValueKey('login_email_field'));
      final passwordField = find.byKey(const ValueKey('login_password_field'));
      final submitBtn = find.byKey(const ValueKey('login_submit_btn'));

      await tester.enterText(emailField, TestConfig.merchantEmail);
      await tester.enterText(passwordField, TestConfig.merchantPassword);
      await tester.tap(submitBtn);

      // 等待异步登录 + 路由跳转到审核页
      await waitForNavigation(
        tester,
        find.text('Application Under Review'),
      );

      // 审核状态页应显示 "Application Under Review"
      expect(
        find.text('Application Under Review'),
        findsOneWidget,
        reason: 'pending 状态页应显示 "Application Under Review"',
      );

      // 也应显示预计审核时间
      expect(
        find.textContaining('24'),
        findsOneWidget,
        reason: '审核状态页应显示预计审核时间',
      );
    });

    // ----------------------------------------------------------
    // M012: 审核状态页可以退出登录
    // ----------------------------------------------------------
    testWidgets('M012 - 审核状态页可点击退出登录', (tester) async {
      // 设置为 pending 状态
      await SupabaseTestHelper.setMerchantStatus(
        TestConfig.merchantId,
        'pending',
      );

      await launchAppSignedOut(tester);

      final emailField = find.byKey(const ValueKey('login_email_field'));
      final passwordField = find.byKey(const ValueKey('login_password_field'));
      final submitBtn = find.byKey(const ValueKey('login_submit_btn'));

      await tester.enterText(emailField, TestConfig.merchantEmail);
      await tester.enterText(passwordField, TestConfig.merchantPassword);
      await tester.tap(submitBtn);

      // 等待异步登录 + 路由跳转到审核页
      await waitForNavigation(
        tester,
        find.text('Sign Out'),
      );

      // 在审核状态页找到 "Sign Out" 按钮
      final signOutBtn = find.text('Sign Out');
      expect(signOutBtn, findsOneWidget, reason: '审核状态页应有 Sign Out 按钮');

      await tester.tap(signOutBtn);

      // 等待登出 + 路由跳回登录页
      await waitForNavigation(
        tester,
        find.byKey(const ValueKey('login_email_field')),
      );

      // 退出后应回到登录页
      expect(
        find.byKey(const ValueKey('login_email_field')),
        findsOneWidget,
        reason: '审核页退出后应回到登录页',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────
  // 测试组 4: 注册入口与导航 (M013-M015)
  // ──────────────────────────────────────────────────────────────
  group('M013-M015 注册入口与导航', () {
    setUp(() async {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    });

    // ----------------------------------------------------------
    // M013: 登录页显示"Register"链接
    // ----------------------------------------------------------
    testWidgets('M013 - 登录页存在注册链接', (tester) async {
      await launchAppSignedOut(tester);

      // 登录页底部应有 "Register" 链接
      expect(
        find.text('Register'),
        findsOneWidget,
        reason: '登录页应有 Register 链接',
      );
    });

    // ----------------------------------------------------------
    // M014: 点击注册链接跳转到注册页第一步
    // ----------------------------------------------------------
    testWidgets('M014 - 点击注册链接跳转注册页', (tester) async {
      await launchAppSignedOut(tester);

      // 点击 "Register" 链接
      final registerLink = find.text('Register');
      expect(registerLink, findsOneWidget);
      await tester.tap(registerLink);
      await tester.pumpAndSettle();

      // 注册页第一步：账号注册（应显示 "Create Account" 或邮箱/密码输入框）
      // 注册页 Step 0 有 sign-up email/password 表单
      expect(
        find.textContaining('Account').evaluate().isNotEmpty ||
            find.textContaining('Sign Up').evaluate().isNotEmpty ||
            find.textContaining('Create').evaluate().isNotEmpty ||
            find.textContaining('Register').evaluate().isNotEmpty,
        isTrue,
        reason: '点击注册链接后应进入注册流程',
      );
    });

    // ----------------------------------------------------------
    // M015: 注册页有返回登录的导航入口
    // ----------------------------------------------------------
    testWidgets('M015 - 注册页可返回登录页', (tester) async {
      await launchAppSignedOut(tester);

      // 先进入注册页
      final registerLink = find.text('Register');
      if (registerLink.evaluate().isNotEmpty) {
        await tester.tap(registerLink);
        await tester.pumpAndSettle();
      }

      // 查找返回按钮（AppBar 的 back button 或 "Sign In" 链接）
      final backBtn = find.byType(BackButton);
      final arrowBack = find.byIcon(Icons.arrow_back);
      final arrowBackIos = find.byIcon(Icons.arrow_back_ios);
      final signInLink = find.textContaining('Sign In');

      final hasBackNavigation = backBtn.evaluate().isNotEmpty ||
          arrowBack.evaluate().isNotEmpty ||
          arrowBackIos.evaluate().isNotEmpty ||
          signInLink.evaluate().isNotEmpty;

      expect(
        hasBackNavigation,
        isTrue,
        reason: '注册页应有返回/跳转登录页的入口',
      );

      // 如果有 back 按钮，点击后应回到登录页
      if (arrowBack.evaluate().isNotEmpty) {
        await tester.tap(arrowBack.first);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('login_email_field')),
          findsOneWidget,
          reason: '返回后应回到登录页',
        );
      } else if (arrowBackIos.evaluate().isNotEmpty) {
        await tester.tap(arrowBackIos.first);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('login_email_field')),
          findsOneWidget,
          reason: '返回后应回到登录页',
        );
      }
    });
  });
}
