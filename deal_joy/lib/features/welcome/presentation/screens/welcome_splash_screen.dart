import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/splash_ad_model.dart';
import '../../data/models/welcome_models.dart';
import '../../domain/providers/welcome_provider.dart';
import '../widgets/adaptive_image.dart';
import '../widgets/countdown_skip_button.dart';
import '../widgets/page_indicator.dart';

/// 开屏广告 Splash Screen
/// 支持竞价广告（基于 GPS 定位）和静态配置两种模式
/// 竞价优先，无竞价 fallback 到静态配置
class WelcomeSplashScreen extends ConsumerStatefulWidget {
  const WelcomeSplashScreen({super.key});

  @override
  ConsumerState<WelcomeSplashScreen> createState() =>
      _WelcomeSplashScreenState();
}

class _WelcomeSplashScreenState extends ConsumerState<WelcomeSplashScreen>
    with TickerProviderStateMixin {
  AnimationController? _countdownController;
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _navigated = false;

  // 静态配置模式
  SplashConfig? _config;

  // 竞价广告模式
  List<SplashAdSlide> _adSlides = [];
  bool _isAdMode = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    debugPrint('[Splash] _loadConfig 开始');
    final repo = ref.read(welcomeRepositoryProvider);
    final prefs = await SharedPreferences.getInstance();

    // 记录 app_open 埋点（仅登录用户，user_events.user_id NOT NULL）
    _recordAppOpen();

    // ── Step 1: 检查今天是否已展示过竞价广告 ──
    final lastAdDate = prefs.getString('last_splash_ad_date');
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (lastAdDate != today) {
      // ── Step 2: 尝试获取位置（不弹权限框，只用缓存） ──
      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (e) {
        debugPrint('[Splash] 获取位置失败: $e');
      }

      if (position != null) {
        debugPrint('[Splash] 有位置: ${position.latitude}, ${position.longitude}');
        // ── Step 3: 有位置 → 查竞价广告 ──
        final ads = await repo.fetchSplashAds(
          lat: position.latitude,
          lng: position.longitude,
        );
        debugPrint('[Splash] 竞价广告: ${ads.length} 条');

        if (!mounted) return;

        if (ads.isNotEmpty) {
          // ── Step 4: 有竞价广告 → 竞价模式 ──
          await prefs.setString('last_splash_ad_date', today);
          setState(() {
            _adSlides = ads;
            _isAdMode = true;
            // 竞价模式用虚拟 config（仅为驱动倒计时）
            _config = SplashConfig(
              id: 'ad',
              durationSeconds: 5,
              slides: [],
            );
          });
          _startCountdown();
          // P7: 首屏 impression 用 addPostFrameCallback 确保 build 完成后记录
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _recordAdEvent(ads.first.campaignId, 'impression');
          });
          return;
        }
      } else {
        debugPrint('[Splash] 无位置缓存，直接进首页');
        _navigateNext();
        return;
      }
    } else {
      debugPrint('[Splash] 今天已展示过竞价广告，直接进首页');
      _navigateNext();
      return;
    }

    // ── Step 5: 无竞价广告 → 直接进首页 ──
    debugPrint('[Splash] 无竞价广告，直接进首页');
    _navigateNext();
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

  /// 当前图片倒计时结束：切换下一张或退出
  void _advanceOrClose() {
    final totalSlides = _isAdMode ? _adSlides.length : (_config?.slides.length ?? 0);
    if (_currentPage < totalSlides - 1) {
      _currentPage++;
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _countdownController?.reset();
      _countdownController?.forward();
    } else {
      _navigateNext();
    }
  }

  /// 退出 Splash，根据是否首次安装决定去 Onboarding 或首页
  Future<void> _navigateNext() async {
    if (_navigated) return;
    _navigated = true;
    _countdownController?.stop();

    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = prefs.getBool('is_first_launch') ?? true;
    debugPrint('[Splash] _navigateNext: isFirstLaunch=$isFirstLaunch');

    if (!mounted) return;
    if (isFirstLaunch) {
      debugPrint('[Splash] → /onboarding');
      context.go('/onboarding');
    } else {
      debugPrint('[Splash] → /home');
      context.go('/home');
    }
  }

  /// 点击静态 slide 跳转对应链接（P6: 显式 break + external 安全校验）
  void _handleSlideTap(WelcomeSlide slide) {
    switch (slide.linkType) {
      case 'deal':
        if (slide.linkValue != null && slide.linkValue!.isNotEmpty) {
          _countdownController?.stop();
          context.go('/deals/${slide.linkValue}');
        }
        break;
      case 'merchant':
        if (slide.linkValue != null && slide.linkValue!.isNotEmpty) {
          _countdownController?.stop();
          context.go('/merchant/${slide.linkValue}');
        }
        break;
      case 'external':
        // C7: 安全校验 — 仅允许 http/https
        final uri = Uri.tryParse(slide.linkValue ?? '');
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
      default:
        // 'none' — 点击无操作
        break;
    }
  }

  /// 点击竞价广告 slide — 记录 click（CPC 扣费）+ 跳转
  void _handleAdSlideTap(SplashAdSlide ad) {
    // 记录 click 事件（CPC 模式下扣费）
    _recordAdEvent(ad.campaignId, 'click');
    // linkType 为 none 时仅记录 click，不跳转
    if (ad.linkType == 'none') return;
    // 复用静态 slide 跳转逻辑
    _countdownController?.stop();
    _handleSlideTap(ad.toWelcomeSlide());
  }

  /// Skip 按钮 — 竞价模式下记录 skip 事件
  void _handleSkip() {
    if (_isAdMode && _currentPage < _adSlides.length) {
      _recordAdEvent(_adSlides[_currentPage].campaignId, 'skip');
    }
    _advanceOrClose();
  }

  /// app_open 埋点（仅登录用户，fire-and-forget）
  void _recordAppOpen() {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return; // 未登录不记录（user_events.user_id NOT NULL）
    unawaited(() async {
      try {
        Position? pos;
        try {
          pos = await Geolocator.getLastKnownPosition();
        } catch (_) {}
        await client.from('user_events').insert({
          'user_id': userId,
          'event_type': 'app_open',
          'metadata': pos != null
              ? {'lat': pos.latitude, 'lng': pos.longitude}
              : null,
        });
      } catch (e) {
        debugPrint('[Splash] recordAppOpen error: $e');
      }
    }());
  }

  /// fire-and-forget 广告事件记录（不阻塞 UI）
  void _recordAdEvent(String campaignId, String eventType) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    debugPrint('[Splash] recordAdEvent: $eventType, campaign=$campaignId, user=$userId');
    unawaited(
      Supabase.instance.client.functions.invoke('record-ad-event', body: {
        'campaign_id': campaignId,
        'event_type': eventType,
        'user_id': userId,
      }).catchError((e) {
        debugPrint('[Splash] recordAdEvent error: $e');
        return FunctionResponse(status: 500, data: {});
      }),
    );
  }

  @override
  void dispose() {
    _countdownController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 配置未加载完 — 显示 loading
    if (_config == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    final totalSlides = _isAdMode ? _adSlides.length : _config!.slides.length;
    final padding = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 全屏轮播图片
          PageView.builder(
            controller: _pageController,
            itemCount: totalSlides,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
              // 手动滑动重置倒计时
              _countdownController?.reset();
              _countdownController?.forward();
              // P7: 竞价模式下记录后续 slide 的 impression（index > 0）
              if (_isAdMode && index > 0 && index < _adSlides.length) {
                _recordAdEvent(_adSlides[index].campaignId, 'impression');
              }
            },
            itemBuilder: (context, index) {
              if (_isAdMode) {
                // ── 竞价广告模式 ──
                final ad = _adSlides[index];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (_) => _handleAdSlideTap(ad),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AdaptiveImage(imageUrl: ad.creativeUrl, fit: BoxFit.fill),
                      // 左下角 "Ad" 标识 + 商家名
                      Positioned(
                        left: 16,
                        bottom: padding.bottom + 50,
                        child: _AdBadge(merchantName: ad.merchantName),
                      ),
                    ],
                  ),
                );
              }
              // ── 静态配置模式 ──
              final slide = _config!.slides[index];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (_) => _handleSlideTap(slide),
                child: AdaptiveImage(
                  imageUrl: slide.imageUrl,
                  fit: BoxFit.fill,
                ),
              );
            },
          ),

          // 右上角：倒计时 + Skip（竞价模式用 _handleSkip 记录 skip 事件）
          if (_countdownController != null)
            Positioned(
              top: padding.top + 12,
              right: 16,
              child: CountdownSkipButton(
                controller: _countdownController!,
                durationSeconds: _config!.durationSeconds,
                onSkip: _isAdMode ? _handleSkip : _advanceOrClose,
              ),
            ),

          // 底部 page indicator（多图时显示）
          if (totalSlides > 1)
            Positioned(
              bottom: padding.bottom + 20,
              left: 0,
              right: 0,
              child: PageIndicator(
                count: totalSlides,
                current: _currentPage,
              ),
            ),
        ],
      ),
    );
  }
}

/// 竞价广告左下角标识
class _AdBadge extends StatelessWidget {
  final String merchantName;
  const _AdBadge({required this.merchantName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.amber.shade700,
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              'Ad',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            merchantName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
