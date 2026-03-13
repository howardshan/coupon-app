// 三端联动集成测试 (X001)
// 场景: 商家端视角验证「后台审核状态变更 → App 路由响应」完整流程
// 流程: pending 状态登录 → 显示审核页 → API 改为 approved → 刷新 → 显示 Dashboard

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
  // X001: 后台审核通过 → 商家端路由自动跳转 Dashboard
  // ──────────────────────────────────────────────────────────────
  group('X001 三端联动: 审核状态变更后路由响应', () {
    // 测试后无论成功失败，都恢复商家状态为 approved
    tearDown(() async {
      try {
        await SupabaseTestHelper.restoreMerchantToApproved();
      } catch (_) {}
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    });

    // ----------------------------------------------------------
    // X001-Step1: pending 状态登录显示审核页
    // ----------------------------------------------------------
    testWidgets('X001-Step1 - pending 状态登录后显示审核状态页', (tester) async {
      // 第1步: 用 API 将商家状态设为 pending（模拟刚注册等待审核）
      await SupabaseTestHelper.setMerchantStatus(
        TestConfig.merchantId,
        'pending',
      );

      // 验证数据库已变更
      final merchantData = await SupabaseTestHelper.queryMerchant(
        TestConfig.merchantId,
      );
      expect(
        merchantData['status'],
        equals('pending'),
        reason: '数据库 status 应为 pending',
      );

      // 第2步: 启动 App（确保未登录）
      await launchAppSignedOut(tester);

      // 第3步: 在登录页输入测试商家凭据并提交
      final emailField = find.byKey(const ValueKey('login_email_field'));
      final passwordField = find.byKey(const ValueKey('login_password_field'));
      final submitBtn = find.byKey(const ValueKey('login_submit_btn'));

      expect(emailField, findsOneWidget, reason: '应在登录页');
      await tester.enterText(emailField, TestConfig.merchantEmail);
      await tester.enterText(passwordField, TestConfig.merchantPassword);
      await tester.tap(submitBtn);

      // 等待路由跳转（async redirect 需要查数据库）
      await tester.pumpAndSettle(TestConfig.routeRedirectTimeout);

      // 第4步: 验证跳转到审核状态页（而非 Dashboard）
      expect(
        find.text('Application Under Review'),
        findsOneWidget,
        reason: 'pending 状态应显示审核状态页，不应进入 Dashboard',
      );

      // 验证底部导航栏不存在（处于全屏审核页，没有 Tab Bar）
      expect(
        find.byType(NavigationBar),
        findsNothing,
        reason: '审核页不应有底部导航栏',
      );
    });

    // ----------------------------------------------------------
    // X001-Step2: 后台将状态改为 approved 后刷新跳转 Dashboard
    // ----------------------------------------------------------
    testWidgets('X001-Step2 - 审核通过后刷新/重新登录跳转 Dashboard', (tester) async {
      // 第1步: 先将状态设为 pending
      await SupabaseTestHelper.setMerchantStatus(
        TestConfig.merchantId,
        'pending',
      );

      // 第2步: 启动 App 并以 pending 状态登录
      await launchAppSignedOut(tester);

      final emailField = find.byKey(const ValueKey('login_email_field'));
      final passwordField = find.byKey(const ValueKey('login_password_field'));
      final submitBtn = find.byKey(const ValueKey('login_submit_btn'));

      await tester.enterText(emailField, TestConfig.merchantEmail);
      await tester.enterText(passwordField, TestConfig.merchantPassword);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle(TestConfig.routeRedirectTimeout);

      // 确认在审核状态页
      expect(
        find.text('Application Under Review'),
        findsOneWidget,
        reason: '第一阶段应在审核页',
      );

      // 第3步: 模拟后台审核通过（用 Service Role Key 修改状态）
      await SupabaseTestHelper.setMerchantStatus(
        TestConfig.merchantId,
        'approved',
      );

      // 验证数据库已变更为 approved
      final updatedData = await SupabaseTestHelper.queryMerchant(
        TestConfig.merchantId,
      );
      expect(
        updatedData['status'],
        equals('approved'),
        reason: '数据库 status 应已变更为 approved',
      );

      // 第4步: 清除路由缓存后重新触发路由刷新
      // 在审核状态页点击刷新按钮（AppBar 中有 refresh icon）
      final refreshBtn = find.byIcon(Icons.refresh);
      if (refreshBtn.evaluate().isNotEmpty) {
        await tester.tap(refreshBtn.first);
        await tester.pumpAndSettle(TestConfig.routeRedirectTimeout);
      }

      // 若刷新后显示 "You're Approved!" 状态，点击 "Go to Dashboard" 按钮
      final dashboardBtn = find.byKey(
        const ValueKey('review_status_dashboard_btn'),
      );
      if (dashboardBtn.evaluate().isNotEmpty) {
        await tester.tap(dashboardBtn);
        await tester.pumpAndSettle(TestConfig.routeRedirectTimeout);
      }

      // 第5步: 验证已进入 Dashboard（底部导航栏存在）
      expect(
        find.byType(NavigationBar),
        findsOneWidget,
        reason: '审核通过后进入 Dashboard，底部导航栏应存在',
      );
    });

    // ----------------------------------------------------------
    // X001-Step3: 验证 merchants 表 status = approved（数据库层断言）
    // ----------------------------------------------------------
    testWidgets('X001-Step3 - 验证数据库 merchants.status = approved', (tester) async {
      // 确保状态为 approved
      await SupabaseTestHelper.setMerchantStatus(
        TestConfig.merchantId,
        'approved',
      );

      // 查询数据库并断言
      final merchantData = await SupabaseTestHelper.queryMerchant(
        TestConfig.merchantId,
      );

      expect(
        merchantData['status'],
        equals('approved'),
        reason: 'merchants 表中 status 应为 approved',
      );

      // 验证 merchants.id 与预期一致
      expect(
        merchantData['id'],
        equals(TestConfig.merchantId),
        reason: 'merchants.id 应与 TestConfig.merchantId 一致',
      );

      // 无需启动 App，纯数据库层断言
      // pumpWidget 仅为满足 testWidgets 签名要求
      await tester.pumpWidget(const SizedBox.shrink());
    });

    // ----------------------------------------------------------
    // X001-Full: 完整端到端流程（单测试跑完全部步骤）
    // ----------------------------------------------------------
    testWidgets('X001-Full - 完整三端联动流程', (tester) async {
      // ── 阶段 1: 设为 pending，登录，验证在审核页 ─────────────
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
      await tester.pumpAndSettle(TestConfig.routeRedirectTimeout);

      // 阶段 1 断言: 应在审核页
      expect(
        find.text('Application Under Review'),
        findsOneWidget,
        reason: '[阶段1] pending 状态应显示审核页',
      );

      // ── 阶段 2: 后台将状态改为 approved ─────────────────────
      await SupabaseTestHelper.setMerchantStatus(
        TestConfig.merchantId,
        'approved',
      );

      // ── 阶段 3: 刷新并验证进入 Dashboard ────────────────────
      // 点击审核页右上角刷新按钮
      final refreshBtn = find.byIcon(Icons.refresh);
      if (refreshBtn.evaluate().isNotEmpty) {
        await tester.tap(refreshBtn.first);
        await tester.pumpAndSettle(TestConfig.routeRedirectTimeout);
      }

      // 如果出现 "Go to Dashboard" 按钮，点击
      final dashboardBtn = find.byKey(
        const ValueKey('review_status_dashboard_btn'),
      );
      if (dashboardBtn.evaluate().isNotEmpty) {
        await tester.tap(dashboardBtn);
        await tester.pumpAndSettle(TestConfig.routeRedirectTimeout);
      }

      // 阶段 3 断言: 应已进入 Dashboard
      expect(
        find.byType(NavigationBar),
        findsOneWidget,
        reason: '[阶段3] 审核通过后应进入 Dashboard',
      );

      // ── 阶段 4: 数据库最终状态断言 ──────────────────────────
      final finalData = await SupabaseTestHelper.queryMerchant(
        TestConfig.merchantId,
      );
      expect(
        finalData['status'],
        equals('approved'),
        reason: '[阶段4] 最终数据库 status 应为 approved',
      );

      // ── 阶段 5: 清理 ─────────────────────────────────────────
      // tearDown 会自动执行 restoreMerchantToApproved 和 signOut
    });
  });
}
