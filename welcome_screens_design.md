# 欢迎页面系统设计文档

> **核心决策汇总**
> - ✅ Splash Screen：每次打开 App 显示，倒计时 + 可提前关闭，多图轮播，每图独立链接
> - ✅ Onboarding：首次安装后显示，之后不再显示
> - ✅ 所有图片、链接、文案均可在 Admin 后台实时修改，无需用户更新 App
> - ✅ 屏幕尺寸自适应（Flutter LayoutBuilder + BoxFit.cover）

---

## Phase 0 · 侦察

```bash
# 1. 确认现有路由入口（app_router.dart）
cat lib/router/app_router.dart | head -100

# 2. 确认现有 Splash / 启动页
find . -name "*splash*" -o -name "*onboard*" | grep ".dart" | sort

# 3. 确认 Supabase Storage bucket
grep -rn "storage\|bucket" supabase/ --include="*.ts" -l

# 4. 确认现有 Admin 配置表
grep -rn "config\|settings\|banner" supabase/migrations/*.sql

# 5. 确认 shared_preferences / local storage 方案
grep -rn "shared_preferences\|hive\|storage" lib/ --include="*.dart" -l \
  | grep -v ".g.dart"
```

**侦察检查表：**
```
[ ] 现有 Splash 页路径：________（有则修改，无则新建）
[ ] 现有 Onboarding 页路径：________
[ ] Storage bucket 名称（存图片用）：________
[ ] shared_preferences 版本：________
[ ] Admin 后台框架：Next.js / 其他：________
[ ] 现有 splash_configs / banner_configs 表：是 / 否
```

---

## 一、三个模块总览

```
App 启动
    ↓
Splash Screen（每次启动）
  - 全屏广告轮播（1~5 张）
  - 右上角倒计时 + Skip 按钮
  - 点击图片跳转对应链接
    ↓
是否首次安装？
  ├─ 是 → Onboarding（滑动引导，3~5 页）
  └─ 否 → 直接进 App 主页
    ↓
主页 Homepage Banner（常驻轮播）
  - 顶部 Banner 区，多图自动轮播
  - 每图独立链接
```

---

## 二、数据模型

### 2.1 Splash 配置表

```sql
CREATE TABLE splash_configs (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_active    boolean NOT NULL DEFAULT false,
  duration_seconds int NOT NULL DEFAULT 5,   -- 倒计时秒数（3~10）
  slides       jsonb NOT NULL DEFAULT '[]',  -- 轮播图列表（见下方结构）
  created_by   uuid REFERENCES users(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- 每次只有一条 is_active = true
CREATE UNIQUE INDEX idx_splash_configs_active
  ON splash_configs(is_active) WHERE is_active = true;

-- slides 字段结构（jsonb 数组）：
-- [
--   {
--     "id": "uuid",
--     "image_url": "https://...",
--     "link_type": "deal" | "merchant" | "external" | "none",
--     "link_value": "deal_id / merchant_id / https://...",
--     "sort_order": 0
--   },
--   ...
-- ]
```

### 2.2 Onboarding 配置表

```sql
CREATE TABLE onboarding_configs (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_active    boolean NOT NULL DEFAULT false,
  slides       jsonb NOT NULL DEFAULT '[]',  -- 引导页列表（见下方结构）
  created_by   uuid REFERENCES users(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_onboarding_configs_active
  ON onboarding_configs(is_active) WHERE is_active = true;

-- slides 字段结构：
-- [
--   {
--     "id": "uuid",
--     "image_url": "https://...",
--     "title": "Discover Local Deals",
--     "subtitle": "Save up to 60% at restaurants near you",
--     "cta_label": "Next" | null,   -- 最后一页为 "Get Started"
--     "sort_order": 0
--   },
--   ...
-- ]
```

### 2.3 Homepage Banner 配置表

