import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// Disables the Material 3 "stretch" overscroll effect on Android,
/// which distorts images and text when scrolling past the edge.
class _NoStretchScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class DealJoyApp extends ConsumerWidget {
  const DealJoyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'DealJoy',
      theme: AppTheme.light,
      routerConfig: router,
      scrollBehavior: _NoStretchScrollBehavior(),
      debugShowCheckedModeBanner: false,
    );
  }
}
