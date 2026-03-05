import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/merchant_photo_model.dart';
import '../../domain/providers/store_detail_provider.dart';

/// 照片类别筛选标签
enum _PhotoFilter {
  all('All'),
  dishes('Dishes'),
  environment('Environment'),
  other('Other'),
  merchantUploads('Merchant Uploads');

  final String label;
  const _PhotoFilter(this.label);
}

/// 商家相册页
/// 双列网格展示商家所有照片，支持分类筛选 + 全屏浏览
class PhotoGalleryScreen extends ConsumerStatefulWidget {
  final String merchantId;

  const PhotoGalleryScreen({super.key, required this.merchantId});

  @override
  ConsumerState<PhotoGalleryScreen> createState() =>
      _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends ConsumerState<PhotoGalleryScreen> {
  _PhotoFilter _selectedFilter = _PhotoFilter.all;

  @override
  Widget build(BuildContext context) {
    final merchantAsync =
        ref.watch(merchantDetailInfoProvider(widget.merchantId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: merchantAsync.when(
          data: (m) => Text('Photos (${m.photos.length})'),
          loading: () => const Text('Photos'),
          error: (_, _) => const Text('Photos'),
        ),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: merchantAsync.when(
        data: (merchant) => _buildBody(merchant.photos),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Failed to load photos',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ),
    );
  }

  Widget _buildBody(List<MerchantPhotoModel> allPhotos) {
    // 按筛选条件过滤
    final filtered = _filterPhotos(allPhotos);

    return Column(
      children: [
        // 分类筛选标签
        _buildFilterBar(),
        const Divider(height: 1),
        // 照片网格
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library_outlined,
                          size: 48, color: AppColors.textHint),
                      const SizedBox(height: 12),
                      Text('No photos in this category',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(4),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => _PhotoGridItem(
                    photo: filtered[index],
                    onTap: () => _openFullScreen(context, filtered, index),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 48,
      color: AppColors.surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _PhotoFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final filter = _PhotoFilter.values[i];
          final isSelected = _selectedFilter == filter;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.secondary
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
                border: isSelected
                    ? null
                    : Border.all(color: AppColors.surfaceVariant),
              ),
              child: Text(
                filter.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<MerchantPhotoModel> _filterPhotos(List<MerchantPhotoModel> photos) {
    return switch (_selectedFilter) {
      _PhotoFilter.all => photos,
      _PhotoFilter.dishes =>
        photos.where((p) => p.photoType == 'product').toList(),
      _PhotoFilter.environment =>
        photos.where((p) => p.photoType == 'environment').toList(),
      _PhotoFilter.other => photos
          .where((p) =>
              p.photoType != 'product' &&
              p.photoType != 'environment' &&
              p.photoType != 'storefront' &&
              p.photoType != 'cover')
          .toList(),
      _PhotoFilter.merchantUploads => photos, // 所有商家上传的照片
    };
  }

  /// 打开全屏浏览
  void _openFullScreen(
      BuildContext context, List<MerchantPhotoModel> photos, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenViewer(photos: photos, initialIndex: index),
      ),
    );
  }
}

/// 照片网格项
class _PhotoGridItem extends StatelessWidget {
  final MerchantPhotoModel photo;
  final VoidCallback onTap;

  const _PhotoGridItem({required this.photo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: photo.photoUrl,
            fit: BoxFit.cover,
            placeholder: (_, _) => Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: Container(color: Colors.white),
            ),
            errorWidget: (_, _, _) => Container(
              color: AppColors.surfaceVariant,
              child: const Icon(Icons.broken_image,
                  color: AppColors.textHint),
            ),
          ),
          // 左上角来源标签
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _sourceLabel(photo.photoType),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _sourceLabel(String photoType) {
    return switch (photoType) {
      'cover' => 'Cover',
      'storefront' => 'Storefront',
      'environment' => 'Environment',
      'product' => 'Dish',
      _ => 'Photo',
    };
  }
}

/// 全屏图片浏览器
class _FullScreenViewer extends StatefulWidget {
  final List<MerchantPhotoModel> photos;
  final int initialIndex;

  const _FullScreenViewer({
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<_FullScreenViewer> createState() => _FullScreenViewerState();
}

class _FullScreenViewerState extends State<_FullScreenViewer> {
  late int _currentIndex;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.photos.length}',
          style: const TextStyle(fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.photos[i].photoUrl,
              fit: BoxFit.contain,
              placeholder: (_, _) =>
                  const CircularProgressIndicator(color: Colors.white),
              errorWidget: (_, _, _) => const Icon(
                Icons.broken_image,
                color: Colors.white54,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
