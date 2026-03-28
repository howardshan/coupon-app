import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/welcome_models.dart';
import '../../domain/providers/welcome_provider.dart';
import '../widgets/adaptive_image.dart';
import '../widgets/countdown_skip_button.dart';
import '../widgets/page_indicator.dart';

/// 开屏广告 Splash Screen
/// 每次启动显示，支持多图轮播、倒计时跳过、点击跳转
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
  SplashConfig? _config;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    debugPrint('[Splash] _loadConfig 开始');
    final config =
        await ref.read(welcomeRepositoryProvider).fetchActiveSplashConfig();
    debugPrint('[Splash] config=${config?.slides.length ?? 'null'} slides');
    if (!mounted) {
      debugPrint('[Splash] widget 已卸载，跳过');
      return;
    }

    // 无配置或无图片 → 直接跳过
    if (config == null || config.slides.isEmpty) {
      debugPrint('[Splash] 无图片，直接跳过');
      _navigateNext();
      return;
    }

    debugPrint('[Splash] 显示 ${config.slides.length} 张图片，每张 ${config.durationSeconds}s');
    setState(() => _config = config);
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

  /// 当前图片倒计时结束：切换下一张或退出
  void _advanceOrClose() {
    final slides = _config?.slides ?? [];
    if (_currentPage < slides.length - 1) {
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

  /// 点击图片跳转对应链接
  void _handleSlideTap(WelcomeSlide slide) {
    switch (slide.linkType) {
      case 'deal':
        if (slide.linkValue != null && slide.linkValue!.isNotEmpty) {
          _countdownController?.stop();
          context.go('/deals/${slide.linkValue}');
        }
      case 'merchant':
        if (slide.linkValue != null && slide.linkValue!.isNotEmpty) {
          _countdownController?.stop();
          context.go('/merchant/${slide.linkValue}');
        }
      case 'external':
        if (slide.linkValue != null && slide.linkValue!.isNotEmpty) {
          launchUrl(Uri.parse(slide.linkValue!),
              mode: LaunchMode.externalApplication);
        }
      default:
        // 'none' — 点击无操作
        break;
    }
  }

  @override
  void dispose() {
    _countdownController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 配置未加载完 — 显示品牌 Logo loading
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

    final slides = _config!.slides;
    final padding = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 全屏轮播图片
          PageView.builder(
            controller: _pageController,
            itemCount: slides.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
              // 手动滑动重置倒计时
              _countdownController?.reset();
              _countdownController?.forward();
            },
            itemBuilder: (context, index) {
              final slide = slides[index];
              return GestureDetector(
                onTap: () => _handleSlideTap(slide),
                child: AdaptiveImage(imageUrl: slide.imageUrl),
              );
            },
          ),

          // 右上角：倒计时 + Skip
          if (_countdownController != null)
            Positioned(
              top: padding.top + 12,
              right: 16,
              child: CountdownSkipButton(
                controller: _countdownController!,
                durationSeconds: _config!.durationSeconds,
                onSkip: _advanceOrClose,
              ),
            ),

          // 底部 page indicator（多图时显示）
          if (slides.length > 1)
            Positioned(
              bottom: padding.bottom + 20,
              left: 0,
              right: 0,
              child: PageIndicator(
                count: slides.length,
                current: _currentPage,
              ),
            ),
        ],
      ),
    );
  }
}
