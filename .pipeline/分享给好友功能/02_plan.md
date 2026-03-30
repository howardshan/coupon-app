# 分享给好友功能 — 修改计划

## 背景与设计决策

### 消息类型设计
DB 的 `messages` 表已有 `coupon_payload` 字段（jsonb），类型支持 'text' | 'image' | 'coupon' | 'emoji' | 'system'。

**不新增 DB 字段/表**，而是复用 `coupon_payload` 字段存储分享数据，新增两个消息类型常量：
- `'deal_share'`：分享 Deal 卡片
- `'merchant_share'`：分享 Merchant 卡片

Payload 结构：
```json
// deal_share
{
  "deal_id": "uuid",
  "deal_title": "...",
  "deal_image_url": "...",
  "discount_price": 9.9,
  "original_price": 19.9,
  "merchant_id": "uuid",
  "merchant_name": "..."
}

// merchant_share
{
  "merchant_id": "uuid",
  "merchant_name": "...",
  "merchant_logo_url": "...",
  "merchant_address": "...",
  "merchant_cover_url": "..."
}
```

### 核心流程
1. 用户在 Deal 详情页 / Merchant 详情页点击分享按钮
2. 弹出选择好友底部弹窗（ShareToFriendSheet）
3. 用户选择一个或多个好友 -> 点击 Send
4. 对每个好友：获取或创建与其的 direct 会话，发送 deal_share / merchant_share 消息
5. Toast 提示 "Shared to X friend(s)"

### 关于"获取或创建 direct 会话"
ChatRepository 已有 `getOrCreateSupportChat`，但没有"获取或创建与某好友的 direct 会话"方法，需新增 `getOrCreateDirectChat`。

---

## 数据库改动

**不需要迁移**。
- `messages.coupon_payload` 已是 jsonb，可存 deal_share / merchant_share payload
- `messages.type` 已是 varchar，无枚举约束，直接写入 'deal_share' / 'merchant_share' 即可
- `previewText` 在 MessageModel 中通过 Dart 代码控制，无需改 DB

---

## 任务列表

---

### Task 1 — 修改 ChatRepository：新增 getOrCreateDirectChat + sendShareMessage
**文件**: `deal_joy/lib/features/chat/data/repositories/chat_repository.dart`
**操作**: modify
**描述**:
1. 在文件末尾新增 `getOrCreateDirectChat(String currentUserId, String friendUserId)` 方法：
   - 查询 conversation_members 表，找到两人共同参与的 direct 类型会话
   - 若存在则返回该会话 ID
   - 若不存在则创建新 direct 会话并添加两个成员，返回新会话 ID
2. 新增 `sendShareMessage(String conversationId, String senderId, Map<String, dynamic> payload)` 方法：
   - 内部调用 `_sendMessage`，type 字段来自 payload 中的 'type' key（'deal_share' 或 'merchant_share'），coupon_payload 存数据

**预计代码量**: ~60 行
**依赖**: 无

---

### Task 2 — 修改 MessageModel：支持新类型的 previewText
**文件**: `deal_joy/lib/features/chat/data/models/message_model.dart`
**操作**: modify
**描述**:
在 `previewText` getter 的 switch 中新增两个 case：
```dart
case 'deal_share':
  return '[Deal] ${couponPayload?['deal_title'] ?? 'Deal'}';
case 'merchant_share':
  return '[Store] ${couponPayload?['merchant_name'] ?? 'Store'}';
```
同时更新顶部注释（消息类型枚举说明加入 deal_share / merchant_share）

**预计代码量**: ~10 行
**依赖**: 无

---

### Task 3 — 新建 ShareToFriendSheet Widget（核心弹窗）
**文件**: `deal_joy/lib/features/chat/presentation/widgets/share_to_friend_sheet.dart`
**操作**: create
**描述**:
创建 `ShareToFriendSheet` StatefulWidget（用 ConsumerStatefulWidget，消费 friendsProvider + currentUserProvider）。

UI 结构：
- 顶部拖拽条 + 标题 "Share to Friends"
- 搜索框（本地过滤好友列表，不需要远程搜索）
- 好友列表（每行：头像 + 名字 + Checkbox，支持多选）
- 底部固定 Send 按钮（显示已选数量，未选时 disabled）

逻辑：
- 通过 ref.read(friendsProvider) 获取好友列表
- 维护本地 `Set<String> _selectedFriendIds`
- 点击 Send：
  - 对每个选中好友调用 `chatRepository.getOrCreateDirectChat(currentUserId, friendId)`
  - 再调用 `chatRepository.sendShareMessage(convId, currentUserId, payload)`
  - 完成后 Navigator.pop + ScaffoldMessenger 显示成功提示

**入参**:
```dart
const ShareToFriendSheet({
  required this.shareType, // 'deal_share' | 'merchant_share'
  required this.payload,   // Map<String, dynamic>
})
```

**预计代码量**: ~200 行
**依赖**: Task 1

---

### Task 4 — 修改 message_bubble.dart：新增 DealShareBubble + MerchantShareBubble
**文件**: `deal_joy/lib/features/chat/presentation/widgets/message_bubble.dart`
**操作**: modify
**描述**:
1. 在 `_buildBubbleContent` 的 switch 中新增两个 case：
```dart
case 'deal_share':
  return _DealShareBubble(
    payload: message.couponPayload ?? {},
    onTap: (dealId) => context.push('/deals/$dealId'),
  );
case 'merchant_share':
  return _MerchantShareBubble(
    payload: message.couponPayload ?? {},
    onTap: (merchantId) => context.push('/merchant/$merchantId'),
  );
```

