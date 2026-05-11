import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/welcome_provider.dart';
import '../../data/models/welcome_models.dart';
import '../widgets/adaptive_image.dart';
import '../widgets/page_indicator.dart';

/// 首次安装引导页（Onboarding）
/// 仅首次安装后显示，之后不再显示
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  OnboardingConfig? _config;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await ref
        .read(welcomeRepositoryProvider)
        .fetchActiveOnboardingConfig();
    if (!mounted) return;

    // 无配置或无有效 slide → 直接完成
    if (config == null || config.slides.isEmpty) {
      _completeOnboarding();
      return;
    }

    setState(() {
      _config = config;
      _loading = false;
    });
  }

  /// 完成 Onboarding，标记为非首次安装
  /// 已登录 → /welcome（开屏广告流程）；未登录 → /home（游客可浏览）
  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_launch', false);
    // 更新 provider，避免 router redirect 再次重定向到 onboarding
    ref.read(isFirstLaunchProvider.notifier).state = false;
    if (!mounted) return;
    final session = Supabase.instance.client.auth.currentSession;
    context.go(session != null ? '/welcome' : '/home');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Loading…',
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final slides = _config!.slides;
    final isLastPage = _currentPage == slides.length - 1;
    final padding = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // 右上角 Skip 按钮
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16, top: 8),
                child: TextButton(
                  onPressed: _completeOnboarding,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

            // 滑动引导页
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: slides.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  return _OnboardingPage(slide: slides[index]);
                },
              ),
            ),

            // 底部：指示器 + 按钮（iPad 上加 maxWidth 约束，避免按钮横铺全屏）
            Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, padding.bottom + 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Column(
                    children: [
                      PageIndicator(
                        count: slides.length,
                        current: _currentPage,
                        dark: false,
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            if (isLastPage) {
                              _completeOnboarding();
                            } else {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            isLastPage ? 'Get Started' : 'Next',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 单页引导内容 ──
class _OnboardingPage extends StatelessWidget {
  final OnboardingSlide slide;
  const _OnboardingPage({required this.slide});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final screenHeight = size.height;
    final isTablet = size.shortestSide >= 600;
    // 平板：更高图片区 + BoxFit.contain，避免扁宽视口 + cover 裁切上下文案
    // 手机：略低比例，仍用 contain 与审核环境一致
    final double imageHeight = isTablet
        ? (screenHeight * 0.48).clamp(340.0, 540.0)
        : (screenHeight * 0.40).clamp(260.0, 400.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: imageHeight,
                      child: slide.imageUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: ColoredBox(
                                color: AppColors.background,
                                child: AdaptiveImage(
                                  imageUrl: slide.imageUrl,
                                  fit: BoxFit.contain,
                                  useProminentPlaceholder: true,
                                ),
                              ),
                            )
                          : Center(
                              child: Icon(
                                Icons.local_offer,
                                size: 120,
                                color: AppColors.primary.withValues(alpha: 0.3),
                              ),
                            ),
                    ),
                    SizedBox(height: isTablet ? 28 : 24),
                    Text(
                      slide.title,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isTablet ? 28 : 26,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      slide.subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isTablet ? 17 : 16,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
