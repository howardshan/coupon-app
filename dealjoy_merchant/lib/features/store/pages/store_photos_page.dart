// 门店照片管理页面
// 分三个区块展示: Storefront / Environment / Products
// 每个区块使用 PhotoGrid 组件

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/store_info.dart';
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
