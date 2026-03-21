# Git Change Description

## 2026-03-20 — Order System V3 重构（多 deal 购物车 + 双状态 + Store Credit）

### 数据库 (Supabase Migrations)

#### 新建表和 Enum
- **20260320000001_order_system_v3.sql**: 创建 `customer_item_status` / `merchant_item_status` enum；新建 `cart_items`（DB 持久化购物车，每张券一行）、`order_items`（核心，双状态 customer/merchant）、`store_credits`（余额）、`store_credit_transactions`（流水）四张表；修改 `orders` 表（新增 items_amount, service_fee_total, paid_at）；修改 `coupons` 表（新增 order_item_id, coupon_code）；修改 `refund_requests` 表（新增 order_item_id, refund_method）
- **20260320000002_order_item_triggers.sql**: `auto_create_coupon_per_item()` 触发器（order_items INSERT → 自动创建 coupon + 16 位券码）；`fn_snapshot_stores_for_item()` 门店快照触发器；`sync_deal_total_sold_on_item_insert()` total_sold 同步触发器；`add_store_credit()` RPC 函数
- **20260320000003_migrate_existing_orders.sql**: 数据迁移 — 12 条旧 orders 映射到 order_items，coupons.order_item_id 和 coupon_code 回填
- **20260320120000_rpc_get_expired_order_items.sql**: 过期 item 查询 RPC（供 auto-refund-expired 使用）

### 后端 (Edge Functions) — 全部 8 个重写/新建

#### create-payment-intent（重写）
- 入参改为 `items: [{dealId, unitPrice, promoCode?}]`（多 deal 购物车）
- 服务端价格防篡改校验
- `capture_method: 'automatic'`（直接 charge，取代预授权）
- 计算 service_fee = $0.99 × distinct deal count

#### create-order-v3（新建）
- Stripe 支付成功后创建 order + order_items
- 触发器自动创建 coupons（含 16 位券码）
- 分摊 service fee：$0.99 / 同 Deal 张数
- 清理 cart_items

#### create-refund（重写）
- 入参改为 `{orderItemId, refundMethod}`（per-item 退款）
- store_credit 路径：退 unit_price + service_fee，调 `add_store_credit` RPC，立即到账
- original_payment 路径：退 unit_price（不含 service fee），调 Stripe refunds.create

#### merchant-scan（更新）
- 移除 Stripe capture 逻辑（不再预授权）
- 核销时更新 order_items 双状态（customer_status='used', merchant_status='unpaid'）
- 门店快照查询改为 JOIN order_items

#### stripe-webhook（简化）
- 移除 `amount_capturable_updated` 和 `payment_intent.canceled` 处理
- `charge.refunded` 改为 per-item 退款（通过 metadata.order_item_id）

#### auto-refund-expired（更新）
- 改为基于 order_items + coupons.expires_at 查找过期项
- 过期统一退 store credit（含 service fee）
- 移除 Stripe cancel PI 逻辑

#### merchant-orders（更新）
- handleList 改为 order_items 维度查询
- handleDetail 返回 order + items 列表 + customer 信息
- handleExport CSV 改为 order_items 维度

#### user-order-detail（更新）
- 返回 order + items 列表，每个 item 含 coupon 信息
- timeline 增加 item 级别事件
- 向后兼容旧订单

### 用户端 (deal_joy)

#### Cart 模块重写（DB 持久化）
- **cart_item_model.dart**: 新增 DB 字段（id, userId, unitPrice 等），移除 quantity
- **cart_repository.dart**: 新建，直接读写 cart_items 表（fetchCartItems, addToCart, removeFromCart, clearCart）
- **cart_provider.dart**: 改为 AsyncNotifier 模式，新增 cartServiceFeeProvider（$0.99 × distinct deal 数）
- **cart_screen.dart**: 重写，同 deal 多张券按分组卡片展示，底部结算栏拆分 subtotal/service fee/total

#### Checkout 模块重写
- **checkout_repository.dart**: 新增 `checkoutCart()`（V3 多 deal 结账），保留 `checkoutSingleDeal()`（兼容 Buy Now）
- **checkout_screen.dart**: 支持购物车模式和单 deal 模式，显示 service fee + 退款政策提示
- **app_router.dart**: 新增 `/checkout-cart` 路由

