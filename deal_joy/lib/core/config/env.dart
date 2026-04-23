import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  static String get stripePublishableKey =>
      dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? '';

  /// Apple Pay Merchant ID（须与 Xcode Apple Pay capability 一致）。可在 .env 覆盖。
  static String get stripeApplePayMerchantId =>
      dotenv.env['STRIPE_APPLE_PAY_MERCHANT_ID'] ??
      'merchant.com.crunchyplum.crunchyplum';

  static String get googleWebClientId =>
      dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';
}
