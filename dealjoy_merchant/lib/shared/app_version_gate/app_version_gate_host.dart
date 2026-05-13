import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_version_gate_evaluator.dart';
import 'app_version_gate_provider.dart';
import 'force_update_screen.dart';

ThemeData _merchantGateTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF6B35),
      brightness: Brightness.light,
    ),
    useMaterial3: true,
  );
}

/// 在主导航展示前完成版本闸门判定（优先于删号监听等业务首帧逻辑）。
class AppVersionGateHost extends ConsumerWidget {
  const AppVersionGateHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(merchantForceUpdateDecisionProvider);
    final theme = _merchantGateTheme();
    return async.when(
      data: (ForceUpdateDecision d) {
        if (d.mustUpdate) {
          return MaterialApp(
            title: 'Crunchy Plum Merchant',
            theme: theme,
            debugShowCheckedModeBanner: false,
            home: ForceUpdateScreen(decision: d),
          );
        }
        return child;
      },
      loading: () => MaterialApp(
        title: 'Crunchy Plum Merchant',
        theme: theme,
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (Object e, StackTrace st) {
        debugPrint('[AppVersionGateHost] $e\n$st');
        return child;
      },
    );
  }
}