#### Orders 模块重构
- **order_item_model.dart**: 新建，`CustomerItemStatus` / `MerchantItemStatus` 枚举 + `OrderItemModel`（含按钮可见性 getter + 券码格式化）
- **order_model.dart**: 新增 items 列表、itemsAmount、serviceFeeTotal、itemsByDeal getter，保留旧字段向后兼容
- **coupon_model.dart**: 新增 orderItemId、couponCode 字段
- **order_detail_model.dart**: 新增 items 列表
- **orders_repository.dart**: JOIN order_items 查询，新增 requestItemRefund()
- **coupons_repository.dart**: 通过 order_items 获取 applicable_store_ids，requestRefund 增加 refundMethod 参数
- **coupons_provider.dart**: RefundNotifier 新增 requestItemRefund() 方法
- **orders_screen.dart**: 订单卡片展示多 items 摘要
- **order_detail_screen.dart**: 按 deal 分组展示 items + QR Code Bottom Sheet + Cancel Bottom Sheet（store credit / 原路退选择）

#### Store Credit UI（新建）
- **store_credit_model.dart**: StoreCredit + StoreCreditTransaction 模型
- **store_credit_repository.dart**: 查询 store_credits / store_credit_transactions 表
- **store_credit_provider.dart**: FutureProvider 余额 + 流水
- **store_credit_screen.dart**: 品牌色渐变余额卡片 + 交易记录列表
- **app_router.dart**: 新增 `/profile/store-credit` 路由

### 商家端 (dealjoy_merchant)
- **merchant_order.dart**: 新增 orderItemId、customerStatus、merchantStatus、serviceFee、couponCode 字段，新建 MerchantOrderItem 类
- **orders_service.dart**: 适配 order_items 维度响应
- **orders_provider.dart**: 适配新 model

---

## 2026-03-17

### Deal 有效期三种模式 + Stripe 预授权支持

#### 数据库
- **20260317000001_validity_type_three_modes.sql**: `deals.validity_type` CHECK 约束扩展为三值 (`fixed_date` / `short_after_purchase` / `long_after_purchase`)；`orders` 表新增 `capture_method` 列 (`automatic` | `manual`)
- **20260317000002_rpc_add_validity_fields.sql**: 重建 `search_deals_nearby` 和 `search_deals_by_city` RPC 函数，返回值新增 `validity_type` / `validity_days` 字段

#### 后端 (Supabase Edge Functions)
- **create-payment-intent**: 服务端查 `deals.validity_type`，`short_after_purchase` 时 Stripe PI 使用 `capture_method: 'manual'`（预授权）；返回 `captureMethod` 字段
- **merchant-scan**: 核销前检查预授权 deal 距过期不足 1 小时则拒绝；核销成功后若 `capture_method=manual` 则调 Stripe capture；capture 失败时回滚 coupon 状态
- **create-refund**: 查 `orders.capture_method`，`manual` 时调 `paymentIntents.cancel()` 取消预授权，`automatic` 时走正常退款
- **auto-refund-expired**: 清理旧错误代码；预授权订单提前 1 小时触发，查 PI 状态后 cancel 或仅更新 DB；立即扣款订单原逻辑不变
- **merchant-deals**: `validity_type` 白名单改为三值；模板发布分支条件从 `days_after_purchase` 改为 `short/long_after_purchase`

#### 商家端 (dealjoy_merchant)
- **merchant_deal.dart**: `ValidityType` 枚举 `daysAfterPurchase` → `shortAfterPurchase` + `longAfterPurchase`，`fromString` 向后兼容旧值
- **deal_create_page.dart**: 有效期 Chip 改为三个（Fixed Date / Short-term / Long-term）；天数验证 Short 1-7 / Long 8-365；切换时自动清空超范围输入；不同类型显示不同说明文字
- **deal_edit_page.dart**: 同上
- **deal_template_create_page.dart**: `_validityTypeOptions` 改为三值，天数验证同步
- **deals_service_test.dart**: 更新 `ValidityType` 枚举测试用例

#### 用户端 (deal_joy)
- **deal_model.dart**: 新增 `validityType` 和 `validityDays` 字段，`fromJson` / `fromSearchJson` 均支持
- **deal_detail_screen.dart**: Purchase Notes 的 Validity 行根据 `validityType` 动态展示；Short-term 额外显示 "Card hold only" 支付说明行
- **checkout_repository.dart**: 解析 `captureMethod` 返回值，写入 `orders.capture_method`

