// 门店照片网格组件
// 展示已上传照片（支持删除），包含"Add Photo"按钮
// 最多 10 张（storefront 类型限制 1 张）

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../models/store_info.dart';
import '../providers/store_provider.dart';

// ============================================================
// PhotoGrid — 照片网格（ConsumerWidget，读取 storeProvider）
// photoType: 指定展示哪种类型的照片
// ============================================================
class PhotoGrid extends ConsumerWidget {
  const PhotoGrid({
    super.key,
    required this.photoType,
  });

  final StorePhotoType photoType;

  // 各类型照片上限
  int get _maxPhotos => photoType == StorePhotoType.storefront ? 1 : 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(storeProvider);

    return storeAsync.when(
      loading: () => const SizedBox(
        height: 100,
        child: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFFF6B35),
            strokeWidth: 2,
          ),
        ),
      ),
      error: (e, _) => Text(
        'Failed to load photos: $e',
        style: const TextStyle(color: Colors.red, fontSize: 13),
      ),
      data: (store) {
        // 根据类型过滤照片列表
        final photos = switch (photoType) {
          StorePhotoType.storefront => store.storefrontPhoto != null
              ? [store.storefrontPhoto!]
              : <StorePhoto>[],
          StorePhotoType.environment => store.environmentPhotos,
          StorePhotoType.product => store.productPhotos,
        };

        final canAdd = photos.length < _maxPhotos;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 照片类型标题 + 计数
            Row(
              children: [
                Text(
                  photoType.displayLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${photos.length}/$_maxPhotos)',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF999999),
                  ),
                ),
                if (photoType == StorePhotoType.storefront) ...[
                  const SizedBox(width: 4),
                  const Text(
                    '*',
                    style: TextStyle(
                      color: Color(0xFFFF6B35),
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),

            // 照片网格
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                // 已有照片
                ...photos.map(
                  (photo) => _PhotoCell(
                    photo: photo,
                    onDelete: () => _confirmDelete(context, ref, photo),
                  ),
                ),

                // 添加按钮（未达上限时显示）
                if (canAdd)
                  _AddPhotoCell(
                    onTap: () => _pickAndUpload(context, ref, store.id),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  // 弹出删除确认对话框
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    StorePhoto photo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Photo'),
        content: const Text('Are you sure you want to delete this photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(storeProvider.notifier).deletePhoto(photo.id);
    }
  }

  // 从图库选取图片并上传
  Future<void> _pickAndUpload(
    BuildContext context,
    WidgetRef ref,
    String merchantId,
  ) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );

    if (picked == null) return;

    // 计算当前同类型照片数量作为 sortOrder
    final storeAsync = ref.read(storeProvider);
    final currentCount = storeAsync.valueOrNull?.photos
            .where((p) => p.type == photoType)
            .length ??
        0;

    if (!context.mounted) return;

    // 上传时显示加载提示
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text('Uploading photo...'),
          ],
        ),
        duration: Duration(seconds: 10),
        backgroundColor: Color(0xFF333333),
      ),
    );

    try {
      await ref.read(storeProvider.notifier).uploadPhoto(
            merchantId: merchantId,
            file: picked,
            type: photoType,
            sortOrder: currentCount,
          );

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo uploaded successfully'),
            backgroundColor: Color(0xFF4CAF50),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

// ============================================================
// 单张照片格子（显示缩略图 + 右上角删除按钮）
// ============================================================
class _PhotoCell extends StatelessWidget {
  const _PhotoCell({
    required this.photo,
    required this.onDelete,
  });

  final StorePhoto photo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 照片缩略图
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: photo.url,
            width: 88,
            height: 88,
            fit: BoxFit.cover,
            placeholder: (_, _) => Container(
              width: 88,
              height: 88,
              color: const Color(0xFFF0F0F0),
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFF6B35),
                ),
              ),
            ),
            errorWidget: (_, _, _) => Container(
              width: 88,
              height: 88,
              color: const Color(0xFFF0F0F0),
              child: const Icon(
                Icons.broken_image_outlined,
                color: Color(0xFFCCCCCC),
                size: 32,
              ),
            ),
          ),
        ),

        // 右上角删除按钮
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: Color(0xFFFF4444),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 添加照片格子（虚线边框 + 加号图标）
// ============================================================
class _AddPhotoCell extends StatelessWidget {
  const _AddPhotoCell({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFFF6B35),
            width: 1.5,
            // 虚线边框效果通过 CustomPaint 实现（简化版用实线）
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 28,
              color: Color(0xFFFF6B35),
            ),
            SizedBox(height: 4),
            Text(
              'Add',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFFFF6B35),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