```sql
CREATE TABLE banner_configs (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_active    boolean NOT NULL DEFAULT false,
  auto_play_seconds int NOT NULL DEFAULT 3,  -- 自动轮播间隔
  slides       jsonb NOT NULL DEFAULT '[]',
  created_by   uuid REFERENCES users(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_banner_configs_active
  ON banner_configs(is_active) WHERE is_active = true;

-- slides 结构同 splash_configs.slides
```

### 2.4 RLS

```sql
-- 所有配置公开可读（App 启动时匿名读取）
ALTER TABLE splash_configs      ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboarding_configs  ENABLE ROW LEVEL SECURITY;
ALTER TABLE banner_configs      ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public_read_splash"     ON splash_configs
  FOR SELECT USING (true);
CREATE POLICY "public_read_onboarding" ON onboarding_configs
  FOR SELECT USING (true);
CREATE POLICY "public_read_banner"     ON banner_configs
  FOR SELECT USING (true);
```

---

## 三、Splash Screen 设计

### 3.1 UI 结构

```
┌──────────────────────────────────┐  ← 全屏（SafeArea 内）
│                                  │
│                                  │
│      [商家广告图 / 活动图]         │  ← 全屏 BoxFit.cover
│                                  │
│                                  │
│                          [5 ▶]  │  ← 右上角：倒计时圆形进度 + Skip
│                                  │
│                                  │
│                                  │
│                                  │
│         ● ○ ○ ○               │  ← 底部 indicator（多图时显示）
└──────────────────────────────────┘
```

**倒计时按钮细节：**
```
圆形进度条（CircularProgressIndicator）
中间显示剩余秒数，点击立即关闭
倒计时结束自动关闭
```

### 3.2 多图自动轮播行为

```
图片1 停留 duration_seconds 秒
    ↓ 自动切换（PageView）
图片2 停留 duration_seconds 秒
    ↓ ...
最后一张停留完 → 自动进入下一步（Onboarding 或主页）

用户可在任意时刻点击 Skip 跳过所有
用户可左右滑动手动切换图片（滑动会重置倒计时）
```

### 3.3 链接跳转逻辑

```dart
void handleSplashTap(SplashSlide slide) {
  switch (slide.linkType) {
    case 'deal':
      // 关闭 Splash，进主页后 deep link 到 Deal 详情
      context.go('/deals/${slide.linkValue}');
    case 'merchant':
      context.go('/merchants/${slide.linkValue}');
    case 'external':
      launchUrl(Uri.parse(slide.linkValue));
    case 'none':
      // 点击无操作，只有 Skip 能关闭
      break;
  }
}
```

### 3.4 Flutter 实现要点

```dart
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  late AnimationController _countdownController;
  final PageController _pageController = PageController();
  int _currentPage = 0;
  SplashConfig? _config;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    // 优先读本地缓存，后台刷新
    final cached = await _localCache.getSplashConfig();
    if (cached != null) setState(() => _config = cached);

    // 后台拉最新配置
    final fresh = await _repo.fetchActiveSplashConfig();
    if (fresh != null) {
      await _localCache.setSplashConfig(fresh);
      if (mounted) setState(() => _config = fresh);
    }

    _startCountdown();
  }

  void _startCountdown() {
    final duration = Duration(seconds: _config?.durationSeconds ?? 5);
    _countdownController = AnimationController(
      vsync: this,
      duration: duration,
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _advanceOrClose();
        }
      })
      ..forward();
  }

  void _advanceOrClose() {
    final slides = _config?.slides ?? [];
    if (_currentPage < slides.length - 1) {
      _currentPage++;
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _countdownController.reset();
      _countdownController.forward();
    } else {
      _navigateNext();
    }
  }

  void _navigateNext() {
    _countdownController.stop();
    // 根据是否首次安装决定去 Onboarding 还是主页
    final isFirstLaunch = _prefs.getBool('is_first_launch') ?? true;
    if (isFirstLaunch) {
      context.go('/onboarding');
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_config == null || _config!.slides.isEmpty) {
      // 无配置直接跳过
      WidgetsBinding.instance.addPostFrameCallback((_) => _navigateNext());
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 全屏轮播
          PageView.builder(
            controller:  _pageController,
            itemCount:   _config!.slides.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
              _countdownController.reset();
              _countdownController.forward();
            },
            itemBuilder: (context, index) {
              final slide = _config!.slides[index];
              return GestureDetector(
                onTap: () => handleSplashTap(slide),
                child: _AdaptiveImage(imageUrl: slide.imageUrl),
              );
            },
          ),

          // 右上角：倒计时 + Skip
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: _CountdownSkipButton(
              controller:      _countdownController,
              durationSeconds: _config!.durationSeconds,
              onSkip:          _navigateNext,
            ),
          ),

          // 底部 page indicator（多图时显示）
          if (_config!.slides.length > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 20,
              left:   0,
              right:  0,
              child:  _PageIndicator(
                count:   _config!.slides.length,
                current: _currentPage,
              ),
            ),
        ],
      ),
    );
  }
}
```

