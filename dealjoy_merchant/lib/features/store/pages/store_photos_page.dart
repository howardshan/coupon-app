// 门店照片管理页面
// 分三个区块展示: Storefront / Environment / Products
// 每个区块使用 PhotoGrid 组件

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../../menu/providers/menu_provider.dart';
import '../models/store_info.dart';
import '../providers/store_provider.dart';
import '../widgets/header_style_selector.dart';
import '../widgets/photo_grid.dart';

// ============================================================
// StorePhotosPage — 照片管理页（ConsumerWidget）
// ============================================================
class StorePhotosPage extends ConsumerWidget {
  const StorePhotosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: const Color(0xFF333333),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Store Photos',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 说明文字
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8F5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFDDCC)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFFFF6B35),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cover photos are displayed on your store page carousel (5 max, first is the main cover). Storefront photos show your store exterior (3 max).',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFFF6B35),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 头图模式选择器（客户端店铺详情页头图展示方式）
            _PhotoSection(
              title: 'Header Display Style',
              subtitle: 'How your store page header looks to customers',
              child: const HeaderStyleSelector(),
            ),
            const SizedBox(height: 16),

            // 首页封面图区块（单张，用于客户端首页 deal 卡片）
            _PhotoSection(
              title: 'Homepage Cover',
              subtitle: 'Displayed on deal cards in customer app',
              required: true,
              child: const _HomepageCoverUploader(),
            ),
            const SizedBox(height: 16),

            // 封面照区块
            _PhotoSection(
              title: 'Cover Photos',
              subtitle: 'Up to 5 · First is main cover · Drag to reorder',
              required: true,
              child: const PhotoGrid(photoType: StorePhotoType.cover),
            ),
            const SizedBox(height: 16),

            // 门头照区块
            _PhotoSection(
              title: 'Storefront Photos',
              subtitle: 'Up to 3 photos',
              child: const PhotoGrid(photoType: StorePhotoType.storefront),
            ),
            const SizedBox(height: 16),

            // 环境照区块
            _PhotoSection(
              title: 'Environment Photos',
              subtitle: 'Up to 10 photos',
              child: const PhotoGrid(photoType: StorePhotoType.environment),
            ),
            const SizedBox(height: 16),

            // 菜品照区块
            _PhotoSection(
              title: 'Product Photos',
              subtitle: 'Up to 10 photos',
              child: const PhotoGrid(photoType: StorePhotoType.product),
            ),
            const SizedBox(height: 16),

            // 菜单产品图片（自动从 menu 读取，只读展示）
            _PhotoSection(
              title: 'Menu Item Photos',
              subtitle: 'Auto-synced from your menu',
              child: const _MenuItemPhotos(),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 照片区块卡片（标题 + 副标题 + 内容）
// ============================================================
class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.title,
    required this.subtitle,
    required this.child,
    this.required = false,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        if (required) ...[
                          const SizedBox(width: 4),
                          const Text(
                            '*',
                            style: TextStyle(
                              color: Color(0xFFFF6B35),
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF999999),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ============================================================
// 首页封面图上传组件（单张）
// ============================================================
class _HomepageCoverUploader extends ConsumerStatefulWidget {
  const _HomepageCoverUploader();

  @override
  ConsumerState<_HomepageCoverUploader> createState() =>
      _HomepageCoverUploaderState();
}

class _HomepageCoverUploaderState
    extends ConsumerState<_HomepageCoverUploader> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final store = ref.read(storeProvider).valueOrNull;
    if (store == null) return;

    // 1. 选择图片
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked == null) return;

    // 2. 裁剪图片（固定 5:7 比例，匹配客户端商家卡片）
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 5, ratioY: 7),
      compressQuality: 85,
      maxWidth: 800,
      maxHeight: 1120,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Cover Photo',
          toolbarColor: const Color(0xFFFF6B35),
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Crop Cover Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    if (cropped == null) return;

    // 3. 检查文件大小（不超过 1MB）
    final croppedFile = XFile(cropped.path);
    final fileSize = await croppedFile.length();
    if (fileSize > 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo must be under 1 MB'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // 4. 上传裁剪后的图片
    setState(() => _uploading = true);
    try {
      await ref.read(storeProvider.notifier).uploadHomepageCover(
            merchantId: store.id,
            file: croppedFile,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Homepage Cover?'),
        content: const Text('This will remove the cover image from all your deal cards.'),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => ctx.pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(storeProvider.notifier).deleteHomepageCover();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider).valueOrNull;
    final url = store?.homepageCoverUrl;
    final hasImage = url != null && url.isNotEmpty;

    if (_uploading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (hasImage) {
      // 已有图片 → 显示缩略图 + 替换/删除按钮
      return Column(
        children: [
          // 5:7 比例匹配客户端商家卡片
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 5 / 7,
              child: CachedNetworkImage(
                imageUrl: url,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: const Color(0xFFF0F0F0),
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: const Color(0xFFF0F0F0),
                  child: const Icon(Icons.broken_image, size: 40, color: Colors.grey),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickAndUpload,
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Replace'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _confirmDelete,
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // 无图片 → 显示上传按钮
    return GestureDetector(
      onTap: _pickAndUpload,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFCCCCCC), style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(8),
          color: const Color(0xFFFAFAFA),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_photo_alternate_outlined, size: 36, color: Color(0xFF999999)),
              SizedBox(height: 6),
              Text(
                'Add Homepage Cover',
                style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 菜单产品图片展示（只读，从 menuProvider 自动同步）
// ============================================================
class _MenuItemPhotos extends ConsumerWidget {
  const _MenuItemPhotos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuAsync = ref.watch(menuProvider);

    return menuAsync.when(
      loading: () => const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => const Text(
        'Failed to load menu photos',
        style: TextStyle(color: Colors.red, fontSize: 13),
      ),
      data: (items) {
        // 只显示有图片的菜品
        final withPhotos = items.where((i) => i.imageUrl != null && i.imageUrl!.isNotEmpty).toList();

        if (withPhotos.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No menu items with photos yet. Add photos in Menu Management.',
              style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
            ),
          );
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: withPhotos.map((item) => _MenuPhotoCell(item: item)).toList(),
        );
      },
    );
  }
}

// ============================================================
// 单个菜单产品图片格子（只读，显示名称标签）
// ============================================================
class _MenuPhotoCell extends StatelessWidget {
  const _MenuPhotoCell({required this.item});

  final dynamic item; // MenuItem

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 7:5 比例匹配客户端菜品卡片
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: item.imageUrl!,
            width: 98,
            height: 70,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 98,
              height: 70,
              color: const Color(0xFFF0F0F0),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF6B35)),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              width: 98,
              height: 70,
              color: const Color(0xFFF0F0F0),
              child: const Icon(Icons.broken_image_outlined, color: Color(0xFFCCCCCC), size: 32),
            ),
          ),
        ),
        // 菜品名称标签（底部）
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
            ),
            child: Text(
              item.name,
              style: const TextStyle(color: Colors.white, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}
