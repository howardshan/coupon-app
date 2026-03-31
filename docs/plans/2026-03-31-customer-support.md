# Customer Support 模块实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在用户端 Profile 页添加 Customer Support 入口，提供 Email / Call Back Later / Chat（预设问答树）三种客服联系方式。

**Architecture:** 新建 `features/support/` 模块，遵循项目的 Feature-First Clean Architecture。Chat 为纯前端问答树（不存数据库），Call Back 需要新建 `support_callbacks` 数据库表。Profile 页插入 Customer Support section card 作为入口。

**Tech Stack:** Flutter + Riverpod + Supabase（仅 Call Back 用到数据库）+ url_launcher（Email）+ go_router

---

## Task 1: 数据库迁移 — 创建 support_callbacks 表

**Files:**
- Create: `deal_joy/supabase/migrations/20260331000001_support_callbacks.sql`

**Step 1: 编写 migration SQL**

```sql
-- 客服回拨请求表
CREATE TABLE IF NOT EXISTS support_callbacks (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  phone TEXT NOT NULL,
  preferred_time_slot TEXT NOT NULL CHECK (preferred_time_slot IN ('morning', 'afternoon', 'evening')),
  description TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE support_callbacks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "support_callbacks_select_own"
  ON support_callbacks FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "support_callbacks_insert_own"
  ON support_callbacks FOR INSERT
  WITH CHECK (auth.uid() = user_id);
```

**Step 2: 部署到远程数据库**

```bash
/opt/homebrew/opt/libpq/bin/psql "postgresql://postgres.kqyolvmgrdekybjrwizx:dealjoy20260228!@aws-0-us-west-2.pooler.supabase.com:5432/postgres" -f deal_joy/supabase/migrations/20260331000001_support_callbacks.sql
```

Expected: `CREATE TABLE`, `ALTER TABLE`, `CREATE POLICY` × 2 成功

**Step 3: Commit**

```bash
git add deal_joy/supabase/migrations/20260331000001_support_callbacks.sql
git commit -m "feat(support): add support_callbacks table with RLS"
```

---

## Task 2: FAQ 数据定义 — 预设问答树

**Files:**
- Create: `deal_joy/lib/features/support/presentation/widgets/faq_data.dart`

**Step 1: 定义问答数据结构和内容**

创建 `FaqItem` 类和预设问答列表。每个 FaqItem 包含：
- `id`: 唯一标识
- `label`: 按钮显示文字
- `keywords`: 关键词列表（用于输入匹配）
- `response`: 回复内容
- `action`: 可选的后续动作类型（`showOrders`, `showRefundableOrders`, `goBack` 等）

预设问题：
1. **Check Order Status** — keywords: order, status, 订单 → action: `showOrders`
2. **Request a Refund** — keywords: refund, return, 退款 → action: `showRefundableOrders`
3. **How to Use Coupons** — keywords: coupon, use, redeem, 用券 → 纯文字回答
4. **Refund Policy** — keywords: policy, rule, 政策 → 纯文字回答
5. **Contact Merchant** — keywords: merchant, store, contact, 商家 → 纯文字回答（引导去商家详情页看联系方式）
6. **Other Questions** — 兜底 → 引导 Email / Call Back

**Step 2: Commit**

```bash
git add deal_joy/lib/features/support/presentation/widgets/faq_data.dart
git commit -m "feat(support): add FAQ data definitions for chat tree"
```

---

## Task 3: Data 层 — CallbackRequestModel + SupportRepository

**Files:**
- Create: `deal_joy/lib/features/support/data/models/callback_request_model.dart`
- Create: `deal_joy/lib/features/support/data/repositories/support_repository.dart`

**Step 1: 创建 CallbackRequestModel**

字段：id, userId, phone, preferredTimeSlot, description, status, createdAt
包含 `fromJson` (null-safe) 和 `toInsertJson` 方法。

**Step 2: 创建 SupportRepository**

方法：
- `submitCallbackRequest({required String phone, required String timeSlot, String? description})` → 插入 `support_callbacks` 表
- 使用项目现有模式：`SupabaseClient` 注入，`AppException` 处理异常

**Step 3: Commit**

```bash
git add deal_joy/lib/features/support/data/
git commit -m "feat(support): add CallbackRequestModel and SupportRepository"
```

---

## Task 4: Domain 层 — Riverpod Providers

**Files:**
- Create: `deal_joy/lib/features/support/domain/providers/support_provider.dart`

**Step 1: 创建 providers**

