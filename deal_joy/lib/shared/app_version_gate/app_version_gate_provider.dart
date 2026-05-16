import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import 'app_version_gate_evaluator.dart';
import 'app_version_gate_repository.dart';

final appVersionGateRepositoryProvider = Provider<AppVersionGateRepository>((ref) {
  return AppVersionGateRepository(Supabase.instance.client);
});

/// 用户端（consumer）启动时强制更新判定。
final consumerForceUpdateDecisionProvider =
    FutureProvider<ForceUpdateDecision>((ref) async {
  final repo = ref.watch(appVersionGateRepositoryProvider);
  return AppVersionGateEvaluator.evaluate(
    repository: repo,
    appKey: 'consumer',
    fallbackIosStoreUrl: Env.storeUrlIosConsumer,
    fallbackAndroidStoreUrl: Env.storeUrlAndroidConsumer,
  );
});
