# 5.下单与支付 — 开发计划

## 优先级 1: 后端补全

### 1.1 创建 promo_codes 表 (新 migration)
- **文件**: `deal_joy/supabase/migrations/20260301100000_add_promo_codes.sql`
- **内容**: promo_codes 表 + RLS 策略 + 种子数据
- **字段**: id, code, discount_type (percentage/fixed), discount_value, min_order_amount, max_discount, max_uses, current_uses, deal_id (nullable), expires_at, is_active

### 1.2 创建 Stripe Webhook Edge Function
- **文件**: `deal_joy/supabase/functions/stripe-webhook/index.ts`
- **内容**: 处理 payment_intent.succeeded/failed, charge.refunded, charge.dispute.created
- **安全**: 验证 Stripe Signature, 幂等性处理

## 优先级 2: 前端修复 & 补全

### 2.1 CheckoutRepository — 添加优惠码验证方法
- **文件**: `deal_joy/lib/features/checkout/data/repositories/checkout_repository.dart`
- **修改**: 添加 `validatePromoCode(code, dealId, subtotal)` 方法
- **逻辑**: 查询 promo_codes 表验证有效性，返回折扣金额

### 2.2 CheckoutProvider — 添加优惠码状态管理
- **文件**: `deal_joy/lib/features/checkout/domain/providers/checkout_provider.dart`
- **修改**: 添加 PromoCodeState provider

### 2.3 CheckoutScreen — 完善优惠券功能 & 限购
- **文件**: `deal_joy/lib/features/checkout/presentation/screens/checkout_screen.dart`
- **修改**:
  1. Apply 按钮调用 validatePromoCode
  2. 移除硬编码 10% 折扣，改用真实优惠码折扣
  3. 展示限购数量 (从 deal.stockLimit 获取)
  4. 添加优惠券验证状态 UI (loading/success/error)

### 2.4 OrderSuccessScreen — 展示订单详情
- **文件**: `deal_joy/lib/features/checkout/presentation/screens/order_success_screen.dart`
- **修改**: 添加订单号、Deal信息、支付金额展示

## 优先级 3: 测试

### 3.1 修复现有测试
- **文件**: `deal_joy/test/widget_test.dart` — 已修复

### 3.2 新增测试
- **文件**: `deal_joy/test/features/checkout/` — OrderModel, CheckoutRepository 单元测试
