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
        body: const Center(child: CircularProgressIndicator()),
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
    // 图片区高度：屏幕高度的 45%，最小 280，最大 400
    // 在 iPad 宽屏上避免图片过度拉伸占满整个 Expanded 区域
    final screenHeight = MediaQuery.of(context).size.height;
    final imageHeight = (screenHeight * 0.45).clamp(280.0, 400.0);

    return Center(
      child: ConstrainedBox(
        // iPad 宽屏：内容区限制最大宽度 600，居中显示
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 引导图（响应式高度，避免在 iPad 上过大或截断）
              SizedBox(
                height: imageHeight,
                child: slide.imageUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: AdaptiveImage(imageUrl: slide.imageUrl),
                      )
                    : Center(
                        child: Icon(
                          Icons.local_offer,
                          size: 120,
                          color: AppColors.primary.withValues(alpha: 0.3),
                        ),
                      ),
              ),

              const SizedBox(height: 32),

              // 标题 + 副标题（加 maxLines 防截断，overflow 用 ellipsis 兜底）
              Text(
                slide.title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                slide.subtitle,
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