2. 新增 `_DealShareBubble` 私有 Widget（底部 View Deal 按钮）：
   - 宽度 240，展示：封面图、deal 标题、商家名、价格（discountPrice）、原价（划线）
   - 底部操作按钮 "View Deal"
   - 样式与现有 `_CouponBubble` 一致（白色卡片、圆角12、阴影）

3. 新增 `_MerchantShareBubble` 私有 Widget：
   - 展示：封面图（merchant_cover_url）、商家名、地址
   - 底部操作按钮 "View Store"
   - 样式与 `_DealShareBubble` 一致

**预计代码量**: ~150 行
**依赖**: Task 2

---

### Task 5 — 修改 deal_detail_screen.dart：分享按钮触发弹窗
**文件**: `deal_joy/lib/features/deals/presentation/screens/deal_detail_screen.dart`
**操作**: modify
**描述**:
第 230 行的 `_AdaptiveCircleButton(icon: Icons.share_outlined, ...)` 的 onTap 当前调用 `Share.share(...)`。

修改为：**显示一个分享选项弹窗（AlertDialog 或 BottomSheet）**，给用户两个选项：
- "Share to Friends"（in-app 分享）→ 弹出 `ShareToFriendSheet`
- "Share via..."（系统分享）→ 调用原有的 `Share.share(...)`

`ShareToFriendSheet` 的 payload 构造：
```dart
{
  'type': 'deal_share',
  'deal_id': deal.id,
  'deal_title': deal.title,
  'deal_image_url': deal.images.isNotEmpty ? deal.images.first : null,
  'discount_price': deal.discountPrice,
  'original_price': deal.originalPrice,
  'merchant_id': deal.merchantId,
  'merchant_name': deal.merchantName,
}
```

注意：DealDetailScreen 是 ConsumerWidget，需要通过 `_DealDetailBody`（ConsumerStatefulWidget）持有的 widget context 来 showModalBottomSheet。`_DealDetailBody` 的构建方式需要确认后再决定是否需要改成 ConsumerStatefulWidget。

**预计代码量**: ~40 行（主要是新增一个 `_showShareOptions` 方法 + import）
**依赖**: Task 3

---

### Task 6 — 修改 merchant_detail_screen.dart：分享按钮触发弹窗
**文件**: `deal_joy/lib/features/merchant/presentation/screens/merchant_detail_screen.dart`
**操作**: modify
**描述**:
第 184 行 `_ActionBtn(Icons.share_outlined, onTap: () {})` 的 onTap 当前为空。

修改为调用 `_showShareOptions(context, merchant)` 方法，该方法显示分享选项：
- "Share to Friends" → 弹出 `ShareToFriendSheet`
- "Share via..." → `Share.share(merchant.name + ' on DealJoy!')`（需要 import share_plus）

`ShareToFriendSheet` 的 payload 构造：
```dart
{
  'type': 'merchant_share',
  'merchant_id': merchant.id,
  'merchant_name': merchant.name,
  'merchant_logo_url': merchant.logoUrl,
  'merchant_address': merchant.address,
  'merchant_cover_url': merchant.headerPhotos.isNotEmpty
      ? merchant.headerPhotos.first : null,
}
```

**预计代码量**: ~30 行
**依赖**: Task 3

---

## 文件一览

| 编号 | 文件路径 | 操作 |
|------|----------|------|
| T1 | `deal_joy/lib/features/chat/data/repositories/chat_repository.dart` | modify |
| T2 | `deal_joy/lib/features/chat/data/models/message_model.dart` | modify |
| T3 | `deal_joy/lib/features/chat/presentation/widgets/share_to_friend_sheet.dart` | create |
| T4 | `deal_joy/lib/features/chat/presentation/widgets/message_bubble.dart` | modify |
| T5 | `deal_joy/lib/features/deals/presentation/screens/deal_detail_screen.dart` | modify |
| T6 | `deal_joy/lib/features/merchant/presentation/screens/merchant_detail_screen.dart` | modify |

---

## 执行顺序

```
T1 (ChatRepository) ──┐
T2 (MessageModel)   ──┤──> T4 (message_bubble)
                       └──> T3 (ShareToFriendSheet) ──> T5 (deal_detail)
                                                    └──> T6 (merchant_detail)
```

T1、T2 无依赖，可并行。
T3 依赖 T1（需调用 getOrCreateDirectChat / sendShareMessage）。
T4 依赖 T2（新类型的 previewText 已就绪）。
T5、T6 依赖 T3（需要 ShareToFriendSheet 类已存在）。

---

## 注意事项

1. **禁止修改** Deal 详情页的 `_ImageGallery` widget 和 `SliverToBoxAdapter` 图片画廊布局结构（CLAUDE.md 保护区）
2. Deal 详情页分享按钮位于 `_DealDetailBody` 的 `build` 方法中，`_DealDetailBody` 是 `ConsumerStatefulWidget`，可以直接在其 build 方法中调用 `showModalBottomSheet`，无需改变 Widget 类型
3. `messages.type` 字段在 DB 层无枚举约束，直接写入 'deal_share' / 'merchant_share' 不会报错
4. `ShareToFriendSheet` 发送时需要处理 loading 状态（按钮 disable + 进度指示），防止用户重复点击
5. 如果好友列表为空，底部显示 "No friends yet. Add friends first." 占位提示
