// 地图导航工具：让用户选择 Apple Maps 或 Google Maps 打开导航
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 弹出选择器，让用户选择用 Apple Maps 或 Google Maps 打开导航
/// [address] 目的地地址字符串
Future<void> showMapsChooser(BuildContext context, String address) async {
  if (address.isEmpty) return;
  final encoded = Uri.encodeComponent(address);

  // 显示底部弹窗让用户选择地图应用
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: const Text('Open in Maps'),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () async {
            Navigator.pop(ctx);
            // Apple Maps URL scheme，fallback 使用 HTTPS
            final uri = Uri.parse('maps.apple.com://?q=$encoded');
            final fallback = Uri.parse('https://maps.apple.com/?q=$encoded');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              await launchUrl(fallback, mode: LaunchMode.externalApplication);
            }
          },
          child: const Text('Apple Maps'),
        ),
        CupertinoActionSheetAction(
          onPressed: () async {
            Navigator.pop(ctx);
            final uri = Uri.parse('https://maps.google.com/?q=$encoded');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: const Text('Google Maps'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDestructiveAction: false,
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel'),
      ),
    ),
  );
}
