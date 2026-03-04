import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';

/// 商家详情页顶部图片轮播组件
/// 接收 photoUrls 列表，支持左右滑动翻页
/// 右下角显示当前页码指示器
class StorePhotoCarousel extends StatefulWidget {
  final List<String> photoUrls;

  const StorePhotoCarousel({
    super.key,
    required this.photoUrls,
  });

  @override
  State<StorePhotoCarousel> createState() => _StorePhotoCarouselState();
}

class _StorePhotoCarouselState extends State<StorePhotoCarousel> {
  // 当前页码索引
  int _currentIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 无图片时显示灰色占位
    if (widget.photoUrls.isEmpty) {
      return _buildPlaceholder();
    }

    return SizedBox(
      height: 220,
      child: Stack(
        children: [
          // 图片翻页视图
          PageView.builder(
            controller: _pageController,
            itemCount: widget.photoUrls.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              return CachedNetworkImage(
                imageUrl: widget.photoUrls[index],
                fit: BoxFit.cover,
                width: double.infinity,
                // Shimmer 加载占位
                placeholder: (context, url) => Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Container(
                    width: double.infinity,
                    height: 220,
                    color: Colors.white,
                  ),
                ),
                // 加载失败时显示占位图标
                errorWidget: (context, url, error) => Container(
                  width: double.infinity,
                  height: 220,
                  color: AppColors.surfaceVariant,
                  child: const Icon(
                    Icons.restaurant,
                    size: 64,
                    color: AppColors.textHint,
                  ),
                ),
              );
            },
          ),

          // 右下角页码指示器（如 "1/3"）
          if (widget.photoUrls.length > 1)
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentIndex + 1}/${widget.photoUrls.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 空图片列表时的灰色占位
  Widget _buildPlaceholder() {
    return Container(
      height: 220,
      width: double.infinity,
      color: AppColors.surfaceVariant,
      child: const Icon(
        Icons.restaurant,
        size: 64,
        color: AppColors.textHint,
      ),
    );
  }
}