---

## 四、Onboarding 设计

### 4.1 UI 结构

```
┌──────────────────────────────────┐
│                                  │
│        [引导图（上半屏）]          │
│                                  │
│                                  │
├──────────────────────────────────┤
│                                  │
│   Discover Local Deals           │  ← 标题（大字）
│   Save up to 60% at              │  ← 副标题（小字）
│   restaurants near you           │
│                                  │
│         ● ○ ○                   │  ← indicator
│                                  │
│   [        Next        ]         │  ← 最后一页变 "Get Started"
│                                  │
└──────────────────────────────────┘
```

### 4.2 自适应布局

```dart
class _AdaptiveImage extends StatelessWidget {
  final String imageUrl;
  const _AdaptiveImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CachedNetworkImage(
          imageUrl:   imageUrl,
          width:      constraints.maxWidth,
          height:     constraints.maxHeight,
          fit:        BoxFit.cover,
          // 按屏幕宽度选择不同分辨率（Supabase Image Transform）
          imageUrl: _getOptimizedUrl(imageUrl, constraints.maxWidth),
        );
      },
    );
  }

  String _getOptimizedUrl(String url, double width) {
    // Supabase Storage Image Transform：按屏幕宽度请求适配分辨率
    final w = width.ceil();
    if (url.contains('supabase')) {
      return '$url?width=$w&quality=80';
    }
    return url;
  }
}
```

### 4.3 首次安装标记

```dart
// Onboarding 完成后标记，之后不再显示
Future<void> completeOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('is_first_launch', false);
  if (mounted) context.go('/home');
}
```

---

## 五、Homepage Banner 设计

### 5.1 UI 位置

```
┌──────────────────────────────────┐
│  Crunchy Plum           🔔 👤   │  ← AppBar
├──────────────────────────────────┤
│  ┌──────────────────────────┐    │
│  │   [Banner 轮播图]         │    │  ← 16:6 比例，自动轮播
│  │                    ● ○ ○ │    │
│  └──────────────────────────┘    │
│                                  │
│  Featured Deals                  │
│  ...                             │
└──────────────────────────────────┘
```

### 5.2 Banner 比例与自适应

