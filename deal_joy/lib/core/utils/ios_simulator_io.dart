import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// 由 [ensureIosSimulatorDetected] 在启动时写入；模拟器上须为 true 才会走 Image.network 分支。
bool? _cachedIsSimulator;

/// 须在 [runApp] 之前 `await`，否则首帧可能仍误判为真机并触发 path_provider FFI 崩溃。
Future<void> ensureIosSimulatorDetected() async {
  if (!Platform.isIOS) {
    _cachedIsSimulator = false;
    return;
  }
  final ios = await DeviceInfoPlugin().iosInfo;
  _cachedIsSimulator = !ios.isPhysicalDevice;
  assert(() {
    debugPrint(
      '[IosSimulator] cached=$_cachedIsSimulator physicalDevice=${ios.isPhysicalDevice}',
    );
    return true;
  }());
}

/// 是否在 iOS 模拟器上运行。
/// Flutter 进程里 [Platform.environment] 往往没有 SIMULATOR_*，不能单独依赖环境变量。
bool get isIosSimulator {
  if (_cachedIsSimulator != null) return _cachedIsSimulator!;
  if (!Platform.isIOS) return false;
  return Platform.environment.containsKey('SIMULATOR_DEVICE_NAME') ||
      Platform.environment.containsKey('SIMULATOR_UDID');
}
