# 测试代码模式参考

> 测试工程师 Agent 的核心参考。

## 1. Flutter Widget 测试模板

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

// Mock 类
class MockAuthService extends Mock implements AuthService {}

/// 测试辅助：包裹 Widget 在必要的 Provider 中
Widget createTestWidget(Widget child, {List<Override>? overrides}) {
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp(home: child),
  );
}

void main() {
  late MockAuthService mockAuthService;

  setUp(() {
    mockAuthService = MockAuthService();
  });

  group('RegisterPage', () {
    // 渲染测试
    testWidgets('renders all form fields', (tester) async {
      await tester.pumpWidget(createTestWidget(const RegisterPage()));

      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
    });

    // 表单校验测试
    testWidgets('shows error for empty email', (tester) async {
      await tester.pumpWidget(createTestWidget(const RegisterPage()));

      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      expect(find.text('Email is required'), findsOneWidget);
    });

    testWidgets('shows error for invalid email', (tester) async {
      await tester.pumpWidget(createTestWidget(const RegisterPage()));

      await tester.enterText(
        find.byType(TextFormField).first,
        'not-an-email',
      );
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid email'), findsOneWidget);
    });

    testWidgets('shows error for weak password', (tester) async {
      await tester.pumpWidget(createTestWidget(const RegisterPage()));

      await tester.enterText(find.byType(TextFormField).first, 'test@test.com');
      await tester.enterText(find.byType(TextFormField).last, '123');
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    });

    // 加载状态测试
    testWidgets('shows loading indicator when submitting', (tester) async {
      // 模拟慢响应
      when(() => mockAuthService.register(
        email: any(named: 'email'),
        password: any(named: 'password'),
        username: any(named: 'username'),
      )).thenAnswer((_) async {
        await Future.delayed(const Duration(seconds: 2));
        return 'user-id';
      });

      await tester.pumpWidget(createTestWidget(
        const RegisterPage(),
        overrides: [
          authServiceProvider.overrideWithValue(mockAuthService),
        ],
      ));

      // 填写有效表单
      await tester.enterText(find.byType(TextFormField).at(0), 'test@test.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'Test1234');
      await tester.enterText(find.byType(TextFormField).at(2), 'testuser');
      await tester.tap(find.text('Sign Up'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // 错误处理测试
    testWidgets('shows snackbar on API error', (tester) async {
      when(() => mockAuthService.register(
        email: any(named: 'email'),
        password: any(named: 'password'),
        username: any(named: 'username'),
      )).thenThrow(AppException(
        code: 'EMAIL_EXISTS',
        message: 'This email is already registered',
      ));

      await tester.pumpWidget(createTestWidget(
        const RegisterPage(),
        overrides: [
          authServiceProvider.overrideWithValue(mockAuthService),
        ],
      ));

      await tester.enterText(find.byType(TextFormField).at(0), 'test@test.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'Test1234');
      await tester.enterText(find.byType(TextFormField).at(2), 'testuser');
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      expect(find.text('This email is already registered'), findsOneWidget);
    });
  });
}
```

## 2. Riverpod Provider 测试模板

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late ProviderContainer container;
  late MockAuthService mockAuthService;

  setUp(() {
    mockAuthService = MockAuthService();
    container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(mockAuthService),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('AuthNotifier', () {
    test('initial state is unauthenticated', () {
      final state = container.read(authNotifierProvider);
      expect(state.status, AuthStatus.initial);
    });

    test('login success updates state to authenticated', () async {
      when(() => mockAuthService.login('test@test.com', 'Test1234'))
          .thenAnswer((_) async => 'user-123');

      await container.read(authNotifierProvider.notifier).login(
        'test@test.com',
        'Test1234',
      );

      final state = container.read(authNotifierProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.userId, 'user-123');
    });

    test('login failure updates state to error', () async {
      when(() => mockAuthService.login(any(), any()))
          .thenThrow(AppException(
            code: 'INVALID_CREDENTIALS',
            message: 'Incorrect email or password',
          ));

      await container.read(authNotifierProvider.notifier).login(
        'wrong@test.com',
        'wrong',
      );

      final state = container.read(authNotifierProvider);
      expect(state.status, AuthStatus.error);
      expect(state.errorMessage, contains('Incorrect'));
    });
  });
}
```

## 3. Deno Edge Function 测试模板

```typescript
// tests/auth-register.test.ts
import { assertEquals } from "https://deno.land/std@0.177.0/testing/asserts.ts";

const BASE_URL = Deno.env.get("SUPABASE_URL") + "/functions/v1";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");

// 辅助函数
async function callFunction(name: string, body: unknown) {
  const res = await fetch(`${BASE_URL}/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${ANON_KEY}`,
    },
    body: JSON.stringify(body),
  });
  return { status: res.status, data: await res.json() };
}

// 正常流程
Deno.test("TC001: 正常邮箱注册", async () => {
  const uniqueEmail = `test_${Date.now()}@example.com`;
  const { status, data } = await callFunction("auth-register", {
    email: uniqueEmail,
    password: "Test1234",
    username: `user_${Date.now()}`,
  });

  assertEquals(status, 200);
  assertEquals(data.success, true);
  assertEquals(typeof data.data.user_id, "string");
});

// 异常: 重复邮箱
Deno.test("TC002: 重复邮箱注册返回 EMAIL_EXISTS", async () => {
  const email = `dup_${Date.now()}@example.com`;
  const body = { email, password: "Test1234", username: `user_${Date.now()}` };

  // 第一次注册
  await callFunction("auth-register", body);
  // 第二次注册
  const { data } = await callFunction("auth-register", {
    ...body,
    username: `user2_${Date.now()}`,
  });

  assertEquals(data.success, false);
  assertEquals(data.error.code, "EMAIL_EXISTS");
});

// 异常: 弱密码
Deno.test("TC003: 弱密码返回 WEAK_PASSWORD", async () => {
  const { data } = await callFunction("auth-register", {
    email: `test_${Date.now()}@example.com`,
    password: "123",
    username: `user_${Date.now()}`,
  });

  assertEquals(data.success, false);
  assertEquals(data.error.code, "WEAK_PASSWORD");
});

// 异常: 无效邮箱格式
Deno.test("TC004: 无效邮箱返回 INVALID_EMAIL", async () => {
  const { data } = await callFunction("auth-register", {
    email: "not-an-email",
    password: "Test1234",
    username: `user_${Date.now()}`,
  });

  assertEquals(data.success, false);
  assertEquals(data.error.code, "INVALID_EMAIL");
});

// 异常: 用户名已存在
Deno.test("TC005: 重复用户名返回 USERNAME_TAKEN", async () => {
  const username = `taken_${Date.now()}`;
  await callFunction("auth-register", {
    email: `a_${Date.now()}@example.com`,
    password: "Test1234",
    username,
  });

  const { data } = await callFunction("auth-register", {
    email: `b_${Date.now()}@example.com`,
    password: "Test1234",
    username,
  });

  assertEquals(data.success, false);
  assertEquals(data.error.code, "USERNAME_TAKEN");
});

// 边界值: 空输入
Deno.test("TC006: 空 body 返回校验错误", async () => {
  const { data } = await callFunction("auth-register", {});
  assertEquals(data.success, false);
});
```

## 4. 测试命名规范

```
文件名: {模块}_{功能}_test.dart / {模块}_{功能}.test.ts
测试ID: TC{三位数字} — 全局唯一递增
组名:   group('{功能名}', () { ... })
用例名: test('{TC编号}: {中文场景描述}', () { ... })
```
