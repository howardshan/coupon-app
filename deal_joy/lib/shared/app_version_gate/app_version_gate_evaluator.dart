import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/utils/version_compare.dart';
import 'app_version_gate_repository.dart';
import 'app_version_gate_row.dart';

/// 强制更新判定结果（供 UI 使用）。
class ForceUpdateDecision {
  ForceUpdateDecision._({
    required this.mustUpdate,
    required this.title,
    required this.body,
    required this.storeUri,
  });

  /// 不拦截、正常进入 App。
  factory ForceUpdateDecision.allowed() {
    return ForceUpdateDecision._(
      mustUpdate: false,
      title: '',
      body: '',
      storeUri: Uri(),
    );
  }

  factory ForceUpdateDecision.blocked({
    required String title,
    required String body,
    required Uri storeUri,
  }) {
    return ForceUpdateDecision._(
      mustUpdate: true,
      title: title,
      body: body,
      storeUri: storeUri,
    );
  }

  final bool mustUpdate;
  final String title;
  final String body;
  final Uri storeUri;
}

class AppVersionGateEvaluator {
  AppVersionGateEvaluator._();

  static Future<ForceUpdateDecision> evaluate({
    required AppVersionGateRepository repository,
    required String appKey,
    required String fallbackIosStoreUrl,
    required String fallbackAndroidStoreUrl,
  }) async {
    final AppVersionGateRow? row = await repository.fetchRow(appKey);
    if (row == null) return ForceUpdateDecision.allowed();

    if (!row.forceUpdateEnabled) return ForceUpdateDecision.allowed();

    final info = await PackageInfo.fromPlatform();
    final current = info.version.trim();
    final min = row.minSupportedVersion.trim();
    if (compareSemver(current, min) >= 0) {
      return ForceUpdateDecision.allowed();
    }

    final uri = _resolveStoreUri(
      row: row,
      fallbackIos: fallbackIosStoreUrl,
      fallbackAndroid: fallbackAndroidStoreUrl,
    );
    if (uri == null || !uri.hasScheme) {
      debugPrint('[AppVersionGate] no valid store URL, skip block');
      return ForceUpdateDecision.allowed();
    }

    final title = (row.messageTitle?.trim().isNotEmpty ?? false)
        ? row.messageTitle!.trim()
        : 'Update required';
    final body = (row.messageBody?.trim().isNotEmpty ?? false)
        ? row.messageBody!.trim()
        : 'Please update Crunchy Plum to continue.';

    return ForceUpdateDecision.blocked(title: title, body: body, storeUri: uri);
  }

  static Uri? _resolveStoreUri({
    required AppVersionGateRow row,
    required String fallbackIos,
    required String fallbackAndroid,
  }) {
    String? pick;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        pick = _nonEmpty(row.iosStoreUrl) ?? _nonEmpty(fallbackIos);
        break;
      case TargetPlatform.android:
        pick = _nonEmpty(row.androidStoreUrl) ??
            _nonEmpty(fallbackAndroid);
        break;
      default:
        pick = _nonEmpty(row.iosStoreUrl) ??
            _nonEmpty(fallbackIos) ??
            _nonEmpty(row.androidStoreUrl) ??
            _nonEmpty(fallbackAndroid);
    }
    if (pick == null) return null;
    return Uri.tryParse(pick);
  }

  static String? _nonEmpty(String? s) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }
}