```dart
class HomeBanner extends StatefulWidget {
  const HomeBanner({super.key});
}

class _HomeBannerState extends State<HomeBanner> {
  final PageController _pageController = PageController();
  Timer? _autoPlayTimer;
  int _currentPage = 0;
  BannerConfig? _config;

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  Future<void> _loadBanner() async {
    final config = await _repo.fetchActiveBannerConfig();
    if (config != null && mounted) {
      setState(() => _config = config);
      _startAutoPlay(config.autoPlaySeconds);
    }
  }

  void _startAutoPlay(int seconds) {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (_config == null) return;
      final next = (_currentPage + 1) % _config!.slides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_config == null || _config!.slides.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 16:6 比例（宽:高），屏幕越大 Banner 越高但保持比例
        final bannerHeight = constraints.maxWidth * 6 / 16;

        return SizedBox(
          height: bannerHeight,
          child: Stack(
            children: [
              PageView.builder(
                controller:    _pageController,
                itemCount:     _config!.slides.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder:   (context, index) {
                  final slide = _config!.slides[index];
                  return GestureDetector(
                    onTap: () => handleBannerTap(slide),
                    child: _AdaptiveImage(imageUrl: slide.imageUrl),
                  );
                },
              ),
              // Page Indicator（右下角）
              Positioned(
                right:  12,
                bottom: 8,
                child:  _PageIndicator(
                  count:   _config!.slides.length,
                  current: _currentPage,
                  dark:    false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }
}
```

---

## 六、Admin 后台配置页

### 6.1 三个配置模块入口

```
/admin/content/splash      → Splash 配置
/admin/content/onboarding  → Onboarding 配置
/admin/content/banner      → Homepage Banner 配置
```

### 6.2 Splash 配置页 UI

```
┌─────────────────────────────────────────────────┐
│  Splash Screen Configuration                    │
│                                                 │
│  Duration per slide: [5] seconds                │
│                                                 │
│  Slides (drag to reorder)                       │
│  ┌─────────────────────────────────────────┐    │
│  │ ⠿ [图片预览 80×60] Slide 1             │    │
│  │   Link: deal › Deal A                   │    │
│  │   [Edit] [Delete]                       │    │
│  └─────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────┐    │
│  │ ⠿ [图片预览 80×60] Slide 2             │    │
│  │   Link: external › https://...          │    │
│  │   [Edit] [Delete]                       │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  [+ Add Slide]                                  │
│                                                 │
│  [Preview]  [Save Draft]  [Activate]            │
└─────────────────────────────────────────────────┘
```

### 6.3 Add/Edit Slide 弹窗

```
┌──────────────────────────────────────┐
│  Edit Slide                          │
│                                      │
│  Image                               │
│  [Upload Image]  或  [Enter URL]     │
│  [图片预览区 16:9]                    │
│                                      │
│  Link Type                           │
│  ○ No link                           │
│  ○ Deal      [搜索并选择 Deal]        │
│  ○ Merchant  [搜索并选择 Merchant]   │
│  ○ External URL                      │
│    [https://...]                     │
│                                      │
│  [Cancel]  [Save]                    │
└──────────────────────────────────────┘
```

### 6.4 Onboarding 配置页

```
┌─────────────────────────────────────────────────┐
│  Onboarding Configuration                       │
│                                                 │
│  Slides (min 1, max 5)                         │
│  ┌─────────────────────────────────────────┐    │
│  │ ⠿ [图片预览] Slide 1                   │    │
│  │   Title: Discover Local Deals           │    │
│  │   Subtitle: Save up to 60%...           │    │
│  │   [Edit] [Delete]                       │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  [+ Add Slide]                                  │
│                                                 │
│  [Preview]  [Save Draft]  [Activate]            │
│                                                 │
│  ⚠️ Activating will show to first-time users.   │
│     Existing users won't see this.              │
└─────────────────────────────────────────────────┘
```

### 6.5 Admin API

```typescript
// 获取当前 Splash 配置（App 调用，匿名可读）
GET /functions/v1/get-splash-config
Response: { slides: [...], durationSeconds: 5 }

// 获取当前 Onboarding 配置
GET /functions/v1/get-onboarding-config
Response: { slides: [...] }

// 获取当前 Banner 配置
GET /functions/v1/get-banner-config
Response: { slides: [...], autoPlaySeconds: 3 }

// Admin：更新配置（serviceRole，Admin 后台调用）
POST /functions/v1/update-splash-config
Body: { slides: [...], durationSeconds: 5 }

POST /functions/v1/activate-splash-config
Body: { configId: "uuid" }
```

---

## 七、Migration 文件

