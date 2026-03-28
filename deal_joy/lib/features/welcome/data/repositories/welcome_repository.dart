import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/welcome_models.dart';

/// 欢迎页面系统数据层：从 Supabase 读取 Splash / Onboarding / Banner 配置
class WelcomeRepository {
  final SupabaseClient _client;

  WelcomeRepository(this._client);

  /// 获取当前活跃的 Splash 广告配置
  Future<SplashConfig?> fetchActiveSplashConfig() async {
    try {
      final data = await _client
          .from('splash_configs')
          .select()
          .eq('is_active', true)
          .maybeSingle();
      if (data == null) return null;
      return SplashConfig.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// 获取当前活跃的 Onboarding 引导配置
  Future<OnboardingConfig?> fetchActiveOnboardingConfig() async {
    try {
      final data = await _client
          .from('onboarding_configs')
          .select()
          .eq('is_active', true)
          .maybeSingle();
      if (data == null) return null;
      return OnboardingConfig.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// 获取当前活跃的首页 Banner 配置
  Future<BannerConfig?> fetchActiveBannerConfig() async {
    try {
      final data = await _client
          .from('banner_configs')
          .select()
          .eq('is_active', true)
          .maybeSingle();
      if (data == null) return null;
      return BannerConfig.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}