---

## 2026-03-13

### 商家端 (dealjoy_merchant)

#### 修复 declined 状态下仍显示倒计时的问题
- **store_deal_confirm_page.dart**: 倒计时横幅增加 `_confirmStatus == 'pending_store_confirmation'` 判断，declined/active 状态不再显示 48 小时倒计时

#### 修复更新营业时间 404 Route not found
- **store_service.dart**: `updateBusinessHours` 的 function name 从 `merchant-store` 改为 `merchant-store/hours`，匹配 Edge Function 的 `PUT /merchant-store/hours` 路由

#### Deal 编辑逻辑改为克隆模式
- 无需前端修改，后端 Edge Function 已处理

### 后端 (Supabase)

#### Deal 编辑改为克隆模式（merchant-deals PATCH）
- **merchant-deals/index.ts**: `handleUpdateDeal` 重写 — 仅修改库存时原地更新；其他修改克隆新 deal（新 ID + pending 状态），旧 deal 自动下架为 inactive。克隆时同步复制 deal_images 和 deal_applicable_stores

### 用户端 (deal_joy)

#### Deal 详情页增加 reg price - deal promotion 说明
- **deal_detail_screen.dart**: 价格区域从 Row 改为 Column，在原价划线下方新增一行 "$X reg price - $Y deal promotion" 说明文字

### Admin 管理端 (admin)

#### Activate 按钮仅 pending 状态显示
- **deal-review-actions.tsx**: Activate 按钮条件从 `!isActive` 改为 `dealStatus === 'pending'`，商家自行下架的 inactive deal 不再显示激活按钮

### 后端 (Supabase)

#### 同步 migration 文件与线上 RPC 函数
- **20260312000003_deal_activation_trigger.sql**: `accept_deal_store` WHERE 改为 `IN ('pending_store_confirmation', 'declined')`；`decline_deal_store` WHERE 改为 `IN ('pending_store_confirmation', 'active')`

---

## 2026-03-13（续）— 多功能批量更新

### 用户端 (deal_joy)

#### 购买时门店快照
- **20260313000001_order_store_snapshot.sql**: orders 表新增 `applicable_store_ids uuid[]`，BEFORE INSERT 触发器自动快照 deal_applicable_stores，回填历史数据
- **merchant-scan/index.ts**: 核销验证改用快照门店列表，NULL 时降级查当前活跃门店
- **coupon_model.dart**: 新增 `applicableStoreIds` 字段，从 orders join 解析
- **coupons_repository.dart**: `_couponSelect` 新增 `orders(applicable_store_ids)` join
- **coupons_provider.dart**: 新增 `applicableStoresProvider` 查询门店名称地址
- **coupon_screen.dart**: 多门店券展示门店列表（名称+地址）

#### Deal 详情页 UI 增强
- **deal_detail_screen.dart**: 多图轮播 PageView + 相册按钮 + 全屏查看器；套餐横向选择器（同店 deal 按 sort_order 排序，优先 shortName）
- **deal_model.dart**: 新增 `shortName`、`sortOrder` 字段

#### Deal 详情页底部栏新增 Add to Cart 按钮
- **deal_detail_screen.dart**: 底部栏改为 Store 图标 | Cart 图标（带 badge）| Add to Cart（#FF9500 橙色）| Buy Now
- **cart_item_model.dart**: 新建购物车单项模型
- **cart_provider.dart**: Riverpod Notifier 管理购物车状态（addDeal / updateQuantity / remove / clear）
- **cart_screen.dart**: 从占位页升级为完整购物车，支持数量调整、移除、清空、总价展示

#### Store 详情页 deal 排序
- **store_detail_repository.dart**: `fetchActiveDeals` 新增 `.order('sort_order')` 排序

### 商家端 (dealjoy_merchant)

#### Deal 列表拖拽排序
- **deals_list_page.dart**: "All" tab 改用 ReorderableListView，拖拽手柄
- **deals_service.dart**: 新增 `batchReorder()` 批量更新排序
- **deals_provider.dart**: DealsNotifier 新增 `reorderDeals()`