```dart
// Repository provider
final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return SupportRepository(ref.watch(supabaseClientProvider));
});

// 提交回拨请求的状态管理（用 AsyncNotifier 模式）
// submitCallbackProvider — 处理提交状态
```

**Step 2: Commit**

```bash
git add deal_joy/lib/features/support/domain/
git commit -m "feat(support): add support providers"
```

---

## Task 5: Call Back 表单弹窗 — CallbackSheet

**Files:**
- Create: `deal_joy/lib/features/support/presentation/widgets/callback_sheet.dart`

**Step 1: 创建 CallbackSheet widget**

底部弹窗（`showModalBottomSheet`），包含：
- 标题 "Request a Call Back"
- 电话号码输入框（`TextFormField`，预填用户已有手机号）
- 时间段选择（`ChoiceChip` 或 `SegmentedButton`）：Morning 9am-12pm / Afternoon 12-5pm / Evening 5-9pm
- 问题描述（可选，`TextFormField` multiline）
- Submit 按钮（调用 `supportRepositoryProvider` 提交）
- 成功后 `Navigator.pop` + `ScaffoldMessenger` 提示

**Step 2: Commit**

```bash
git add deal_joy/lib/features/support/presentation/widgets/callback_sheet.dart
git commit -m "feat(support): add CallbackSheet bottom sheet widget"
```

---

## Task 6: Customer Support 入口页

**Files:**
- Create: `deal_joy/lib/features/support/presentation/screens/customer_support_screen.dart`

**Step 1: 创建 CustomerSupportScreen**

页面内容：
- AppBar: "Customer Support"
- 三张卡片（纵向排列），每张包含图标 + 标题 + 描述 + 箭头：
  1. **Email Us** — icon: `Icons.email_outlined` — 点击 `url_launcher` 跳转 `mailto:support@dealjoy.com?subject=DealJoy Support Request`
  2. **Call Back Later** — icon: `Icons.phone_callback_outlined` — 点击弹出 `CallbackSheet`
  3. **Chat with Us** — icon: `Icons.chat_outlined` — 点击 `context.push('/support/chat')`

遵循项目现有的 `AppColors` 配色方案。

**Step 2: Commit**

```bash
git add deal_joy/lib/features/support/presentation/screens/customer_support_screen.dart
git commit -m "feat(support): add CustomerSupportScreen with 3 contact options"
```

---

## Task 7: 问答树聊天界面 — SupportChatScreen

**Files:**
- Create: `deal_joy/lib/features/support/presentation/screens/support_chat_screen.dart`

**Step 1: 创建 SupportChatScreen**

这是核心聊天界面，纯前端逻辑：

**状态管理**：用 `StatefulWidget` 内部维护消息列表 `List<_ChatMessage>`，每条消息包含 `text`, `isUser`, `buttons`（可选的快捷按钮列表）, `orderItems`（可选的订单列表）

**UI 结构**：
- AppBar: "DealJoy Support"
- 消息列表（`ListView`）：系统消息左对齐灰色气泡，用户消息右对齐主题色气泡
- 系统消息可附带快捷按钮（`Wrap` 中的 `ActionChip`）
- 系统消息可附带订单列表（可点击的订单卡片）
- 底部输入栏：`TextField` + 发送按钮

**交互逻辑**：
1. 初始化时显示欢迎消息 + 6 个快捷按钮
2. 用户点击按钮或输入文字 → 添加用户消息气泡
3. 根据 `FaqItem.id` 或关键词匹配 → 添加系统回复气泡
4. **Check Order Status**: 调用 `userOrdersProvider` 获取订单列表，以卡片形式展示最近 5 个订单
5. **Request a Refund**: 调用 `userOrdersProvider`，过滤 `customer_status == 'unused'` 的订单项，展示可退款列表，点击跳转 `/refund/:orderId`
6. 其他问题：显示预设文字回答 + "Was this helpful?" + 返回主菜单按钮
7. 无法匹配：显示兜底消息 "I couldn't find an answer... You can email us or request a call back." + 返回主菜单按钮

**Step 2: Commit**

```bash
git add deal_joy/lib/features/support/presentation/screens/support_chat_screen.dart
git commit -m "feat(support): add SupportChatScreen with FAQ tree and order queries"
```

---

## Task 8: 路由注册

**Files:**
- Modify: `deal_joy/lib/core/router/app_router.dart`

**Step 1: 添加 import 和路由**

在 `app_router.dart` 顶部添加 import：
```dart
import '../../features/support/presentation/screens/customer_support_screen.dart';
import '../../features/support/presentation/screens/support_chat_screen.dart';
```

