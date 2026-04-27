// 用户端 Stripe：与 ios/Runner/Info.plist CFBundleURLSchemes 中 crunchyplum 一致
abstract final class StripeAppConfig {
  static const String urlScheme = 'crunchyplum';

  /// PaymentSheet 3DS 回跳，与原生 URL scheme 一致
  static const String paymentSheetReturnUrl = '$urlScheme://stripe-redirect';
}
