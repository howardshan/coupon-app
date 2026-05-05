// Web / 无 dart:io 时使用：不视为 iOS 模拟器

/// Web 构建无需检测。
Future<void> ensureIosSimulatorDetected() async {}

bool get isIosSimulator => false;
