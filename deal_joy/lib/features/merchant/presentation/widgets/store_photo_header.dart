import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/merchant_detail_model.dart';

/// 商家详情页顶部图片组件
/// 支持两种模式：single（轮播）和 triple（三图并排）
class StorePhotoHeader extends StatefulWidget {
  final MerchantDetailModel merchant;
  final VoidCallback? onPhotosPressed;

  const StorePhotoHeader({
    super.key,
    required this.merchant,
    this.onPhotosPressed,
  });

  @override
  State<StorePhotoHeader> createState() => _StorePhotoHeaderState();
}

class _StorePhotoHeaderState extends State<StorePhotoHeader> {
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
    if (widget.merchant.useTripleHeader) {
      return _buildTripleHeader();
    }
    return _buildSingleHeader();
  }

  /// Single 模式：PageView 轮播
  Widget _buildSingleHeader() {
    final urls = widget.merchant.allPhotoUrls;
    if (urls.isEmpty) return _buildPlaceholder(250);

    return SizedBox(
      height: 250,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (context, index) => GestureDetector(
              onTap: widget.onPhotosPressed,
              child: _buildImage(urls[index], 250),
            ),
          ),
          // 右下角页码 + Photos 按钮
          Positioned(
            right: 12,
            bottom: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (urls.length > 1)
                  _buildBadge('${_currentIndex + 1}/${urls.length}'),
                const SizedBox(width: 8),
                _buildPhotosButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Triple 模式：三张图横向并排
  Widget _buildTripleHeader() {
    final photos = widget.merchant.headerPhotos;

    return SizedBox(
      height: 200,
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: widget.onPhotosPressed,
                  child: _buildImage(photos[0], 200),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: GestureDetector(
                  onTap: widget.onPhotosPressed,
                  child: _buildImage(photos[1], 200),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: GestureDetector(
                  onTap: widget.onPhotosPressed,
                  child: _buildImage(photos[2], 200),
                ),
              ),
            ],
          ),
          // 右下角 Photos 按钮
          Positioned(
            right: 12,
            bottom: 12,
            child: _buildPhotosButton(),
          ),
        ],
      ),
    );
  }

  /// 加载网络图片（带 shimmer 占位）
  Widget _buildImage(String url, double height) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: height,
      placeholder: (_, __) => Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(
          width: double.infinity,
          height: height,
          color: Colors.white,
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        width: double.infinity,
        height: height,
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.restaurant, size: 48, color: AppColors.textHint),
      ),
    );
  }

  /// 半透明角标（页码等）
  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// "Photos >" 按钮
  Widget _buildPhotosButton() {
    return GestureDetector(
      onTap: widget.onPhotosPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined, size: 14, color: Colors.white),
            SizedBox(width: 4),
            Text(
              'Photos',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 14, color: Colors.white),
          ],
        ),
      ),
    );
  }

  /// 空图片占位
  Widget _buildPlaceholder(double height) {
    return Container(
      height: height,
      width: double.infinity,
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.restaurant, size: 64, color: AppColors.textHint),
    );
  }
}
