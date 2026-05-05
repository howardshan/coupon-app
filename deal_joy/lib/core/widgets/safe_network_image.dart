import 'package:cached_network_image/cached_network_image.dart' as cni;
import 'package:flutter/material.dart';

import '../utils/ios_simulator.dart';

/// 统一网络图：真机 / Android 仍用磁盘缓存；**iOS 模拟器**改用 [Image.network]，避免 path_provider FFI 崩溃。
class SafeNetworkImage extends StatelessWidget {
  const SafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.placeholder,
    this.errorWidget,
    this.httpHeaders,
    this.fadeInDuration,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  final Map<String, String>? httpHeaders;
  final Duration? fadeInDuration;
  final int? memCacheWidth;
  final int? memCacheHeight;

  @override
  Widget build(BuildContext context) {
    Widget fallbackError(Object error) {
      return errorWidget?.call(context, imageUrl, error) ??
          const Icon(Icons.broken_image_outlined, size: 48);
    }

    if (isIosSimulator) {
      return Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        headers: httpHeaders,
        cacheWidth: memCacheWidth,
        cacheHeight: memCacheHeight,
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) {
            return child;
          }
          return placeholder?.call(ctx, imageUrl) ??
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
        },
        errorBuilder: (ctx, error, stack) => fallbackError(error),
      );
    }

    return cni.CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      httpHeaders: httpHeaders,
      placeholder: placeholder,
      errorWidget: errorWidget,
      fadeInDuration: fadeInDuration ?? const Duration(milliseconds: 200),
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
    );
  }
}

/// 供 CircleAvatar、DecorationImage 等使用；模拟器上为 [NetworkImage]。
ImageProvider<Object> safeNetworkImageProvider(
  String url, {
  Map<String, String>? headers,
}) {
  if (isIosSimulator) {
    return NetworkImage(url, headers: headers);
  }
  return cni.CachedNetworkImageProvider(url, headers: headers);
}