### 文件名：`[timestamp]_welcome_screens.sql`

```sql
-- ============================================================
-- Step 1: splash_configs 表
-- ============================================================
CREATE TABLE IF NOT EXISTS splash_configs (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_active        boolean NOT NULL DEFAULT false,
  duration_seconds int NOT NULL DEFAULT 5
                     CHECK (duration_seconds BETWEEN 3 AND 10),
  slides           jsonb NOT NULL DEFAULT '[]',
  created_by       uuid REFERENCES users(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_splash_configs_active
  ON splash_configs(is_active) WHERE is_active = true;

CREATE TRIGGER set_splash_configs_updated_at
  BEFORE UPDATE ON splash_configs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE splash_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "public_read_splash" ON splash_configs
  FOR SELECT USING (is_active = true);

-- 插入默认空配置
INSERT INTO splash_configs (is_active, duration_seconds, slides)
VALUES (true, 5, '[]');

-- ============================================================
-- Step 2: onboarding_configs 表
-- ============================================================
CREATE TABLE IF NOT EXISTS onboarding_configs (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_active  boolean NOT NULL DEFAULT false,
  slides     jsonb NOT NULL DEFAULT '[]',
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_onboarding_configs_active
  ON onboarding_configs(is_active) WHERE is_active = true;

CREATE TRIGGER set_onboarding_configs_updated_at
  BEFORE UPDATE ON onboarding_configs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE onboarding_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "public_read_onboarding" ON onboarding_configs
  FOR SELECT USING (is_active = true);

-- 插入默认 Onboarding（三页）
INSERT INTO onboarding_configs (is_active, slides) VALUES (
  true,
  '[
    {
      "id": "ob1",
      "image_url": "",
      "title": "Discover Local Deals",
      "subtitle": "Save up to 60% at restaurants and shops near you",
      "sort_order": 0
    },
    {
      "id": "ob2",
      "image_url": "",
      "title": "Buy Anytime, Refund Anytime",
      "subtitle": "No risk. Get a full refund before your coupon expires",
      "sort_order": 1
    },
    {
      "id": "ob3",
      "image_url": "",
      "title": "Share with Friends",
      "subtitle": "Gift coupons or share great deals with your friends",
      "sort_order": 2
    }
  ]'
);

-- ============================================================
-- Step 3: banner_configs 表
-- ============================================================
CREATE TABLE IF NOT EXISTS banner_configs (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_active         boolean NOT NULL DEFAULT false,
  auto_play_seconds int NOT NULL DEFAULT 3
                      CHECK (auto_play_seconds BETWEEN 2 AND 10),
  slides            jsonb NOT NULL DEFAULT '[]',
  created_by        uuid REFERENCES users(id),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_banner_configs_active
  ON banner_configs(is_active) WHERE is_active = true;

CREATE TRIGGER set_banner_configs_updated_at
  BEFORE UPDATE ON banner_configs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE banner_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "public_read_banner" ON banner_configs
  FOR SELECT USING (is_active = true);

-- 插入默认空 Banner 配置
INSERT INTO banner_configs (is_active, auto_play_seconds, slides)
VALUES (true, 3, '[]');

-- ============================================================
-- Step 4: Storage bucket（CLI 或 Dashboard 执行）
-- ============================================================
-- supabase storage create welcome-media --public
-- 存放路径规则：
--   splash/{config_id}/{filename}
--   onboarding/{config_id}/{filename}
--   banner/{config_id}/{filename}
```

---

## 八、前端 Model

### 8.1 Models

```dart
class SplashConfig {
  final String id;
  final int durationSeconds;
  final List<WelcomeSlide> slides;
}

class OnboardingConfig {
  final String id;
  final List<OnboardingSlide> slides;
}

class BannerConfig {
  final String id;
  final int autoPlaySeconds;
  final List<WelcomeSlide> slides;
}

class WelcomeSlide {
  final String id;
  final String imageUrl;
  final String linkType;   // 'deal' | 'merchant' | 'external' | 'none'
  final String? linkValue;
  final int sortOrder;
}

class OnboardingSlide {
  final String id;
  final String imageUrl;
  final String title;
  final String subtitle;
  final int sortOrder;
}
```