#### Deal 创建/编辑新增 short_name + 图片扩展
- **deal_create_page.dart**: Step 0 新增 short_name 输入框（≤10 字符），图片上传从 5 张扩展到 9 张
- **deal_edit_page.dart**: 新增 short_name 字段，图片上限 9 张
- **merchant_deal.dart**: 新增 `shortName` 字段

### 后端 (Supabase)

#### merchant-deals Edge Function 扩展
- **merchant-deals/index.ts**: CREATE 支持 short_name；PATCH 白名单新增 short_name/sort_order；新增 sort_order_only 原地更新标记；新增 `PATCH /reorder` 批量排序端点

#### DB Migration
- deals 表新增 `short_name text CHECK(char_length <= 10)` 列

### key_map.md
- 新增 4 个 ValueKey：deal_short_name_field, deal_list_drag_handle, deal_image_gallery, deal_variant_selector

---

## 2026-03-13（续）— dishes 改名 + 照片库增强 + 价格自适应

### 用户端 (deal_joy)

#### 价格公式行自适应修复
- **deal_detail_screen.dart**: 右侧 `= Reg Price - Deal Promotion` 区域用 `Expanded` + `Flexible` 包裹，解决窄屏溢出问题

#### Restaurant Info / Applicable Stores 增加商家封面图
- **deal_detail_screen.dart**: Restaurant Info 标题下新增 `homepageCoverUrl` 横幅图；Applicable Stores 主门店及多店卡片顶部增加封面图
- **_MultiStoreList** 查询新增 `homepage_cover_url` join

#### Deal 详情页产品行显示价格
- **deal_model.dart → _parseProducts**: 已支持 `name::qty::subtotal` 格式解析
- **deal_detail_screen.dart**: 每行产品显示 `×qty $subtotal`

#### 全局 dishes → products 改名
- **deal_model.dart**: 字段 `dishes` → `products`，方法 `_parseDishes` → `_parseProducts`（DB 列名 `json['dishes']` 保留不变）
- **deal_detail_screen.dart**: `_DishesSection` → `_ProductsSection`，所有 `deal.dishes` → `deal.products`
- **deal_card_horizontal.dart / deal_card_v2.dart**: `dishesPreview` → `productsPreview`
- **menu_tab.dart / menu_section.dart**: "Signature Dishes" → "Signature Products"
- **photo_gallery_screen.dart**: 筛选标签 "Dishes" → "Products"，来源标签 "Dish" → "Product"

#### 照片库 Products 筛选器改用 menu_items 数据
- **photo_gallery_screen.dart**: 完全重写。新增 `_DisplayPhoto` 统一模型；Products 筛选从 `menu_items` 表查有图片的产品（按 merchant_id）；图片底部渐变叠加显示产品名称和价格；全屏浏览模式也显示产品名和价格

#### DealModel 新增 optionGroups 支持
- **deal_model.dart**: 新增 `DealOptionGroup`、`DealOptionItem` 类；DealModel 新增 `optionGroups` 字段 + `_parseOptionGroups` 解析
- **deals_repository.dart**: `fetchDealById` select 新增 `deal_option_groups(*, deal_option_items(*))` join

### 商家端 (dealjoy_merchant)

#### MerchantDeal 新增 dishes 字段（结构化格式）
- **merchant_deal.dart**: 新增 `dishes` 字段（`List<String>`），`toJson` 传 `dishes`，`fromJson` 解析 `json['dishes']`
- **deal_create_page.dart**: 新增 `_dishesData` getter，生成 `"name::qty::subtotal"` 格式数组传给后端

### 数据库

#### 更新现有 deals 的 dishes 为带价格格式
- SQL 脚本：将 5 条现有 deal 的 dishes 从纯名称数组匹配 menu_items 价格，更新为 `"name::1::price"` 格式

---

## 2026-03-13（续）— Deal 选项组（"几选几"功能）

### 数据库
- **20260313000002_deal_option_groups.sql**: 新增 `deal_option_groups`（组名/select_min/select_max/sort_order）和 `deal_option_items`（项名/价格/sort_order）两张表，外键 cascade 删除；`orders` 表新增 `selected_options jsonb` 列存储下单时选项快照；完整 RLS 策略（所有人可读，商家通过 deal→merchant_staff 链路可增删改）