在路由列表中（`/chat/notifications` 路由之后、`/chat/:conversationId` 路由之前的区域）添加：
```dart
// Customer Support
GoRoute(
  path: '/support',
  builder: (_, _) => const CustomerSupportScreen(),
),
GoRoute(
  path: '/support/chat',
  builder: (_, _) => const SupportChatScreen(),
),
```

**Step 2: Commit**

```bash
git add deal_joy/lib/core/router/app_router.dart
git commit -m "feat(support): register /support and /support/chat routes"
```

---

## Task 9: Profile 页面添加 Customer Support 入口

**Files:**
- Modify: `deal_joy/lib/features/profile/presentation/screens/profile_screen.dart`

**Step 1: 添加 Customer Support section card**

在 `_ProfileBody.build()` 方法中，第 361 行 `],` 和第 363 行 `const SizedBox(height: 12),` 之间（即 Merchant/BecomeMerchant 块之后、Sign Out 按钮之前），插入：

```dart
const SizedBox(height: 12),

// ── Customer Support ─────────────────────────────────
_SectionCard(
  child: ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.support_agent_outlined,
        color: AppColors.textSecondary,
        size: 20,
      ),
    ),
    title: const Text(
      'Customer Support',
      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    ),
    subtitle: const Text(
      'Email, call back, or chat with us',
      style: TextStyle(fontSize: 12, color: AppColors.textHint),
    ),
    trailing: const Icon(
      Icons.chevron_right,
      color: AppColors.textHint,
    ),
    onTap: () => context.push('/support'),
  ),
),
```

需要在文件顶部添加 `import 'package:go_router/go_router.dart';`（如果 `_ProfileBody` 中没有 context.push，但实际上已经有了，只需确保在该 widget 的 build 中能访问 context — 需要从 `StatelessWidget` 改为接收 BuildContext 或直接使用 `Builder`）。

实际上 `_ProfileBody` 是 `StatelessWidget`，其 `build(BuildContext context)` 可以直接使用 `context.push`，无需额外 import（go_router 已在文件顶部通过 `app_router.dart` 间接导入，但实际需要检查 profile_screen.dart 是否有 `import 'package:go_router/go_router.dart'`）。

**Step 2: Commit**

```bash
git add deal_joy/lib/features/profile/presentation/screens/profile_screen.dart
git commit -m "feat(support): add Customer Support entry in Profile page"
```

---

## Task 10: AppConstants 添加客服邮箱

**Files:**
- Modify: `deal_joy/lib/core/constants/app_constants.dart`

**Step 1: 添加客服联系邮箱常量**

在 `AppConstants` 类中添加：
```dart
/// 客服联系邮箱
static const String supportEmail = 'support@dealjoy.com';
```

**Step 2: Commit**

```bash
git add deal_joy/lib/core/constants/app_constants.dart
git commit -m "feat(support): add supportEmail constant"
```

---

## Task 11: 端到端验证

**Step 1: 运行 Flutter 分析**

```bash
cd "/Users/howardshansmac/github/coupon app/coupon-app/deal_joy" && ~/flutter/bin/flutter analyze lib/features/support/
```

Expected: No issues found

**Step 2: 运行完整项目编译检查**

```bash
cd "/Users/howardshansmac/github/coupon app/coupon-app/deal_joy" && ~/flutter/bin/flutter build apk --debug 2>&1 | tail -5
```

Expected: BUILD SUCCESSFUL

---

## 依赖关系

```
Task 1 (DB migration)     ─── 独立，可先行
Task 2 (FAQ data)         ─── 独立
Task 10 (constants)       ─── 独立
Task 3 (model + repo)     ─── 依赖 Task 1
Task 4 (providers)        ─── 依赖 Task 3
Task 5 (callback sheet)   ─── 依赖 Task 4
Task 6 (support screen)   ─── 依赖 Task 5, 10
Task 7 (chat screen)      ─── 依赖 Task 2, 4
Task 8 (routes)           ─── 依赖 Task 6, 7
Task 9 (profile entry)    ─── 依赖 Task 8
Task 11 (验证)            ─── 依赖全部
```

## 并行执行建议

- **并行组 1**: Task 1 + Task 2 + Task 10（三者互不依赖）
- **并行组 2**: Task 3 + Task 4（依赖 Task 1）
- **并行组 3**: Task 5 + Task 7（分别依赖 Task 4 和 Task 2+4）
- **顺序**: Task 6 → Task 8 → Task 9 → Task 11
