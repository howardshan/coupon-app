# DealJoy UI/UX 参考规范（美团交互逻辑 + 北美简洁风格）

> 本文件是所有前端 Agent 的**最高优先级参考**。生成 UI 代码时必须遵循本文件的布局和交互规范。
> 设计原则：**美团的信息密度和交互流程 + 北美简洁视觉风格**

## 一、全局设计语言

### 配色方案（北美简洁版，非美团黄）
```
Primary:      #FF6B35 (Warm Orange - 品牌主色，按钮/价格/强调)
Secondary:    #1A1A2E (Dark Navy - 标题/正文)
Background:   #F8F9FA (Light Gray - 页面背景)
Card:         #FFFFFF (White - 卡片背景)
Success:      #10B981 (Green - 好评/成功)
Warning:      #F59E0B (Amber - 限时/折扣标签)
Error:        #EF4444 (Red - 错误/下架)
Text Primary: #1A1A2E
Text Secondary: #6B7280
Text Hint:    #9CA3AF
Divider:      #E5E7EB
```

### 字体
```
标题: SF Pro Display (iOS) / Roboto (Android), Bold
正文: SF Pro Text / Roboto, Regular
价格: SF Pro Display / Roboto, Bold (加大号)
```

### 圆角
```
卡片: 12px
按钮: 8px
图片: 12px (卡片内图片顶部圆角与卡片一致)
头像: 圆形
标签/Badge: 6px
```

---

## 二、底部导航栏 (Bottom Tab Bar)

DealJoy 只保留 4 个 Tab（美团有5个，去掉"视频"）：

```
┌──────────────────────────────────────────┐
│  🏠 Home    🔍 Search    🎫 Orders    👤 Me  │
└──────────────────────────────────────────┘
```

| Tab | 英文 | 图标 | 说明 |
|-----|------|------|------|
| 首页 | Home | house icon (filled when active) | Deal 推荐流 |
| 搜索 | Search | magnifying glass | 搜索 + 分类筛选 |
| 订单 | Orders | ticket/receipt icon | 我的团购券 + 订单 |
| 我的 | Me | person icon | 个人中心 |

- Active tab: Primary Orange 色图标 + 文字
- Inactive: #9CA3AF 灰色
- 无红点/角标（V1 简化）

---

## 三、首页 (Home Page)

### 整体布局（从上到下）

```
┌─────────────────────────────────────────┐
│ 📍 Dallas, TX ▾        [🔍 Search bar]  │  ← 定位 + 搜索
├─────────────────────────────────────────┤
│  🍔Food  💆Spa  🎮Fun  💇Beauty  ⋯More  │  ← 金刚区 (1行5个)
├─────────────────────────────────────────┤
│ 🔥 Flash Deals          See All >       │  ← 限时特惠横滑
│ ┌─────┐ ┌─────┐ ┌─────┐                │
│ │$4.99│ │$9.99│ │$15  │ ...             │
│ └─────┘ └─────┘ └─────┘                │
├─────────────────────────────────────────┤
│ Nearby Deals                            │  ← 附近 Deal 瀑布流
│ ┌────────┐ ┌────────┐                   │
│ │ [图片]  │ │ [图片]  │                   │
│ │ 商家名  │ │ 商家名  │                   │
│ │ ⭐4.8   │ │ ⭐4.6   │                   │
│ │ $39     │ │ $25     │                   │
│ └────────┘ └────────┘                   │
│ ┌────────┐ ┌────────┐                   │
│ │  ...   │ │  ...   │                   │
│ └────────┘ └────────┘                   │
└─────────────────────────────────────────┘
```

### 3.1 顶部区域
- **定位**: 左上角显示 "📍 Dallas, TX ▾"，点击弹出城市切换（V1只支持Dallas）
- **搜索栏**: 圆角胶囊形，浅灰背景，placeholder: "Search restaurants, spas..."
  - 点击跳转独立搜索页（不是原地展开）

### 3.2 金刚区 (Category Grid)
**只保留 5-8 个与 DealJoy 相关的品类，一行展示，可横滑：**

| 图标 | 英文 | 对应 |
|------|------|------|
| 🍔 | Food & Drink | 美食（美团的"美食"） |
| 💆 | Spa & Massage | 按摩足疗 + 洗浴汗蒸 |
| 💇 | Hair & Beauty | 美发 + 丽人 |
| 🎮 | Fun & Games | 休闲玩乐 |
| 🏋️ | Fitness | 健身 |
| 💅 | Nail & Lash | 美甲美睫 |
| 🧘 | Wellness | 养生保健 |
| ⋯ | More | 更多分类 |

- 图标风格: 简洁线性图标（Lucide/SF Symbols 风格），不用美团的卡通风
- 每个图标下方一行文字
- 不用美团的多行金刚区，只需一行，横滑可见更多