### 后端 (Supabase)
- **merchant-deals/index.ts**: LIST 查询 join `deal_option_groups(*, deal_option_items(*))`；CREATE 时调 `insertOptionGroups()` 批量插入选项组和选项项；PATCH 克隆模式下若传入 option_groups 则插入新数据，否则 `cloneOptionGroups()` 复制旧 deal 的选项组

### 商家端 (dealjoy_merchant)
- **merchant_deal.dart**: 新增 `DealOptionGroup`、`DealOptionItem` 模型（含 fromJson/toJson/copyWith）；`MerchantDeal` 新增 `optionGroups` 字段；`displayLabel` 改为固定数量格式（全选时只显示组名，否则 "Select X from Y"）
- **deal_create_page.dart**: Step 1 新增 "Option Groups (Optional)" 区域，支持添加/编辑/删除选项组和选项项（组名、固定选择数量 Select Count、项名+单价）；selectMin = selectMax = count
- **deal_edit_page.dart**: 同上，options section 位于 Usage Rules 和 Images 之间；同样改为单个 Select Count 输入框

### 用户端 (deal_joy)
- **deal_model.dart**: 新增用户侧 `DealOptionGroup`、`DealOptionItem` 类 + `_parseOptionGroups` 解析
- **deals_provider.dart**: 新增 `dealOptionSelectionsProvider`（StateProvider.family），在详情页的选项选择器和底部栏之间共享选择状态
- **deal_detail_screen.dart**: 新增 `_OptionGroupsSelector` 组件（ConsumerStatefulWidget），支持单选（max=1 替换）/多选模式、完成状态标签；`_BottomBar` 的 Buy Now / Add to Cart 按钮增加选项完成校验（未完成弹 SnackBar 提示）；`_ProductsSection` 产品行匹配选项组时显示 "(Select X from Y)" 格式，全选时只显示名称
- **checkout_repository.dart**: `checkout()` 和 `_createOrder()` 新增 `selectedOptions` 参数，写入 `orders.selected_options` JSONB
- **checkout_screen.dart**: 支付时从 `dealOptionSelectionsProvider` 读取选择，构建 `[{group_id, group_name, items: [{item_id, item_name, price}]}]` 快照传给 checkout

### key_map.md
- 新增 7 个 ValueKey：deal_option_group_name_field, deal_option_select_min_field, deal_option_select_max_field, deal_option_item_name_field, deal_option_item_price_field, deal_option_add_group_btn, deal_option_add_item_btn

---

## 2026-03-13（续）— UI 美化 + 美团风格吸顶 Header

### 用户端 (deal_joy)

#### Deal 详情页 — 美团风格吸顶 Header + 三点菜单
- **deal_detail_screen.dart**:
  - 将 `Stack` + 浮动圆形按钮改为 `SliverAppBar(pinned: true)`：展开时显示图片画廊 + 浮动圆形按钮（返回/收藏/分享/三点），收起时（图片滚出视野）显示白色顶栏（返回箭头/搜索放大镜/收藏心/分享/三点菜单）
  - `_DealDetailBody` 从 `ConsumerWidget` 改为 `ConsumerStatefulWidget`，通过 `NotificationListener<ScrollNotification>` 追踪滚动状态控制 title 显示/隐藏
  - 新增 `_CollapsedHeaderBar`：收起后的顶栏组件（搜索图标跳转 `/search`）
  - 新增 `_CollapsedSaveButton`：收起状态下的扁平收藏按钮
  - 新增 `_showMoreMenu()`：文件级函数，打开三点菜单底部弹出框
  - 新增 `_MoreMenuSheet`（ConsumerWidget）：美团风格底部菜单，包含快捷操作图标行（Home/Nearby/My Orders/Report/Report Error）+ 浏览记录横滚卡片（`historyDealsProvider`）+ 我的收藏横滚卡片（`savedDealsListProvider`），View All 跳转 `/history` 和 `/collection`
  - 新增 `_MenuDealSection`、`_MenuDealCard`、`_SavedDealsSection` 辅助组件

#### 底部导航栏恢复默认样式
- **main_scaffold.dart**: 移除黄色主题 `Theme` wrapper，恢复 Material 3 默认样式；高度设为 60

