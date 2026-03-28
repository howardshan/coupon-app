import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/welcome_models.dart';
import '../../data/repositories/welcome_repository.dart';

/// Repository provider
final welcomeRepositoryProvider = Provider<WelcomeRepository>((ref) {
  return WelcomeRepository(Supabase.instance.client);
});

/// Splash 广告配置（App 启动时加载一次）
final splashConfigProvider = FutureProvider.autoDispose<SplashConfig?>((ref) {
  return ref.read(welcomeRepositoryProvider).fetchActiveSplashConfig();
});

/// Onboarding 引导配置（首次安装时加载一次）
final onboardingConfigProvider =
    FutureProvider.autoDispose<OnboardingConfig?>((ref) {
  return ref.read(welcomeRepositoryProvider).fetchActiveOnboardingConfig();
});

/// 首页 Banner 配置
final bannerConfigProvider = FutureProvider.autoDispose<BannerConfig?>((ref) {
  return ref.read(welcomeRepositoryProvider).fetchActiveBannerConfig();
});
