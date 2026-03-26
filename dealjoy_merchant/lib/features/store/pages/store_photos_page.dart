// 门店照片管理页面（简化版）
// 三个区块: Store Photos / Environment / Products
// Store Photos 合并了原 Homepage Cover + Cover + Storefront，第一张自动作为首页封面

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../menu/providers/menu_provider.dart';
import '../models/store_info.dart';
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
                      'Store photos are displayed on your store page carousel. The first photo is also used as your homepage cover on deal cards. Drag to reorder.',
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

            // 头图模式选择器
            _PhotoSection(
              title: 'Header Display Style',
              subtitle: 'How your store page header looks to customers',
              child: const HeaderStyleSelector(),
            ),
            const SizedBox(height: 16),

            // Store Photos（合并了 Cover + Storefront + Homepage Cover）
            _PhotoSection(
              title: 'Store Photos',
              subtitle: 'Up to 8 · First photo = homepage cover · Drag to reorder',
              required: true,
              child: const PhotoGrid(photoType: StorePhotoType.cover),
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