### 3.3 限时特惠 (Flash Deals)
- 横向滚动卡片，模仿美团 "老友回归1分购" 区域
- 每张卡片：方形图片 + 大号价格 + "Grab" 按钮
- 卡片尺寸: 120x160
- 价格用 Primary Orange，大号字体 (24px)
- 标题截断一行

### 3.4 Deal 推荐流 (Deal Feed) — 核心区域
**双列瀑布流布局，模仿美团团购 Feed：**

每张 Deal 卡片结构（从上到下）：

```
┌─────────────────────┐
│                     │
│    [商家/菜品图片]    │  ← 图片占比约 60%，圆角顶部
│                     │
│  [DEAL] Richardson  │  ← 橙色 Deal 标签 + 地区名
├─────────────────────┤
│ Sakura Sushi Bar    │  ← 商家名 (1行，超长截断)
│ ⭐ 4.8 · 200+ sold  │  ← 评分 + 销量
│ $39  $65  40% off   │  ← 现价(大/橙) 原价(小/删除线) 折扣
└─────────────────────┘
```

**Deal 卡片数据字段：**
```dart
class DealCard {
  String imageUrl;          // 主图（高质量食物/环境图）
  String dealTag;           // "DEAL" (固定) 或 "HOT DEAL"
  String neighborhood;      // 地区: "Richardson", "Plano", "Downtown"
  String merchantName;      // 商家名
  double rating;            // 评分 (0-5)
  int reviewCount;          // 评价数
  double currentPrice;      // 现价 (美元)
  double originalPrice;     // 原价
  int soldCount;            // 已售数量
  String? badge;            // 可选角标: "Best Seller", "New"
}
```

**视觉细节（对标美团但简化）：**
- 图片比例: 不固定（瀑布流自适应，类似美团）
- "DEAL" 标签: 左下角覆盖在图片上，橙色半透明背景 + 白色文字
- 地区名: 紧跟 DEAL 标签右边，白色文字
- 价格: `$39` 用 Primary Orange, Bold, 20px；`$65` 用灰色删除线, 14px
- 销量: "200+ sold" (美团的 "半年售100+")
- 卡片间距: 8px
- 卡片圆角: 12px
- 卡片阴影: 轻微 (elevation 1-2)

---

## 四、Deal 详情页 (Deal Detail Page)

### 布局（从上到下）

```
┌─────────────────────────────────────────┐
│ [← Back]              [♡] [Share]       │  ← 导航栏
├─────────────────────────────────────────┤
│                                         │
│          [轮播图 / 商家照片]              │  ← 图片轮播，高度 250px
│            · · ● · ·                    │
├─────────────────────────────────────────┤
│ Sakura Sushi Bar                        │  ← 商家名 (Bold, 22px)
│ ⭐ 4.8 (326 reviews) · Japanese         │  ← 评分 + 类别
│ 📍 0.8 mi · Richardson                  │  ← 距离 + 地区
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ 🎫 Omakase Dinner for 2            │ │  ← Deal 套餐名
│ │                                     │ │
│ │ · 12-piece chef's selection sushi   │ │  ← 套餐内容
│ │ · 2 miso soup                       │ │
│ │ · 2 house salad                     │ │
│ │ · 2 drinks                          │ │
│ │                                     │ │
│ │ Valid Mon-Thu                        │ │  ← 使用条件
│ │ Dine-in only · 2 per table max      │ │
│ │                                     │ │
│ │ $39          $65     40% off        │ │  ← 价格区
│ └─────────────────────────────────────┘ │
├─────────────────────────────────────────┤
│ 📍 Location                             │
│ 123 Main St, Richardson, TX 75080       │
│ [Map Preview]                           │  ← 嵌入小地图
├─────────────────────────────────────────┤
│ ⭐ Reviews (326)                See All  │
│ ┌───────────────────────────────────┐   │
│ │ John D. ⭐⭐⭐⭐⭐  2 days ago      │   │
│ │ "Amazing omakase experience!"     │   │
│ └───────────────────────────────────┘   │
├─────────────────────────────────────────┤
│                                         │
│  ┌─────────────────────────────────┐    │
│  │   Buy Now · $39                 │    │  ← 底部固定购买按钮
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

**关键交互：**
- 图片支持左右滑动
- "Buy Now" 按钮固定在底部，常驻可见
- 点击 Buy Now → 跳转下单确认页
- 收藏按钮 (♡) 在右上角
- 评价区默认展示 2 条，点 See All 进入评价列表

---

## 五、下单确认页 (Checkout Page)

```
┌─────────────────────────────────────────┐
│ [← Back]     Confirm Order              │
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ [缩略图] Sakura Sushi Bar           │ │
│ │          Omakase Dinner for 2       │ │
│ │          Qty: 1                     │ │
│ └─────────────────────────────────────┘ │
├─────────────────────────────────────────┤
│ Deal Price              $39.00          │
│ Service Fee             $0.00           │
│ ──────────────────────────────          │
│ Total                   $39.00          │
├─────────────────────────────────────────┤
│ Payment Method                          │
│ 💳 Visa •••• 4242               [Edit]  │
├─────────────────────────────────────────┤
│ ☑ I agree to the Terms & Refund Policy  │
│   "Buy anytime, refund anytime"         │  ← DealJoy 核心卖点
├─────────────────────────────────────────┤
│                                         │
│  ┌─────────────────────────────────┐    │
│  │   Pay $39.00                    │    │  ← 支付按钮
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

