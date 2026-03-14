import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/merchant_photo_model.dart';
import '../../domain/providers/store_detail_provider.dart';

/// 照片类别筛选标签
enum _PhotoFilter {
  all('All'),
  products('Products'),
  environment('Environment'),
  other('Other'),
  merchantUploads('Merchant Uploads');

  final String label;
  const _PhotoFilter(this.label);
}

/// 统一的图片展示项（可来自 merchant_photos 或 menu_items）
class _DisplayPhoto {
  final String url;
  final String sourceLabel; // 左上角标签
  final String? productName; // 产品名称（仅 menu_items 来源有值）
  final double? price; // 产品价格

  const _DisplayPhoto({
    required this.url,
    required this.sourceLabel,
    this.productName,
    this.price,
  });
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

  // 缓存 menu_items 产品图片
  List<_DisplayPhoto>? _productPhotos;
  bool _loadingProducts = false;

  @override
  void initState() {
    super.initState();
    _loadProductPhotos();
  }

  /// 从 menu_items 表加载有图片的产品
  Future<void> _loadProductPhotos() async {
    setState(() => _loadingProducts = true);
    try {
      final data = await Supabase.instance.client
          .from('menu_items')
          .select('name, image_url, price')
          .eq('merchant_id', widget.merchantId)
          .not('image_url', 'is', null)
          .neq('image_url', '');

      _productPhotos = (data as List)
          .map((row) => _DisplayPhoto(
                url: row['image_url'] as String,
                sourceLabel: 'Product',
                productName: row['name'] as String? ?? '',
                price: (row['price'] as num?)?.toDouble(),
              ))
          .toList();
    } catch (_) {
      _productPhotos = [];
    }
    if (mounted) setState(() => _loadingProducts = false);
  }

  @override
  Widget build(BuildContext context) {
    final merchantAsync =
        ref.watch(merchantDetailInfoProvider(widget.merchantId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: merchantAsync.when(
          data: (m) {
            final total = m.photos.length + (_productPhotos?.length ?? 0);
            return Text('Photos ($total)');
          },
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

  /// 将 merchant_photos 转为统一的 _DisplayPhoto
  List<_DisplayPhoto> _merchantPhotosToDisplay(List<MerchantPhotoModel> photos) {
    return photos
        .map((p) => _DisplayPhoto(
              url: p.photoUrl,
              sourceLabel: _sourceLabel(p.photoType),
            ))
        .toList();
  }

  Widget _buildBody(List<MerchantPhotoModel> allPhotos) {
    final filtered = _getFilteredPhotos(allPhotos);
    final isLoading = _loadingProducts &&
        (_selectedFilter == _PhotoFilter.products ||
            _selectedFilter == _PhotoFilter.all);

    return Column(
      children: [
        // 分类筛选标签
        _buildFilterBar(),
        const Divider(height: 1),
        // 照片网格
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_library_outlined,
                              size: 48, color: AppColors.textHint),
                          const SizedBox(height: 12),
                          Text('No photos in this category',
                              style:
                                  TextStyle(color: AppColors.textSecondary)),
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
                        onTap: () =>
                            _openFullScreen(context, filtered, index),
                      ),
                    ),
        ),
      ],
    );
  }

  /// 获取当前筛选条件下的照片列表
  List<_DisplayPhoto> _getFilteredPhotos(List<MerchantPhotoModel> photos) {
    final products = _productPhotos ?? [];

    return switch (_selectedFilter) {
      _PhotoFilter.all => [
          ..._merchantPhotosToDisplay(photos),
          ...products,
        ],
      _PhotoFilter.products => products,
      _PhotoFilter.environment => _merchantPhotosToDisplay(
          photos.where((p) => p.photoType == 'environment').toList()),
      _PhotoFilter.other => _merchantPhotosToDisplay(photos
          .where((p) =>
              p.photoType != 'product' &&
              p.photoType != 'environment' &&
              p.photoType != 'storefront' &&
              p.photoType != 'cover')
          .toList()),
      _PhotoFilter.merchantUploads => _merchantPhotosToDisplay(photos),
    };
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

  String _sourceLabel(String photoType) {
    return switch (photoType) {
      'cover' => 'Cover',
      'storefront' => 'Storefront',
      'environment' => 'Environment',
      'product' => 'Product',
      _ => 'Photo',
    };
  }

  /// 打开全屏浏览
  void _openFullScreen(
      BuildContext context, List<_DisplayPhoto> photos, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _FullScreenViewer(photos: photos, initialIndex: index),
      ),
    );
  }
}

/// 照片网格项（支持产品名称叠加显示）
class _PhotoGridItem extends StatelessWidget {
  final _DisplayPhoto photo;
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
            imageUrl: photo.url,
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
                photo.sourceLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
              ),
            ),
          ),
          // 底部产品名称 + 价格（仅 menu_items 来源显示）
          if (photo.productName != null && photo.productName!.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        photo.productName!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (photo.price != null)
                      Text(
                        '\$${photo.price!.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 全屏图片浏览器
class _FullScreenViewer extends StatefulWidget {
  final List<_DisplayPhoto> photos;
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
    final photo = widget.photos[_currentIndex];
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
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) => InteractiveViewer(
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: widget.photos[i].url,
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
          // 底部产品名称（全屏模式也显示）
          if (photo.productName != null && photo.productName!.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        photo.productName!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (photo.price != null)
                      Text(
                        '\$${photo.price!.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
