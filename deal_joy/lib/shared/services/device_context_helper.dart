// 合规审计：采集设备上下文信息
// 用于写入 legal_audit_log 的 device_info / app_version / user_agent / platform 字段
// 首次采集后缓存到内存，避免每次 RPC 调用都查询平台 API

import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 合规审计用的设备上下文快照
class LegalDeviceContext {
  final String? deviceInfo;
  final String? appVersion;
  final String? userAgent;
  final String platform; // ios / android / web / other

  const LegalDeviceContext({
    required this.deviceInfo,
    required this.appVersion,
    required this.userAgent,
    required this.platform,
  });
}

/// 设备上下文单例采集器（懒加载 + 内存缓存）
class DeviceContextHelper {
  static LegalDeviceContext? _cached;

  /// 获取设备上下文。首次调用会读取平台 API，后续直接返回缓存
  static Future<LegalDeviceContext> get() async {
    if (_cached != null) return _cached!;

    final pkgInfo = await PackageInfo.fromPlatform();
    final appVersion = '${pkgInfo.version}+${pkgInfo.buildNumber}';

    String? deviceInfo;
    String platform = 'other';

    try {
      if (kIsWeb) {
        platform = 'web';
        final web = await DeviceInfoPlugin().webBrowserInfo;
        deviceInfo = '${web.browserName.name} ${web.platform ?? ''}'.trim();
      } else if (Platform.isIOS) {
        platform = 'ios';
        final ios = await DeviceInfoPlugin().iosInfo;
        deviceInfo = '${ios.model} iOS ${ios.systemVersion}';
      } else if (Platform.isAndroid) {
        platform = 'android';
        final and = await DeviceInfoPlugin().androidInfo;
        deviceInfo = '${and.manufacturer} ${and.model} Android ${and.version.release}';
      }
    } catch (e) {
      // 采集失败不阻塞业务流程，留空即可
      debugPrint('[DeviceContextHelper] 采集设备信息失败: $e');
    }

    // 拼装 user_agent：DealJoy/1.0.0+1 Android 14 Pixel 6
    final userAgent = deviceInfo != null
        ? '${pkgInfo.appName}/$appVersion $deviceInfo'
        : '${pkgInfo.appName}/$appVersion';

    _cached = LegalDeviceContext(
      deviceInfo: deviceInfo,
      appVersion: appVersion,
      userAgent: userAgent,
      platform: platform,
    );
    return _cached!;
  }
}