**关键要素：**
- 突出 "Buy anytime, refund anytime" — 这是 DealJoy 差异化
- 数量选择器 (Qty: 1 [+][-])
- 支付方式: Stripe (Apple Pay / Google Pay / Card)
- V1 不需要优惠券叠加
- 支付按钮使用 Primary Orange，大号

---

## 六、券码页 (Voucher Page)

购买成功后展示团购券：

```
┌─────────────────────────────────────────┐
│ [← Back]      My Voucher                │
├─────────────────────────────────────────┤
│                                         │
│  ┌─────────────────────────────────┐    │
│  │     ✅ Purchase Successful       │    │
│  │                                  │    │
│  │  ┌──────────────────────────┐   │    │
│  │  │                          │   │    │
│  │  │      [QR CODE]           │   │    │  ← 核销二维码
│  │  │                          │   │    │
│  │  └──────────────────────────┘   │    │
│  │                                  │    │
│  │  Voucher Code: DJY-8A3F-X9K2   │    │  ← 文字码（备用）
│  │                                  │    │
│  │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │    │  ← 撕裂线效果
│  │                                  │    │
│  │  Sakura Sushi Bar               │    │
│  │  Omakase Dinner for 2           │    │
│  │  Valid until: Mar 31, 2026      │    │
│  │  Status: ● Unused               │    │  ← 绿色圆点
│  └─────────────────────────────────┘    │
│                                         │
│  📍 View Location                       │
│  📞 Call Merchant                       │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │   🔄 Refund This Voucher        │    │  ← 退款按钮（显眼）
│  └─────────────────────────────────┘    │
│  Instant refund · No questions asked    │  ← 再次强调核心卖点
└─────────────────────────────────────────┘
```

**券码状态颜色：**
- Unused (未使用): 🟢 Green
- Used (已使用): 🔵 Blue
- Refunded (已退款): ⚪ Gray
- Expired (已过期): 🔴 Red

---

## 七、订单列表 (Orders Page)

```
┌─────────────────────────────────────────┐
│ My Orders                               │
├─────────────────────────────────────────┤
│ [All] [Unused] [Used] [Refunded]        │  ← Tab 筛选
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ [缩略图] Sakura Sushi Bar           │ │
│ │          Omakase Dinner for 2       │ │
│ │          Mar 1, 2026                │ │
│ │                                     │ │
│ │          $39.00     ● Unused   [>]  │ │
│ └─────────────────────────────────────┘ │
│ ┌─────────────────────────────────────┐ │
│ │ [缩略图] Zen Spa & Wellness         │ │
│ │          60min Deep Tissue Massage  │ │
│ │          Feb 28, 2026               │ │
│ │                                     │ │
│ │          $49.00     ● Used     [>]  │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

---

## 八、搜索页 (Search Page)

```
┌─────────────────────────────────────────┐
│ [←] [🔍 Search deals, restaurants...  ] │
├─────────────────────────────────────────┤
│ Recent Searches                 Clear   │
│ sushi   massage   korean bbq           │
├─────────────────────────────────────────┤
│ Popular Near You                        │
│ 🔥 Deep tissue massage                 │
│ 🔥 All-you-can-eat sushi               │
│ 🔥 Hair coloring & cut                 │
├─────────────────────────────────────────┤
│ (搜索后显示结果列表，单列卡片)            │
│ ┌─────────────────────────────────────┐ │
│ │ [图] Sakura Sushi · ⭐4.8 · 0.8mi  │ │
│ │      Omakase for 2 · $39 ($65)      │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

搜索结果用**单列列表**（不是瀑布流），因为搜索结果需要更高信息密度。

---

## 九、个人中心 (Me Page)

