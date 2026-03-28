// 欢迎页面系统数据模型：Splash / Onboarding / Banner

// ── Splash 广告轮播图片 ──
class WelcomeSlide {
  final String id;
  final String imageUrl;
  final String linkType; // 'deal' | 'merchant' | 'external' | 'none'
  final String? linkValue;
  final int sortOrder;

  const WelcomeSlide({
    required this.id,
    required this.imageUrl,
    this.linkType = 'none',
    this.linkValue,
    this.sortOrder = 0,
  });

  factory WelcomeSlide.fromJson(Map<String, dynamic> json) {
    return WelcomeSlide(
      id: json['id'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      linkType: json['link_type'] as String? ?? 'none',
      linkValue: json['link_value'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

// ── Onboarding 引导页 ──
class OnboardingSlide {
  final String id;
  final String imageUrl;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final int sortOrder;

  const OnboardingSlide({
    required this.id,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.sortOrder = 0,
  });

  factory OnboardingSlide.fromJson(Map<String, dynamic> json) {
    return OnboardingSlide(
      id: json['id'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      ctaLabel: json['cta_label'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

// ── Splash 配置 ──
class SplashConfig {
  final String id;
  final int durationSeconds;
  final List<WelcomeSlide> slides;

  const SplashConfig({
    required this.id,
    required this.durationSeconds,
    required this.slides,
  });

  factory SplashConfig.fromJson(Map<String, dynamic> json) {
    final rawSlides = json['slides'] as List<dynamic>? ?? [];
    final slides = rawSlides
        .map((s) => WelcomeSlide.fromJson(s as Map<String, dynamic>))
        .where((s) => s.imageUrl.isNotEmpty) // 过滤空图片
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return SplashConfig(
      id: json['id'] as String? ?? '',
      durationSeconds: json['duration_seconds'] as int? ?? 5,
      slides: slides,
    );
  }
}

// ── Onboarding 配置 ──
class OnboardingConfig {
  final String id;
  final List<OnboardingSlide> slides;

  const OnboardingConfig({
    required this.id,
    required this.slides,
  });

  factory OnboardingConfig.fromJson(Map<String, dynamic> json) {
    final rawSlides = json['slides'] as List<dynamic>? ?? [];
    final slides = rawSlides
        .map((s) => OnboardingSlide.fromJson(s as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return OnboardingConfig(
      id: json['id'] as String? ?? '',
      slides: slides,
    );
  }
}

// ── Banner 配置 ──
class BannerConfig {
  final String id;
  final int autoPlaySeconds;
  final List<WelcomeSlide> slides;

  const BannerConfig({
    required this.id,
    required this.autoPlaySeconds,
    required this.slides,
  });

  factory BannerConfig.fromJson(Map<String, dynamic> json) {
    final rawSlides = json['slides'] as List<dynamic>? ?? [];
    final slides = rawSlides
        .map((s) => WelcomeSlide.fromJson(s as Map<String, dynamic>))
        .where((s) => s.imageUrl.isNotEmpty)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return BannerConfig(
      id: json['id'] as String? ?? '',
      autoPlaySeconds: json['auto_play_seconds'] as int? ?? 3,
      slides: slides,
    );
  }
}
