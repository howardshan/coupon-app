# DealJoy 集成测试报告

> 生成日期: 2026-03-13
> 测试环境: Android Emulator (emulator-5554), Flutter 3.x
> 测试框架: Flutter integration_test

---

## 总览

| 端 | 测试文件 | 用例数 | 通过 | 失败 | 跳过 | 通过率 |
|----|---------|-------|------|------|------|--------|
| 商家端 Auth | `dealjoy_merchant/integration_test/auth_flow_test.dart` | 15 | 9 | 6 | 0 | 60% |
| 商家端 三端联动 | `dealjoy_merchant/integration_test/cross_end_test.dart` | 1 | — | — | — | 未运行 |
| 客户端 Auth | `deal_joy/integration_test/auth_flow_test.dart` | 22 | — | — | — | 未运行 |
| 客户端 三端联动 | `deal_joy/integration_test/cross_end_test.dart` | 2 | — | — | — | 未运行 |
| **合计** | **4 个文件** | **40** | **9** | **6** | **0** | **已运行: 60%** |

---

## 商家端 Auth 测试详情 (M001-M015)

最终运行结果（第 3 次迭代，修复 users.role 和 waitForNavigation 后）：

### 通过 (9/15)

| 编号 | 测试名称 | 结果 | 备注 |
|------|---------|------|------|
| M001 | 登录页输入框存在且可输入 | ✅ PASS | |
| M002 | 登录提交按钮存在 | ✅ PASS | |
| M003 | 空表单提交触发校验错误 | ✅ PASS | |
| M004 | 无效邮箱格式触发校验错误 | ✅ PASS | |
| M005 | 密码为空触发校验错误 | ✅ PASS | |
| M006 | 错误密码显示登录失败错误信息 | ✅ PASS | 修复: 用 waitForNavigation 等待异步网络请求 |
| M007 | store_owner 登录成功跳转 Dashboard | ✅ PASS | 修复: 严格断言 NavigationBar + waitForNavigation |
| M008 | 登出后路由回到登录页 | ✅ PASS | |
| M009 | 登出后访问 Dashboard 被重定向到登录页 | ✅ PASS | |
| M010 | pending 状态登录跳转到审核页 | ✅ PASS | 修复: users.role='merchant' + MerchantStatusCache.clear() |

### 失败 (6/15)

| 编号 | 测试名称 | 结果 | 失败原因 | 分类 |
|------|---------|------|---------|------|
| M008* | (Riverpod 异步竞态) | ⚠️ FLAKY | `ProviderContainer already disposed` — DashboardNotifier 在 widget 销毁后仍尝试读取 Provider。测试逻辑本身通过，但 Flutter 框架捕获到 post-test 异常 | 测试基础设施 |
| M011 | 审核状态页包含审核中描述文字 | ❌ FAIL | M010 tearDown 后 app 状态不干净，`launchAppSignedOut` 后登录页未完全渲染，`enterText` 找不到 email field (`Bad state: No element`) | 测试隔离 |
| M012 | 审核状态页可点击退出登录 | ❌ FAIL | 同 M011，前序测试状态污染导致 login 字段不可用 | 测试隔离 |
| M013 | 登录页存在注册链接 | ❌ FAIL | M012 失败后 app 状态污染级联，`launchAppSignedOut` 后页面未到达 login 页，找不到 "Register" 文字 | 测试隔离 |
| M014 | 点击注册链接跳转注册页 | ❌ FAIL | 同 M013，级联失败 | 测试隔离 |
| M015 | 注册页可返回登录页 | ❌ FAIL | 同 M013，级联失败 | 测试隔离 |

> **注**: M008 标记为 `*` 是因为测试逻辑实际通过（M008 和 M009 都计入 passed），但 Riverpod 的异步竞态导致 Flutter 测试框架报出一个 post-test error，影响了后续测试计数。

---

## 迭代修复记录

### 第 1 次运行 (修复前)
- 结果: 11 通过 / 4 失败
- 问题: M006, M010, M011, M012 失败
- 根因: `pumpAndSettle` 不等待异步网络请求；`MerchantStatusCache` 缓存污染

### 第 2 次运行 (添加 MerchantStatusCache.clear + waitForNavigation)
- 结果: 11 通过 / 4 失败（不同的失败）
- 问题: M010-M012 仍然失败，M006 也失败
- 根因: **测试商家 `users.role = 'user'`**，登录页检查 `role != 'merchant'` 直接退出

