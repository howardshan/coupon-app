# Gift 券赠送功能 — 实施计划

## Phase 1: Migration（后端数据层）

### 1.1 新建 migration 文件
- **文件**: `deal_joy/supabase/migrations/20260325000001_gift_feature.sql`
- **内容**:
  - CREATE TYPE gift_status AS ENUM ('pending','claimed','recalled','expired')
  - ALTER TYPE customer_item_status ADD VALUE 'gifted'
  - ALTER TABLE coupons ADD current_holder_user_id / is_gifted
  - CREATE TABLE coupon_gifts（含 RLS、索引、触发器）
  - INSERT email_type_settings C12/C13

## Phase 2: Edge Functions（后端逻辑层）

### 2.1 send-gift
- **文件**: `deal_joy/supabase/functions/send-gift/index.ts`
- **逻辑**: 验证→撤回旧gift→创建coupon_gift→更新order_item状态→发邮件

### 2.2 recall-gift
- **文件**: `deal_joy/supabase/functions/recall-gift/index.ts`
- **逻辑**: 验证→更新gift状态→恢复order_item为unused

### 2.3 claim-gift
- **文件**: `deal_joy/supabase/functions/claim-gift/index.ts`
- **逻辑**: 验证token→标记claimed→可选绑定用户→返回券信息

## Phase 3: 前端 Model 层

### 3.1 CouponGiftModel
- **文件**: `deal_joy/lib/features/orders/data/models/coupon_gift_model.dart`（新建）
- **内容**: GiftStatus enum + CouponGiftModel class

### 3.2 CustomerItemStatus 新增 gifted
- **文件**: `deal_joy/lib/features/orders/data/models/order_item_model.dart`
- **修改**: enum 加 gifted + displayLabel

### 3.3 OrderItemModel 新增 gift 属性
- **文件**: `deal_joy/lib/features/orders/data/models/order_item_model.dart`
- **修改**: activeGift 字段 + showGift/showRecallGift/showEditRecipient getter

## Phase 4: 前端 Repository + Provider 层

### 4.1 Gift Repository
- **文件**: `deal_joy/lib/features/orders/data/repositories/coupons_repository.dart`
- **修改**: 重写 giftCoupon → 调 send-gift EF，新增 recallGift / fetchActiveGift

### 4.2 Gift Provider
- **文件**: `deal_joy/lib/features/orders/domain/providers/coupons_provider.dart`
- **修改**: GiftNotifier 支持 sendGift(email/phone/message) / recallGift / editRecipient

## Phase 5: 前端 UI 层

### 5.1 Gift Bottom Sheet
- **文件**: `deal_joy/lib/features/orders/presentation/widgets/gift_bottom_sheet.dart`（新建）
- **内容**: 邮箱/电话输入 + 留言 + 发送按钮

### 5.2 order_detail_screen 集成
- **文件**: `deal_joy/lib/features/orders/presentation/screens/order_detail_screen.dart`
- **修改**: _CouponDetailRow 加 Gift / Recall Gift / Edit Recipient 按钮

### 5.3 voucher_detail_screen 集成
- **文件**: `deal_joy/lib/features/orders/presentation/screens/voucher_detail_screen.dart`
- **修改**: Gift 按钮改为调 Gift Bottom Sheet

### 5.4 Gifted 状态展示
- 修改 _CouponStatusRow 支持 gifted 分组
- 修改 _CouponDetailRow 显示 gift badge + 受赠方信息

## Phase 6: Email 模板

### 6.1 gift-sent 模板
- **文件**: `deal_joy/supabase/functions/_shared/email-templates/customer/gift-sent.ts`

### 6.2 gift-received 模板
- **文件**: `deal_joy/supabase/functions/_shared/email-templates/customer/gift-received.ts`