```
┌─────────────────────────────────────────┐
│ ┌─────┐                                │
│ │ 头像 │  Howard S.                     │
│ └─────┘  howard@example.com             │
│           Edit Profile >                │
├─────────────────────────────────────────┤
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐           │
│ │ 2  │ │ 5  │ │ 1  │ │ 0  │           │
│ │未用 │ │已用 │ │退款 │ │过期 │           │
│ └────┘ └────┘ └────┘ └────┘           │
├─────────────────────────────────────────┤
│ 📋 My Orders                        >  │
│ ❤️ Saved Deals                       >  │
│ 📍 My Addresses                      >  │
│ 💳 Payment Methods                   >  │
│ ⚙️ Settings                          >  │
│ ❓ Help & Support                    >  │
├─────────────────────────────────────────┤
│ 🚪 Sign Out                            │
└─────────────────────────────────────────┘
```

---

## 十、DealJoy vs 美团 差异对照

| 元素 | 美团 | DealJoy |
|------|------|---------|
| 品类 | 15+ (外卖/酒店/打车/...) | 5-8 (Food/Spa/Beauty/Fun/Fitness) |
| 金刚区 | 3行15个图标 | 1行5-8个，可横滑 |
| Feed布局 | 双列瀑布流 | **双列瀑布流**（保持一致） |
| 卡片标签 | "团购"/"神券"/"惠" | "DEAL" / "HOT DEAL" / "NEW" |
| 价格 | ¥398 红色 | $39 橙色 |
| 销量 | "半年售100+" | "200+ sold" |
| 折扣 | "8.3折" / "已减204元" | "40% off" / "Save $26" |
| 配色 | 黄色为主 (#FFD100) | 暖橙为主 (#FF6B35) |
| 退款 | 隐藏在客服流程里 | **醒目退款按钮 + 核心卖点标语** |
| 直播/视频 | 有 | V1 无 |
| 外卖功能 | 有 | V1 无（只做到店团购） |

---

## 十一、Flutter 组件命名约定

```
lib/features/
├── home/
│   ├── pages/home_page.dart              # 首页
│   ├── widgets/
│   │   ├── location_bar.dart             # 定位栏
│   │   ├── search_bar_button.dart        # 搜索入口（点击跳转）
│   │   ├── category_grid.dart            # 金刚区
│   │   ├── flash_deals_section.dart      # 限时特惠横滑
│   │   └── deal_feed.dart                # Deal 瀑布流
│   └── providers/home_provider.dart
├── deal_detail/
│   ├── pages/deal_detail_page.dart       # Deal 详情
│   ├── widgets/
│   │   ├── deal_image_carousel.dart      # 图片轮播
│   │   ├── deal_info_section.dart        # 商家信息
│   │   ├── deal_package_card.dart        # 套餐卡片
│   │   ├── merchant_location.dart        # 地图位置
│   │   └── review_preview.dart           # 评价预览
│   └── providers/deal_detail_provider.dart
├── checkout/
│   ├── pages/checkout_page.dart          # 下单确认
│   └── widgets/
│       ├── order_summary_card.dart        # 订单摘要
│       ├── payment_method_selector.dart   # 支付方式
│       └── buy_button.dart               # 支付按钮
├── voucher/
│   ├── pages/voucher_detail_page.dart    # 券码页
│   └── widgets/
│       ├── qr_code_display.dart          # 二维码
│       ├── voucher_status_badge.dart     # 状态标签
│       └── refund_button.dart            # 退款按钮
├── orders/
│   ├── pages/orders_page.dart            # 订单列表
│   └── widgets/
│       ├── order_tab_bar.dart            # 状态Tab
│       └── order_card.dart               # 订单卡片
├── search/
│   ├── pages/search_page.dart            # 搜索页
│   └── widgets/
│       ├── search_history.dart           # 搜索历史
│       ├── popular_searches.dart         # 热门搜索
│       └── search_result_card.dart       # 搜索结果卡片
└── profile/
    ├── pages/profile_page.dart           # 个人中心
    └── widgets/
        ├── profile_header.dart           # 头像+信息
        ├── voucher_stats_row.dart        # 券码统计
        └── settings_menu.dart            # 设置列表
```

---

## 十二、关键交互细节

### 下拉刷新
- 首页 Feed 支持下拉刷新 (RefreshIndicator)
- 刷新图标使用 Primary Orange

### 上拉加载
- Feed 触底自动加载更多 (infinite scroll)
- 加载中显示底部 Loading spinner
- 无更多内容显示 "You've seen all deals nearby"

### 卡片点击
- 点击 Deal 卡片 → push 到 Deal 详情页
- 卡片点击有轻微缩放动画 (scale 0.98)

### 空状态
- 无搜索结果: 插画 + "No deals found. Try a different search."
- 无订单: 插画 + "No orders yet. Browse deals to get started!"
- 无网络: 插画 + "No internet connection" + Retry 按钮

### Toast / SnackBar
- 成功: 绿色背景 + ✓ 图标
- 错误: 红色背景 + ✕ 图标
- 信息: 深色背景
- 位置: 底部，3秒自动消失
