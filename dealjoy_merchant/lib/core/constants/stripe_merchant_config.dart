// Stripe iOS/Android：URL scheme 与 PaymentSheet returnURL 须与原生配置一致
// - ios/Runner/Info.plist → CFBundleURLTypes / CFBundleURLSchemes
// - android/app/src/main/AndroidManifest.xml → intent-filter data android:scheme

/// 商家端 Stripe 与原生 plist/AndroidManifest 共用的常量（勿只改一处）
abstract final class StripeMerchantConfig {
  /// 与 Info.plist、AndroidManifest、main.dart 中 Stripe.urlScheme 一致
  static const String urlScheme = 'crunchyplum-merchant';

  /// PaymentSheet 的 returnURL（Stripe SDK 要求；与 urlScheme 联动）
  /// 参见：https://stripe.com/docs/payments/accept-a-payment?platform=ios&ui=payment-sheet
  static const String paymentSheetReturnUrl = '$urlScheme://stripe-redirect';
}
