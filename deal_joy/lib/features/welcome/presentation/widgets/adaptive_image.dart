import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 自适应网络图片：LayoutBuilder + BoxFit.cover
/// 支持 Supabase Image Transform 按屏幕宽度优化分辨率
class AdaptiveImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;

  const AdaptiveImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return Container(color: Colors.grey.shade200);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final optimizedUrl =
            _getOptimizedUrl(imageUrl, constraints.maxWidth);
        return CachedNetworkImage(
          imageUrl: optimizedUrl,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          fit: fit,
          placeholder: (_, _) => Container(color: Colors.grey.shade100),
          errorWidget: (_, _, _) => Container(
            color: Colors.grey.shade200,
            child:
                Icon(Icons.image_not_supported, color: Colors.grey.shade400),
          ),
        );
      },
    );
  }

  /// Supabase Storage Image Transform：按屏幕宽度请求适配分辨率
  String _getOptimizedUrl(String url, double width) {
    final w = width.ceil();
    if (url.contains('supabase')) {
      // Supabase Storage 支持 ?width=N&quality=N 参数
      final separator = url.contains('?') ? '&' : '?';
      return '$url${separator}width=$w&quality=80';
    }
    return url;
  }
}