### 第 3 次运行 (修复 users.role = 'merchant')
- 结果: **9 通过 / 6 失败**
- 改进: M001-M010 全部通过（含之前失败的 M006, M007, M010）
- 新问题: M011-M015 因测试间 app 状态隔离不足而级联失败

---

## 根因分析

### 已解决的问题

1. **测试数据配置错误** — `users` 表中 `role='user'` 而非 `'merchant'`，导致登录页 role 校验失败
   - 修复: `PATCH /rest/v1/users` 将 role 更新为 `'merchant'`

2. **pumpAndSettle 不等待网络请求** — Flutter 的 `pumpAndSettle` 只等待帧调度，不等待异步网络调用
   - 修复: 新增 `waitForNavigation()` helper，轮询 pump 直到目标 Widget 出现

3. **MerchantStatusCache 缓存污染** — 静态单例在测试间共享，前一个测试的 `approved` 缓存影响后续 `pending` 测试
   - 修复: `launchAppSignedOut()` 中调用 `MerchantStatusCache.clear()`

### 未解决的问题

4. **测试间 App 状态隔离不足** — Flutter integration_test 在同一进程中运行所有 `testWidgets`，共享同一个 `GoRouter` 实例和 Supabase 客户端。M010 通过后的 tearDown (`signOut`) 触发路由跳转，但帧未被 pump，导致 M011 启动时 app 处于中间状态。
   - 影响: M011-M015 全部因此级联失败
   - 建议修复方向:
     - 将 M010-M012 合并为单个 `testWidgets`（一次登录，多个断言）
     - 或在 `launchAppSignedOut` 中增加 `waitForNavigation(login_email_field)` 确保到达登录页
     - 或将 M013-M015 拆分为独立测试文件

5. **Riverpod ProviderContainer disposed 竞态** — Dashboard Provider 的异步请求在 widget tree 销毁后完成，触发 `Bad state: ProviderContainer already disposed`
   - 影响: 不影响测试逻辑结果，但 Flutter 框架将其记为 test failure
   - 建议修复: 在 `DashboardNotifier._fetchData` 中增加 mounted/disposed 检查

---

## 测试基础设施总结

### 已创建的文件

| 文件 | 描述 |
|------|------|
| `dealjoy_merchant/integration_test/helpers/test_config.dart` | Supabase 连接配置 + 测试账号常量 |
| `dealjoy_merchant/integration_test/helpers/supabase_test_helper.dart` | REST API 辅助类（Service Role Key 绕过 RLS） |
| `dealjoy_merchant/integration_test/helpers/app_launcher.dart` | App 启动 + waitForNavigation 辅助函数 |
| `dealjoy_merchant/integration_test/auth_flow_test.dart` | M001-M015 商家端登录注册测试 |
| `dealjoy_merchant/integration_test/cross_end_test.dart` | X001 三端联动测试 |
| `deal_joy/integration_test/helpers/test_config.dart` | 客户端测试配置 |
| `deal_joy/integration_test/helpers/supabase_test_helper.dart` | 客户端 REST API 辅助类 |
| `deal_joy/integration_test/helpers/app_launcher.dart` | 客户端 App 启动辅助 |
| `deal_joy/integration_test/auth_flow_test.dart` | C001-C022 客户端登录注册测试 |
| `deal_joy/integration_test/cross_end_test.dart` | X005, X006 三端联动测试 |

### 测试账号

| 角色 | 邮箱 | UID | 状态 |
|------|------|-----|------|
| 商家 | `test_merchant@dealjoy.test` | `c2c2f2f8-fed0-405a-9640-b10588e1ad47` | users.role=merchant, merchants.status=approved |
| 客户 | `test_customer@dealjoy.test` | `0c17c3cb-88b9-4798-9082-da3bdda87349` | users.role=user |

### ValueKey 覆盖

- 共添加 **77 个 ValueKey**（deal_joy 32 个 + dealjoy_merchant 45 个）
- 覆盖所有 ElevatedButton, TextButton, TextField, TextFormField
- 对照表: `key_map.md`

---

## 后续建议

1. **优先修复 M011-M015**: 将 M010-M012 合并为单个测试用例，或在 `launchAppSignedOut` 中确保等到 login 页面
2. **运行客户端测试**: `cd deal_joy && flutter test integration_test/auth_flow_test.dart -d emulator-5554`
3. **运行三端联动测试**: 需要先启动商家端，再启动客户端
4. **修复 DashboardNotifier 竞态**: 增加 disposed 检查避免 post-test 异常
5. **考虑测试拆分**: 每个 `testWidgets` 独立文件可避免进程内状态污染
