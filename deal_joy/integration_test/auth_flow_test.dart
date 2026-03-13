import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/test_config.dart';
import 'helpers/app_launcher.dart';
import 'helpers/supabase_test_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 每次 testWidgets 之间共享的 helper 实例（用于 signOut 清理）
  final helper = SupabaseTestHelper();

  // ============================================================
  // C001-C008：登录流程
  // ============================================================
  group('登录流程 (C001-C008)', () {
    // C001：邮箱输入框可正常输入
    testWidgets('C001 - 邮箱输入框可正常输入', (tester) async {
      await launchApp(tester);

      // App 未登录状态下应跳转到 /auth/login，可找到邮箱输入框
      final emailField = find.byKey(const ValueKey('login_email_field'));
      expect(emailField, findsOneWidget);

      await tester.enterText(emailField, 'test@example.com');
      await tester.pumpAndSettle();

      // 验证输入框内容已更新
      expect(find.text('test@example.com'), findsOneWidget);
    });

    // C002：密码输入框可正常输入，且密码内容被隐藏
    testWidgets('C002 - 密码输入框可正常输入（密码隐藏）', (tester) async {
      await launchApp(tester);

      final passwordField = find.byKey(const ValueKey('login_password_field'));
      expect(passwordField, findsOneWidget);

      await tester.enterText(passwordField, 'password123');
      await tester.pumpAndSettle();

      // AppTextField 使用 obscureText: true，查找 EditableText 验证 obscureText 属性
      final editableText = tester.widget<EditableText>(
        find.descendant(
          of: passwordField,
          matching: find.byType(EditableText),
        ),
      );
      expect(editableText.obscureText, isTrue);
    });

    // C003：邮箱格式校验（输入无效邮箱后点击登录，显示错误提示）
    testWidgets('C003 - 邮箱格式校验错误提示', (tester) async {
      await launchApp(tester);

      // 输入无效邮箱格式
      await tester.enterText(
        find.byKey(const ValueKey('login_email_field')),
        'invalid-email',
      );
      await tester.enterText(
        find.byKey(const ValueKey('login_password_field')),
        'password123',
      );

      // 点击 Sign In 按钮触发表单校验
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      // 应出现邮箱格式错误提示
      expect(find.text('Enter a valid email address'), findsOneWidget);
    });

    // C004：密码少于 8 位时显示错误提示
    testWidgets('C004 - 密码长度不足 8 位校验错误提示', (tester) async {
      await launchApp(tester);

      await tester.enterText(
        find.byKey(const ValueKey('login_email_field')),
        'valid@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('login_password_field')),
        'short',
      );

      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      // 应出现密码长度不足提示
      expect(
        find.text('Password must be at least 8 characters'),
        findsOneWidget,
      );
    });

    // C005：邮箱和密码为空时提交，显示必填错误
    testWidgets('C005 - 空邮箱和空密码提交显示必填错误', (tester) async {
      await launchApp(tester);

      // 不输入任何内容，直接点击登录
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    // C006：Forgot Password 链接存在且可点击，跳转到重置密码页
    testWidgets('C006 - Forgot Password 链接跳转到重置密码页', (tester) async {
      await launchApp(tester);

      final forgotBtn = find.byKey(const ValueKey('login_forgot_password_btn'));
      expect(forgotBtn, findsOneWidget);

      await tester.tap(forgotBtn);
      await waitForRoute(tester);

      // 重置密码页应包含 "Reset Password" 标题
      expect(find.text('Reset Password'), findsOneWidget);
    });

    // C007：Sign Up 链接存在且可点击，跳转到注册页
    testWidgets('C007 - Sign Up 链接跳转到注册页', (tester) async {
      await launchApp(tester);

      final signupBtn = find.byKey(const ValueKey('login_signup_btn'));
      expect(signupBtn, findsOneWidget);

      await tester.tap(signupBtn);
      await waitForRoute(tester);

      // 注册页应包含 Create Account 标题
      expect(find.text('Create Account'), findsOneWidget);
    });

    // C008：用正确凭据登录成功，跳转到 /home
    testWidgets('C008 - 正确凭据登录成功跳转 /home', (tester) async {
      await launchApp(tester);

      await tester.enterText(
        find.byKey(const ValueKey('login_email_field')),
        TestConfig.customerEmail,
      );
      await tester.enterText(
        find.byKey(const ValueKey('login_password_field')),
        TestConfig.customerPassword,
      );

      await tester.tap(find.text('Sign In'));

      // 登录是网络请求，等待更长时间
      await waitForNetwork(tester);

      // 登录成功后应跳转到首页，底部 Tab 应可见
      // 首页有 Featured Deals 文字或底部导航栏
      expect(
        find.byType(BottomNavigationBar).evaluate().isNotEmpty ||
            find.text('For You').evaluate().isNotEmpty ||
            find.text('Home').evaluate().isNotEmpty,
        isTrue,
      );

      // 测试结束后退出登录，避免影响后续测试
      await helper.signInAsCustomer().then((token) async {
        if (token != null) await helper.signOut(token);
      });
    });
  });

  // ============================================================
  // C009-C016：注册流程
  // ============================================================
  group('注册流程 (C009-C016)', () {
    /// 辅助函数：启动 App 并导航到注册页
    Future<void> navigateToRegister(WidgetTester tester) async {
      await launchApp(tester);
      // 通过 Sign Up 链接导航到注册页
      await tester.tap(find.byKey(const ValueKey('login_signup_btn')));
      await waitForRoute(tester);
      // 确认已到达注册页
      expect(find.text('Create Account'), findsOneWidget);
    }

    // C009：注册页 Username 字段存在且可输入
    testWidgets('C009 - Username 字段存在且可输入', (tester) async {
      await navigateToRegister(tester);

      final usernameField = find.byKey(
        const ValueKey('register_username_field'),
      );
      expect(usernameField, findsOneWidget);

      await tester.enterText(usernameField, 'testuser123');
      await tester.pumpAndSettle();
      expect(find.text('testuser123'), findsOneWidget);
    });

    // C010：注册页 Full Name 字段存在且可输入
    testWidgets('C010 - Full Name 字段存在且可输入', (tester) async {
      await navigateToRegister(tester);

      final fullNameField = find.byKey(
        const ValueKey('register_full_name_field'),
      );
      expect(fullNameField, findsOneWidget);

      await tester.enterText(fullNameField, 'Test User');
      await tester.pumpAndSettle();
      expect(find.text('Test User'), findsOneWidget);
    });

    // C011：注册页 Email 字段存在且可输入
    testWidgets('C011 - Email 字段存在且可输入', (tester) async {
      await navigateToRegister(tester);

      final emailField = find.byKey(
        const ValueKey('register_email_field'),
      );
      expect(emailField, findsOneWidget);

      await tester.enterText(emailField, 'newuser@example.com');
      await tester.pumpAndSettle();
      expect(find.text('newuser@example.com'), findsOneWidget);
    });

    // C012：注册页密码字段存在，且内容被隐藏（obscureText）
    testWidgets('C012 - 密码字段存在且内容被隐藏', (tester) async {
      await navigateToRegister(tester);

      final passwordField = find.byKey(
        const ValueKey('register_password_field'),
      );
      expect(passwordField, findsOneWidget);

      await tester.enterText(passwordField, 'TestPass123');
      await tester.pumpAndSettle();

      // 验证 obscureText 为 true
      final editableText = tester.widget<EditableText>(
        find.descendant(
          of: passwordField,
          matching: find.byType(EditableText),
        ),
      );
      expect(editableText.obscureText, isTrue);
    });

    // C013：注册页确认密码字段存在，两次密码不匹配时显示错误
    testWidgets('C013 - 确认密码不匹配时显示错误提示', (tester) async {
      await navigateToRegister(tester);

      await tester.enterText(
        find.byKey(const ValueKey('register_username_field')),
        'testuser',
      );
      await tester.enterText(
        find.byKey(const ValueKey('register_full_name_field')),
        'Test User',
      );
      await tester.enterText(
        find.byKey(const ValueKey('register_email_field')),
        'test@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('register_password_field')),
        'TestPass123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('register_confirm_password_field')),
        'DifferentPass123',
      );
      await tester.pumpAndSettle();

      // 实时不匹配提示应立即显示（不需要点击提交）
      expect(find.text('Passwords do not match'), findsWidgets);
    });

    // C014：密码强度指示器在输入密码时可见
    testWidgets('C014 - 密码强度指示器在输入时可见', (tester) async {
      await navigateToRegister(tester);

      // 输入弱密码（纯小写）
      await tester.enterText(
        find.byKey(const ValueKey('register_password_field')),
        'weakpass',
      );
      await tester.pumpAndSettle();

      // PasswordStrengthIndicator widget 应当存在于树中
      // 由于它是自定义 widget，检查其内部的进度条或颜色指示
      expect(find.byType(LinearProgressIndicator), findsWidgets);
    });

    // C015：未勾选服务条款时 Create Account 按钮应被禁用
    testWidgets('C015 - 未勾选服务条款时注册按钮禁用', (tester) async {
      await navigateToRegister(tester);

      // 填写所有字段但不勾选 ToS
      await tester.enterText(
        find.byKey(const ValueKey('register_username_field')),
        'testuser',
      );
      await tester.enterText(
        find.byKey(const ValueKey('register_full_name_field')),
        'Test User',
      );
      await tester.enterText(
        find.byKey(const ValueKey('register_email_field')),
        'test@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('register_password_field')),
        'TestPass123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('register_confirm_password_field')),
        'TestPass123',
      );
      await tester.pumpAndSettle();

      // Create Account 按钮的 onPressed 应为 null（disabled）
      // AppButton 内部用 onPressed == null 来禁用
      final createBtn = find.text('Create Account');
      expect(createBtn, findsOneWidget);

      // 找到 ElevatedButton 并验证其 onPressed 为 null
      final elevatedButton = tester.widget<ElevatedButton>(
        find.ancestor(
          of: createBtn,
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(elevatedButton.onPressed, isNull);
    });

    // C016：勾选服务条款后 Create Account 按钮变为可用
    testWidgets('C016 - 勾选服务条款后注册按钮变为可用', (tester) async {
      await navigateToRegister(tester);

      // 填写所有字段
      await tester.enterText(
        find.byKey(const ValueKey('register_username_field')),
        'testuser',
      );
      await tester.enterText(
        find.byKey(const ValueKey('register_full_name_field')),
        'Test User',
      );
      await tester.enterText(
        find.byKey(const ValueKey('register_email_field')),
        'test@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('register_password_field')),
        'TestPass123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('register_confirm_password_field')),
        'TestPass123',
      );
      await tester.pumpAndSettle();

      // 勾选服务条款 Checkbox
      final checkbox = find.byType(Checkbox).first;
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      // Create Account 按钮的 onPressed 应不为 null（enabled）
      final createBtn = find.text('Create Account');
      final elevatedButton = tester.widget<ElevatedButton>(
        find.ancestor(
          of: createBtn,
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(elevatedButton.onPressed, isNotNull);
    });
  });

  // ============================================================
  // C017-C022：忘记密码 / 重置密码流程
  // ============================================================
  group('忘记密码/重置密码 (C017-C022)', () {
    /// 辅助函数：启动 App 并导航到忘记密码页
    Future<void> navigateToForgotPassword(WidgetTester tester) async {
      await launchApp(tester);
      await tester.tap(find.byKey(const ValueKey('login_forgot_password_btn')));
      await waitForRoute(tester);
      // 确认已到达忘记密码页
      expect(find.text('Reset Password'), findsOneWidget);
    }

    // C017：忘记密码页面存在邮箱输入框
    testWidgets('C017 - 忘记密码页面邮箱输入框存在', (tester) async {
      await navigateToForgotPassword(tester);

      final emailField = find.byKey(
        const ValueKey('forgot_password_email_field'),
      );
      expect(emailField, findsOneWidget);
    });

    // C018：忘记密码页面邮箱输入框可正常输入
    testWidgets('C018 - 忘记密码页面邮箱可输入', (tester) async {
      await navigateToForgotPassword(tester);

      await tester.enterText(
        find.byKey(const ValueKey('forgot_password_email_field')),
        'user@example.com',
      );
      await tester.pumpAndSettle();
      expect(find.text('user@example.com'), findsOneWidget);
    });

    // C019：空邮箱提交时显示必填错误
    testWidgets('C019 - 空邮箱提交显示必填错误', (tester) async {
      await navigateToForgotPassword(tester);

      // 不输入邮箱，点击 Send Reset Link
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(find.text('Email is required'), findsOneWidget);
    });

    // C020：邮箱格式无效时显示格式错误
    testWidgets('C020 - 无效邮箱格式显示格式错误', (tester) async {
      await navigateToForgotPassword(tester);

      await tester.enterText(
        find.byKey(const ValueKey('forgot_password_email_field')),
        'not-an-email',
      );
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address'), findsOneWidget);
    });

    // C021：发送重置链接后显示成功状态（邮件发送提示）
    testWidgets('C021 - 发送重置链接后显示成功提示', (tester) async {
      await navigateToForgotPassword(tester);

      // 输入真实测试账号邮箱（Supabase 会发送重置邮件）
      await tester.enterText(
        find.byKey(const ValueKey('forgot_password_email_field')),
        TestConfig.customerEmail,
      );

      await tester.tap(find.text('Send Reset Link'));

      // 等待网络请求完成
      await waitForNetwork(tester);

      // 成功发送后页面切换为成功视图，显示 "Check your email"
      expect(find.text('Check your email'), findsOneWidget);
    });

    // C022：成功视图中 Resend Link 按钮存在，且在冷却期内处于禁用状态
    testWidgets('C022 - 成功发送后 Resend Link 按钮在冷却期禁用', (tester) async {
      await navigateToForgotPassword(tester);

      await tester.enterText(
        find.byKey(const ValueKey('forgot_password_email_field')),
        TestConfig.customerEmail,
      );
      await tester.tap(find.text('Send Reset Link'));
      await waitForNetwork(tester);

      // 成功视图应显示 Resend Link 按钮（带倒计时文字）
      // 冷却期内按钮文字格式为 "Resend Link (Xs)"
      final resendBtn = find.textContaining('Resend Link');
      expect(resendBtn, findsOneWidget);

      // 冷却期内 ElevatedButton 的 onPressed 应为 null（禁用）
      final elevatedButton = tester.widget<ElevatedButton>(
        find.ancestor(
          of: resendBtn,
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(elevatedButton.onPressed, isNull);
    });
  });
}
