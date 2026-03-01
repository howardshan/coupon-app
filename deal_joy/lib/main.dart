import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/env.dart';
import 'app.dart';

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
    debugPrint('[DealJoy] Supabase init failed: $e');
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

  // Initialize Stripe (non-blocking — app works without it)
  try {
    final stripeKey = Env.stripePublishableKey;
    if (stripeKey.startsWith('pk_')) {
      Stripe.publishableKey = stripeKey;
      await Stripe.instance.applySettings();
    } else {
      debugPrint('[DealJoy] Invalid Stripe key format — '
          'expected pk_test_* or pk_live_*. Stripe disabled.');
    }
  } catch (e) {
    debugPrint('[DealJoy] Stripe init failed: $e — payments disabled');
  }

  runApp(
    const ProviderScope(
      child: DealJoyApp(),
    ),
  );
}
