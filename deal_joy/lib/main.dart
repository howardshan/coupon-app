import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/env.dart';
import 'core/constants/stripe_app_config.dart';
import 'features/deals/domain/providers/deals_provider.dart';
import 'shared/services/referral_link_service.dart';
import 'app.dart';

// FCM 后台消息处理器（必须是顶层函数）
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM] background message: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  // Initialize Supabase
  try {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );
  } catch (e) {
    debugPrint('[CrunchyPlum] Supabase init failed: $e');
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Failed to connect to server.\n'
              'Please check your internet connection and restart the app.\n\n'
              'Error: $e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ));
    return;
  }

  // Initialize Firebase (non-blocking — app works without it)
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[CrunchyPlum] Firebase init failed: $e — push disabled');
  }

  // Initialize Stripe (non-blocking — app works without it)
  try {
    final stripeKey = Env.stripePublishableKey;
    if (stripeKey.startsWith('pk_')) {
      Stripe.publishableKey = stripeKey;
      Stripe.urlScheme = StripeAppConfig.urlScheme;
      Stripe.merchantIdentifier = Env.stripeApplePayMerchantId;
      await Stripe.instance.applySettings();
    } else {
      debugPrint('[CrunchyPlum] Invalid Stripe key format — '
          'expected pk_test_* or pk_live_*. Stripe disabled.');
    }
  } catch (e) {
    debugPrint('[CrunchyPlum] Stripe init failed: $e — payments disabled');
  }

  // 初始化 deep link 监听（referral link 处理）
  await ReferralLinkService.instance.init();

  // 读取上次地区选择，首次启动默认 Near Me = true
  final prefs = await SharedPreferences.getInstance();
  // 用 location_setup_done 标记真正的「首次」——无论旧版遗留什么值，只要该 key 不存在就强制 Near Me
  final setupDone = prefs.getBool('location_setup_done') ?? false;
  final bool savedIsNearMe;
  if (!setupDone) {
    savedIsNearMe = true;
    await prefs.setBool('location_is_near_me', true);
    await prefs.setBool('location_setup_done', true);
  } else {
    savedIsNearMe = prefs.getBool('location_is_near_me') ?? true;
  }
  final savedCity = prefs.getString('location_city') ?? 'Dallas';
  final savedState = prefs.getString('location_state') ?? 'Texas';
  final savedMetro = prefs.getString('location_metro') ?? 'DFW';

  // 用 ProviderContainer 直接写入 state，确保第一帧就是正确值
  final container = ProviderContainer();
  container.read(isNearMeProvider.notifier).state = savedIsNearMe;
  container.read(selectedLocationProvider.notifier).state = (
    state: savedState,
    metro: savedMetro,
    city: savedCity,
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CrunchyPlumApp(),
    ),
  );
}
