import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/env.dart';
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
      await Stripe.instance.applySettings();
    } else {
      debugPrint('[CrunchyPlum] Invalid Stripe key format — '
          'expected pk_test_* or pk_live_*. Stripe disabled.');
    }
  } catch (e) {
    debugPrint('[CrunchyPlum] Stripe init failed: $e — payments disabled');
  }

  runApp(
    const ProviderScope(
      child: CrunchyPlumApp(),
    ),
  );
}