### 8.2 Repository

```dart
class WelcomeRepository {
  // 每次 App 启动时调用，优先返回缓存，后台刷新
  Future<SplashConfig?> fetchActiveSplashConfig() async {
    try {
      final data = await supabase
          .from('splash_configs')
          .select()
          .eq('is_active', true)
          .single();
      return SplashConfig.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<OnboardingConfig?> fetchActiveOnboardingConfig() async {
    try {
      final data = await supabase
          .from('onboarding_configs')
          .select()
          .eq('is_active', true)
          .single();
      return OnboardingConfig.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<BannerConfig?> fetchActiveBannerConfig() async {
    try {
      final data = await supabase
          .from('banner_configs')
          .select()
          .eq('is_active', true)
          .single();
      return BannerConfig.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}
```

### 8.3 路由集成

```dart
// app_router.dart 中的路由顺序
GoRoute(
  path: '/splash',
  name: 'splash',
  builder: (context, state) => const SplashScreen(),
),
GoRoute(
  path: '/onboarding',
  name: 'onboarding',
  builder: (context, state) => const OnboardingScreen(),
),

// App 启动时的初始路由逻辑（main.dart 或 app.dart）
String getInitialRoute() {
  // Splash 配置为空（无图片）→ 直接跳过
  // 有 Splash 配置 → 显示 Splash（Splash 完成后判断 Onboarding）
  return '/splash';
}
```

---

## 九、执行顺序

```
Phase 0: 侦察 → 填检查表
    ↓
Phase 1: Migration
         - splash_configs 表（含默认数据）
         - onboarding_configs 表（含默认3页文案）
         - banner_configs 表
         - Storage bucket: welcome-media
    ↓ supabase db push（staging 验证）
Phase 2: Flutter 前端
         - WelcomeSlide / SplashConfig / BannerConfig Models
         - WelcomeRepository（三个 fetch 方法）
         - SplashScreen（轮播 + 倒计时 + Skip）
         - OnboardingScreen（滑动引导 + Get Started）
         - HomeBanner Widget（自适应比例 + 自动轮播）
         - _AdaptiveImage（LayoutBuilder + BoxFit.cover）
         - _CountdownSkipButton（CircularProgressIndicator）
         - 路由集成（修改初始路由逻辑）
         - SharedPreferences 首次安装标记
    ↓
Phase 3: Admin 后台
         - /admin/content/splash 页面
         - /admin/content/onboarding 页面
         - /admin/content/banner 页面
         - 图片上传到 Supabase Storage
         - Slide 排序（拖拽）
         - 激活逻辑（旧配置变 inactive）
    ↓
Phase 4: 构建 APK，手动验证
         - 首次安装：Splash → Onboarding → 主页
         - 非首次：Splash → 主页（跳过 Onboarding）
         - Splash 无配置（空 slides）：直接跳过
         - Splash 倒计时 + Skip 按钮
         - 图片点击跳转（Deal / Merchant / External）
         - 屏幕自适应（小屏/大屏/平板）
         - Admin 修改配置 → 下次 App 启动生效
         - Banner 自动轮播 + 手动滑动
    ↓
Phase 5: Maestro 测试
```

---

## Progress

### [2026-03-27] Phase 0 完成 ✅
- 侦察检查表：
  - 现有 Splash 页路径：`core/widgets/splash_screen.dart`（保留为 auth loading，新建 ad splash）
  - 现有 Onboarding 页路径：无（新建）
  - Storage bucket 名称：待创建 `welcome-media`
  - shared_preferences 版本：^2.3.3（已有）
  - Admin 后台框架：Next.js 16.1.6
  - 现有 splash_configs / banner_configs 表：否（需新建）
  - `update_updated_at_column()` 触发器：已存在

