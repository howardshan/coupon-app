import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/welcome_models.dart';
import '../../domain/providers/welcome_provider.dart';
import 'adaptive_image.dart';
import 'page_indicator.dart';

/// 首页顶部 Banner 轮播组件
/// 16:6 比例，自动轮播，每图独立链接
class HomeBanner extends ConsumerStatefulWidget {
  const HomeBanner({super.key});

  @override
  ConsumerState<HomeBanner> createState() => _HomeBannerState();
}

class _HomeBannerState extends ConsumerState<HomeBanner> {
  final PageController _pageController = PageController();
  Timer? _autoPlayTimer;
  int _currentPage = 0;
  bool _autoPlayStarted = false;

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoPlay(int seconds, int slideCount) {
    _autoPlayTimer?.cancel();
    if (slideCount <= 1) return;
    _autoPlayStarted = true;
    _autoPlayTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (!mounted) return;
      final next = (_currentPage + 1) % slideCount;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  void _handleTap(WelcomeSlide slide, BuildContext context) {
    switch (slide.linkType) {
      case 'deal':
        if (slide.linkValue != null && slide.linkValue!.isNotEmpty) {
          context.push('/deals/${slide.linkValue}');
        }
      case 'merchant':
        if (slide.linkValue != null && slide.linkValue!.isNotEmpty) {
          context.push('/merchant/${slide.linkValue}');
        }
      case 'external':
        if (slide.linkValue != null && slide.linkValue!.isNotEmpty) {
          launchUrl(Uri.parse(slide.linkValue!),
              mode: LaunchMode.externalApplication);
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(bannerConfigProvider);

    return configAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (config) {
        if (config == null || config.slides.isEmpty) {
          return const SizedBox.shrink();
        }

        // 启动自动轮播（仅首次数据加载完成时）
        if (!_autoPlayStarted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _startAutoPlay(config.autoPlaySeconds, config.slides.length);
          });
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            // 16:6 比例（宽:高）
            final bannerHeight = constraints.maxWidth * 6 / 16;

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: bannerHeight,
                  child: Stack(
                    children: [
                      // 轮播图
                      PageView.builder(
                        controller: _pageController,
                        itemCount: config.slides.length,
                        onPageChanged: (i) {
                          setState(() => _currentPage = i);
                          // 手动滑动后重置自动轮播计时
                          _startAutoPlay(
                              config.autoPlaySeconds, config.slides.length);
                        },
                        itemBuilder: (context, index) {
                          final slide = config.slides[index];
                          return GestureDetector(
                            onTap: () => _handleTap(slide, context),
                            child: AdaptiveImage(imageUrl: slide.imageUrl),
                          );
                        },
                      ),

                      // 右下角 Page Indicator
                      if (config.slides.length > 1)
                        Positioned(
                          right: 12,
                          bottom: 8,
                          child: PageIndicator(
                            count: config.slides.length,
                            current: _currentPage,
                            dark: false,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
