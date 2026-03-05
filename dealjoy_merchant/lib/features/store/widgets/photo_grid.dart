// 门店照片网格组件
// 展示已上传照片（支持删除），包含"Add Photo"按钮
// cover 最多 5 张，storefront 最多 3 张，environment/product 各最多 10 张
// cover 类型支持拖拽排序和封面标记

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
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
  int get _maxPhotos => switch (photoType) {
        StorePhotoType.cover => 5,
        StorePhotoType.storefront => 3,
        StorePhotoType.environment => 10,
        StorePhotoType.product => 10,
      };

  // 缩略图尺寸（匹配客户端裁剪比例）
  ({double w, double h}) get _thumbSize => switch (photoType) {
        StorePhotoType.cover => (w: 140.0, h: 79.0),       // 16:9
        StorePhotoType.storefront => (w: 120.0, h: 68.0),  // 16:9
        StorePhotoType.environment => (w: 104.0, h: 78.0), // 4:3
        StorePhotoType.product => (w: 98.0, h: 70.0),      // 7:5
      };

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
          StorePhotoType.cover => store.coverPhotos,
          StorePhotoType.storefront => store.storefrontPhotos,
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
                if (photoType == StorePhotoType.cover) ...[
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

            // cover 类型使用可拖拽排序的网格
            if (photoType == StorePhotoType.cover)
              _CoverPhotoGrid(
                photos: photos,
                canAdd: canAdd,
                onDelete: (photo) => _confirmDelete(context, ref, photo),
                onSetCover: (photo) => _setCover(ref, photos, photo),
                onReorder: (oldIndex, newIndex) =>
                    _handleReorder(ref, photos, oldIndex, newIndex),
                onAdd: () => _pickAndUpload(context, ref, store.id),
              )
            else
              // 其他类型使用普通 Wrap 布局
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ...photos.map(
                    (photo) => _PhotoCell(
                      photo: photo,
                      width: _thumbSize.w,
                      height: _thumbSize.h,
                      onDelete: () => _confirmDelete(context, ref, photo),
                    ),
                  ),
                  if (canAdd)
                    _AddPhotoCell(
                      width: _thumbSize.w,
                      height: _thumbSize.h,
                      onTap: () => _pickAndUpload(context, ref, store.id),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  // 设为封面（移到首位）
  void _setCover(
    WidgetRef ref,
    List<StorePhoto> photos,
    StorePhoto target,
  ) {
    final ids = photos.map((p) => p.id).toList();
    ids.remove(target.id);
    ids.insert(0, target.id);
    ref.read(storeProvider.notifier).reorderPhotos(ids);
  }

  // 拖拽排序回调
  void _handleReorder(
    WidgetRef ref,
    List<StorePhoto> photos,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < newIndex) newIndex -= 1;
    final ids = photos.map((p) => p.id).toList();
    final id = ids.removeAt(oldIndex);
    ids.insert(newIndex, id);
    ref.read(storeProvider.notifier).reorderPhotos(ids);
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

    // 根据客户端显示框尺寸设定裁剪参数
    final cropConfig = switch (photoType) {
      // cover → 客户端轮播 full width × 220h ≈ 16:9
      StorePhotoType.cover => (
        ratio: const CropAspectRatio(ratioX: 16, ratioY: 9),
        maxW: 1080,
        maxH: 608,
        lock: true,
      ),
      // storefront → 同样用于轮播
      StorePhotoType.storefront => (
        ratio: const CropAspectRatio(ratioX: 16, ratioY: 9),
        maxW: 1080,
        maxH: 608,
        lock: true,
      ),
      // environment → 客户端 200×150 = 4:3
      StorePhotoType.environment => (
        ratio: const CropAspectRatio(ratioX: 4, ratioY: 3),
        maxW: 800,
        maxH: 600,
        lock: true,
      ),
      // product → 客户端 140×100 = 7:5
      StorePhotoType.product => (
        ratio: const CropAspectRatio(ratioX: 7, ratioY: 5),
        maxW: 700,
        maxH: 500,
        lock: true,
      ),
    };

    // 裁剪图片（按客户端显示比例裁剪，支持缩放和移动）
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: cropConfig.ratio,
      compressQuality: 85,
      maxWidth: cropConfig.maxW,
      maxHeight: cropConfig.maxH,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop ${photoType.displayLabel}',
          toolbarColor: const Color(0xFFFF6B35),
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: cropConfig.lock,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Crop ${photoType.displayLabel}',
          aspectRatioLockEnabled: cropConfig.lock,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    if (cropped == null) return;

    // 检查文件大小（不超过 1MB）
    final croppedFile = XFile(cropped.path);
    final fileSize = await croppedFile.length();
    if (fileSize > 1024 * 1024) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo must be under 1 MB'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

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
            file: croppedFile,
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
// Cover 照片可拖拽排序网格
// ============================================================
class _CoverPhotoGrid extends StatelessWidget {
  const _CoverPhotoGrid({
    required this.photos,
    required this.canAdd,
    required this.onDelete,
    required this.onSetCover,
    required this.onReorder,
    required this.onAdd,
  });

  final List<StorePhoto> photos;
  final bool canAdd;
  final void Function(StorePhoto) onDelete;
  final void Function(StorePhoto) onSetCover;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    // 构建所有子项（照片 + 添加按钮）
    final itemCount = photos.length + (canAdd ? 1 : 0);

    // cover 缩略图 16:9
    const double thumbW = 140;
    const double thumbH = 79;

    return SizedBox(
      height: thumbH + 12, // 留出删除按钮空间
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        proxyDecorator: (child, index, animation) {
          return Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: child,
          );
        },
        onReorder: onReorder,
        itemCount: itemCount,
        itemBuilder: (context, index) {
          // 最后一个是添加按钮
          if (index >= photos.length) {
            return Padding(
              key: const ValueKey('add_button'),
              padding: const EdgeInsets.only(right: 10),
              child: _AddPhotoCell(width: thumbW, height: thumbH, onTap: onAdd),
            );
          }

          final photo = photos[index];
          final isCover = index == 0;

          return ReorderableDragStartListener(
            key: ValueKey(photo.id),
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _CoverPhotoCell(
                photo: photo,
                width: thumbW,
                height: thumbH,
                isCover: isCover,
                onDelete: () => onDelete(photo),
                onSetCover: isCover ? null : () => onSetCover(photo),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// Cover 照片格子（缩略图 + 删除 + 封面标记 + 长按菜单）
// ============================================================
class _CoverPhotoCell extends StatelessWidget {
  const _CoverPhotoCell({
    required this.photo,
    required this.width,
    required this.height,
    required this.isCover,
    required this.onDelete,
    this.onSetCover,
  });

  final StorePhoto photo;
  final double width;
  final double height;
  final bool isCover;
  final VoidCallback onDelete;
  final VoidCallback? onSetCover;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _showContextMenu(context),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 照片缩略图
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: photo.url,
              width: width,
              height: height,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: width,
                height: height,
                color: const Color(0xFFF0F0F0),
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFFF6B35),
                  ),
                ),
              ),
              errorWidget: (_, _, _) => Container(
                width: width,
                height: height,
                color: const Color(0xFFF0F0F0),
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: Color(0xFFCCCCCC),
                  size: 32,
                ),
              ),
            ),
          ),

          // 封面标记（左下角）
          if (isCover)
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF6B35),
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(6),
                    bottomLeft: Radius.circular(8),
                  ),
                ),
                child: const Text(
                  'Cover',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
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
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onSetCover != null)
              ListTile(
                leading: const Icon(Icons.star_rounded,
                    color: Color(0xFFFF6B35)),
                title: const Text('Set as Cover'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onSetCover!();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title:
                  const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.of(ctx).pop();
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 单张照片格子（显示缩略图 + 右上角删除按钮）
// ============================================================
class _PhotoCell extends StatelessWidget {
  const _PhotoCell({
    required this.photo,
    required this.width,
    required this.height,
    required this.onDelete,
  });

  final StorePhoto photo;
  final double width;
  final double height;
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
            width: width,
            height: height,
            fit: BoxFit.cover,
            placeholder: (_, _) => Container(
              width: width,
              height: height,
              color: const Color(0xFFF0F0F0),
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFF6B35),
                ),
              ),
            ),
            errorWidget: (_, _, _) => Container(
              width: width,
              height: height,
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
  const _AddPhotoCell({
    required this.width,
    required this.height,
    required this.onTap,
  });

  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFFF6B35),
            width: 1.5,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
