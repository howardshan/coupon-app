import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_version_gate_evaluator.dart';
import 'app_version_gate_repository.dart';

final appVersionGateRepositoryProvider = Provider<AppVersionGateRepository>((ref) {
  return AppVersionGateRepository(Supabase.instance.client);
});

/// 商家端（merchant）启动时强制更新判定。
final merchantForceUpdateDecisionProvider =
    FutureProvider<ForceUpdateDecision>((ref) async {
  final repo = ref.watch(appVersionGateRepositoryProvider);
  return AppVersionGateEvaluator.evaluate(
    repository: repo,
    appKey: 'merchant',
    fallbackIosStoreUrl:
        dotenv.env['STORE_URL_IOS_MERCHANT'] ?? dotenv.env['STORE_URL_IOS'] ?? '',
    fallbackAndroidStoreUrl: dotenv.env['STORE_URL_ANDROID_MERCHANT'] ??
        dotenv.env['STORE_URL_ANDROID'] ??
        '',
  );
});
