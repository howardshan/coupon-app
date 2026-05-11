import 'package:deal_joy/core/widgets/safe_network_image.dart';
import 'package:flutter/material.dart';

/// 自适应网络图片：LayoutBuilder + 默认可用 BoxFit.cover
/// 支持 Supabase Image Transform 按屏幕宽度优化分辨率
class AdaptiveImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;

  /// 为 Onboarding 等场景使用更明显的加载占位，避免弱网下长时间像「白屏」
  final bool useProminentPlaceholder;

  const AdaptiveImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.useProminentPlaceholder = false,
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
        final placeholder = useProminentPlaceholder
            ? (BuildContext _, String _) => ColoredBox(
                  color: Colors.grey.shade300,
                  child: Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                )
            : (BuildContext _, String _) =>
                Container(color: Colors.grey.shade100);
        return SafeNetworkImage(
          imageUrl: optimizedUrl,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          fit: fit,
          placeholder: placeholder,
          errorWidget: (_, _, _) => Container(
            color: Colors.grey.shade200,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image_not_supported, color: Colors.grey.shade500),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Image unavailable',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Supabase Storage Image Transform：按屏幕宽度请求适配分辨率
  String _getOptimizedUrl(String url, double width) {
    // 首帧或未布局完成时 maxWidth 可能为 0，避免 width=0 触发异常或无效请求
    final safeW = (!width.isFinite || width <= 0) ? 800 : width.ceil();
    final w = safeW.clamp(1, 4096);
    if (url.contains('supabase')) {
      // Supabase Storage 支持 ?width=N&quality=N 参数
      final separator = url.contains('?') ? '&' : '?';
      return '$url${separator}width=$w&quality=80';
    }
    return url;
  }
}