### [2026-03-27] Phase 1 完成 ✅
- 实际操作：
  - 创建 `supabase/migrations/20260327000001_welcome_screens.sql`
  - 通过 psql 直接执行 SQL，3 表全部创建成功
  - splash_configs: 默认空配置（is_active=true, slides=[]）
  - onboarding_configs: 默认 3 页文案（Discover / Refund / Share）
  - banner_configs: 默认空配置
  - RLS: 所有表公开可读（is_active=true 的记录）
  - 唯一索引确保同时只有一条 active 配置
- 差异：Storage bucket `welcome-media` 暂未创建（Admin 后台上传图片时创建）
- 跳过：无

### [2026-03-27] Phase 2 完成 ✅
- 实际操作：
  - **新建文件（10个）：**
    - `features/welcome/data/models/welcome_models.dart` — 5 个数据模型
    - `features/welcome/data/repositories/welcome_repository.dart` — 3 个 fetch 方法
    - `features/welcome/domain/providers/welcome_provider.dart` — 3 个 Provider
    - `features/welcome/presentation/screens/welcome_splash_screen.dart` — 开屏广告
    - `features/welcome/presentation/screens/onboarding_screen.dart` — 首次引导
    - `features/welcome/presentation/widgets/home_banner.dart` — 首页 Banner
    - `features/welcome/presentation/widgets/adaptive_image.dart` — 自适应图片
    - `features/welcome/presentation/widgets/countdown_skip_button.dart` — 倒计时按钮
    - `features/welcome/presentation/widgets/page_indicator.dart` — 圆点指示器
  - **修改文件（2个）：**
    - `core/router/app_router.dart`:
      - initialLocation: `/splash` → `/welcome`
      - 新增 `/welcome` 和 `/onboarding` 路由
      - redirect 逻辑豁免 welcome/onboarding 页面
    - `features/deals/presentation/screens/home_screen.dart`:
      - 非搜索模式下在分类图标上方插入 `HomeBanner` widget
  - Flutter analyze: 0 Error, 0 Warning
- 差异：
  - 设计文档用 `/splash` 路径做广告页，实际用 `/welcome` 避免与现有 auth loading splash 冲突
  - 现有 `/splash`（auth loading）保留作为认证状态解析时的安全回退
- 下一步：Phase 3（Admin 后台配置页）

### [2026-03-27] Phase 3 完成 ✅
- 实际操作：
  - **Server Action** `admin/app/actions/welcome-config.ts`:
    - Splash: getSplashConfig, updateSplashConfig, activateSplashConfig, createSplashConfig
    - Onboarding: getOnboardingConfig, updateOnboardingConfig, activateOnboardingConfig
    - Banner: getBannerConfig, updateBannerConfig, activateBannerConfig
  - **通用组件** `admin/components/slides-editor.tsx`:
    - WelcomeSlidesEditor（Splash/Banner 通用，支持图片URL、链接类型、排序、删除）
    - OnboardingSlidesEditor（Onboarding 专用，支持标题、副标题、图片）
  - **3 个配置页面**:
    - `/settings/splash` — 状态卡片 + SplashConfigEditor
    - `/settings/onboarding` — 状态卡片 + OnboardingConfigEditor
    - `/settings/banner` — 状态卡片 + BannerConfigEditor
  - **Sidebar 更新**: 新增 "Content" 分组（Splash Screen / Onboarding / Homepage Banner）
  - Sidebar group 展开逻辑重构：支持多个 group 独立展开/折叠
- 差异：
  - 路径用 `/settings/splash` 而非 `/admin/content/splash`，与现有 settings 页面一致
  - 图片上传暂用 URL 输入（Storage bucket 上传需后续集成）
  - Slide 排序用上下箭头而非拖拽（简化实现）
- TypeScript 编译：新增文件无错误（已有错误与本次改动无关）
