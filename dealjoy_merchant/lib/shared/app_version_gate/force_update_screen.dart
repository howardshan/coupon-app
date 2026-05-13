import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import 'app_version_gate_evaluator.dart';

/// 全屏强制更新页：与用户端 Crunchy Plum 强制更新页视觉对齐。
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key, required this.decision});

  final ForceUpdateDecision decision;

  Future<void> _openStore() async {
    final uri = decision.storeUri;
    if (!uri.hasScheme) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),
                Icon(
                  Icons.system_update,
                  size: 64,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  decision.title,
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  decision.body,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _openStore,
                  child: Text(
                    defaultTargetPlatform == TargetPlatform.iOS
                        ? 'Update in App Store'
                        : 'Update in Play Store',
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
