import 'welcome_models.dart';

/// 竞价开屏广告 slide 数据模型
/// 对应 RPC get_splash_ads 返回的数据
class SplashAdSlide {
  final String campaignId;
  final String merchantId;
  final String creativeUrl;     // 9:16 广告图片 URL
  final String linkType;        // 'deal' | 'merchant' | 'external' | 'none'
  final String? linkValue;      // deal_id / merchant_id / URL
  final String merchantName;
  final String? merchantLogoUrl;

  const SplashAdSlide({
    required this.campaignId,
    required this.merchantId,
    required this.creativeUrl,
    required this.linkType,
    this.linkValue,
    required this.merchantName,
    this.merchantLogoUrl,
  });

  /// 从 RPC 返回的 JSON 构造，所有字段 null-safe
  factory SplashAdSlide.fromJson(Map<String, dynamic> json) {
    return SplashAdSlide(
      campaignId:      json['campaign_id'] as String? ?? '',
      merchantId:      json['merchant_id'] as String? ?? '',
      creativeUrl:     json['creative_url'] as String? ?? '',
      linkType:        json['splash_link_type'] as String? ?? 'none',
      linkValue:       json['splash_link_value'] as String?,
      merchantName:    json['merchant_name'] as String? ?? '',
      merchantLogoUrl: json['merchant_logo_url'] as String?,
    );
  }

  /// 转换为 WelcomeSlide，复用 _handleSlideTap 跳转逻辑
  WelcomeSlide toWelcomeSlide() {
    return WelcomeSlide(
      id: campaignId,
      imageUrl: creativeUrl,
      linkType: linkType,
      linkValue: linkValue,
      sortOrder: 0,
    );
  }
}