#### 首页搜索栏紧凑化
- **home_screen.dart**: `PreferredSize` 高度 52→44，TextField 添加 `isDense: true`、`contentPadding`、字号 14

#### 商家标签改灰色 + 缩小
- **store_info_card.dart**: tag chips 背景改 `AppColors.surfaceVariant`，文字改 `AppColors.textSecondary`，字号 12→10，高度 28→22，圆角 14→4
- **store_feature_tags.dart**: `_TagChip` 背景保持 `surfaceVariant`，图标/文字改 `AppColors.textHint`，字号 12→10，图标 14→12，圆角 20→4

#### Store 详情页 TabBar 自适应
- **merchant_detail_screen.dart**: `_StickyTabBar` 从 `ListView.separated`（可滚动）改为 `Row` + `Expanded`，每个 tab 等分宽度居中对齐，确保 Deals/Menu/About 始终全部可见

#### Near Me 功能完善 — GPS 附近商家搜索
- **location_utils.dart**（新建）: 从 `deals_provider.dart` 提取 `haversineDistanceMiles()` 为共享工具函数
- **deals_provider.dart**: 删除内联 Haversine 函数，改为引用 `location_utils.dart`
- **home_screen.dart**: `distanceMiles()` 调用改为 `haversineDistanceMiles()`
- **merchant_model.dart**: 新增 `distanceMiles` 字段 + `copyWith()` 方法
- **merchant_repository.dart**: 新增 `fetchMerchantsNearby({lat, lng, category, radiusMiles})` — 拉取 approved 商家，Dart 端 Haversine 计算距离，过滤 20mi 内，按距离排序
- **merchant_provider.dart**: `merchantListProvider` 新增 `isNearMeProvider` 监听，Near Me 时调 `fetchMerchantsNearby`，城市模式保持不变
- **home_screen.dart** `_MerchantGridCard`: 评分行新增距离显示（"X.X mi"），仅 `distanceMiles != null` 时出现
- **store_info_card.dart**: 新增 `distanceMiles` 参数，评分行加入距离显示（"X.X mi · ..."）
- **merchant_detail_screen.dart**: 通过 `userLocationProvider` + `haversineDistanceMiles` 计算距离传入 `StoreInfoCard`

---

## 2026-03-15 — Deal 详情页 Restaurant Info 布局 + Detail Images 功能

### 用户端 (deal_joy)

#### Restaurant Info 图片与名字同行
- **deal_detail_screen.dart** `_RestaurantInfo`: 移除全宽封面图，头像改为圆形 56x56（优先 homepageCoverUrl，降级 logoUrl），与商家名称同行显示

#### Deal 详情页新增 Photos 展示区
- **deal_detail_screen.dart**: 新增 `_DetailPhotosSection` widget，在 Restaurant Info 下方展示竖版图片（宽度铺满、3:4 比例、圆角 10px），使用 CachedNetworkImage
- **deal_model.dart**: DealModel 新增 `detailImages` 字段（`List<String>`），fromJson/fromSearchJson 均解析 `detail_images`

#### coupon_screen.dart 编译修复
- **coupon_screen.dart**: `coupon.orderNumber` 替换为 `coupon.orderId.substring(0, 8).toUpperCase()`（CouponModel 无 orderNumber 字段）

### 商家端 (dealjoy_merchant)

#### Deal 创建/编辑新增竖版图片上传
- **merchant_deal.dart**: MerchantDeal 新增 `detailImages` 字段（`List<String>`），fromJson/toJson/copyWith 均支持
- **deals_service.dart**: 新增 `uploadDetailImage()` 方法，上传到 Storage 路径 `{merchantId}/detail_images/{dealId}/{timestamp}.jpg`
- **deal_create_page.dart**: Step 5 新增 "Detail Photos (Portrait)" 区域，最多 5 张竖版图片，创建 deal 后上传并 PATCH 回写 detail_images
- **deal_edit_page.dart**: Images 编辑区新增竖版图片管理，支持已有图片展示/删除 + 新图片上传

### 后端 (Supabase)

#### DB Migration
- **20260315000001_deal_detail_images.sql**: deals 表新增 `detail_images text[] NOT NULL DEFAULT '{}'`

#### Edge Function
- **merchant-deals/index.ts**: POST 创建时写入 detail_images；PATCH updatableFields 和 cloneFields 白名单新增 detail_images
