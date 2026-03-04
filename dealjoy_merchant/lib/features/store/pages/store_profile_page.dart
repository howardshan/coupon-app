// 门店信息主页面（只读展示，各区块右上角有 Edit 按钮）
// 分段展示: 基本信息 / 门店照片 / 营业时间 / 标签

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/store_info.dart';
import '../providers/store_provider.dart';
import '../widgets/photo_grid.dart';
import '../widgets/tag_chip_list.dart';

// ============================================================
// StoreProfilePage — 门店信息总览页（ConsumerWidget）
// 挂载在底部导航 "Me" Tab 的子页面
// ============================================================
class StoreProfilePage extends ConsumerWidget {
  const StoreProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(storeProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Store Profile',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        actions: [
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF666666)),
            onPressed: () => ref.read(storeProvider.notifier).refresh(),
          ),
        ],
      ),
      body: storeAsync.when(
        loading: () => const _LoadingView(),
        error: (e, _) => _ErrorView(error: e.toString(), onRetry: () {
          ref.read(storeProvider.notifier).refresh();
        }),
        data: (store) => RefreshIndicator(
          color: const Color(0xFFFF6B35),
          onRefresh: () => ref.read(storeProvider.notifier).refresh(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 门店状态横幅（审核中 / 已下线时显示）
                if (store.status != 'approved') ...[
                  _StatusBanner(status: store.status),
                  const SizedBox(height: 12),
                ],

                // 区块 1: 基本信息
                _SectionCard(
                  title: 'Basic Info',
                  onEdit: () => context.push('/store/edit'),
                  child: _BasicInfoContent(store: store),
                ),
                const SizedBox(height: 12),

                // 区块 2: 门店照片
                _SectionCard(
                  title: 'Store Photos',
                  onEdit: () => context.push('/store/photos'),
                  child: _PhotosContent(store: store),
                ),
                const SizedBox(height: 12),

                // 区块 3: 营业时间
                _SectionCard(
                  title: 'Business Hours',
                  onEdit: () => context.push('/store/hours'),
                  child: _HoursContent(hours: store.hours),
                ),
                const SizedBox(height: 12),

                // 区块 4: 类别和标签
                _SectionCard(
                  title: 'Category & Tags',
                  onEdit: () => context.push('/store/tags'),
                  child: _TagsContent(store: store),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 通用区块卡片（带标题 + 右上角 Edit 按钮）
// ============================================================
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.onEdit,
    required this.child,
  });

  final String title;
  final VoidCallback onEdit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          // 区块标题行
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                TextButton(
                  onPressed: onEdit,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6B35),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Edit',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 基本信息内容区
// ============================================================
class _BasicInfoContent extends StatelessWidget {
  const _BasicInfoContent({required this.store});

  final StoreInfo store;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoRow(label: 'Store Name', value: store.name),
        const SizedBox(height: 10),
        _InfoRow(
          label: 'Description',
          value: store.description?.isNotEmpty == true
              ? store.description!
              : 'No description yet',
          isGrayed: store.description?.isEmpty != false,
        ),
        const SizedBox(height: 10),
        _InfoRow(
          label: 'Phone',
          value: store.phone?.isNotEmpty == true ? store.phone! : 'Not set',
          isGrayed: store.phone?.isEmpty != false,
        ),
        const SizedBox(height: 10),
        _InfoRow(
          label: 'Address',
          value: store.address?.isNotEmpty == true ? store.address! : 'Not set',
          isGrayed: store.address?.isEmpty != false,
        ),
      ],
    );
  }
}

// ============================================================
// 单行信息展示（标签 + 值）
// ============================================================
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.isGrayed = false,
  });

  final String label;
  final String value;
  final bool isGrayed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF999999),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: isGrayed ? const Color(0xFFBBBBBB) : const Color(0xFF333333),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 照片内容区（只读缩略图预览）
// ============================================================
class _PhotosContent extends StatelessWidget {
  const _PhotosContent({required this.store});

  final StoreInfo store;

  @override
  Widget build(BuildContext context) {
    final storefrontPhoto = store.storefrontPhoto;
    final envCount = store.environmentPhotos.length;
    final productCount = store.productPhotos.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 门头照预览
        Row(
          children: [
            _PhotoTypePreview(
              label: 'Storefront',
              photo: storefrontPhoto,
              isRequired: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 环境照和菜品照计数
        Row(
          children: [
            _PhotoCountBadge(
              label: 'Environment',
              count: envCount,
              max: 10,
            ),
            const SizedBox(width: 12),
            _PhotoCountBadge(
              label: 'Products',
              count: productCount,
              max: 10,
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================
// 照片类型预览（门头照）
// ============================================================
class _PhotoTypePreview extends StatelessWidget {
  const _PhotoTypePreview({
    required this.label,
    required this.photo,
    this.isRequired = false,
  });

  final String label;
  final StorePhoto? photo;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 缩略图
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: photo != null
              ? Image.network(
                  photo!.url,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _PhotoPlaceholder(size: 64),
                )
              : _PhotoPlaceholder(size: 64),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF333333),
                  ),
                ),
                if (isRequired) ...[
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
            Text(
              photo != null ? 'Uploaded' : 'Not uploaded',
              style: TextStyle(
                fontSize: 12,
                color: photo != null
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFFF6B35),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================
// 照片数量徽章
// ============================================================
class _PhotoCountBadge extends StatelessWidget {
  const _PhotoCountBadge({
    required this.label,
    required this.count,
    required this.max,
  });

  final String label;
  final int count;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        children: [
          Text(
            '$count/$max',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF333333),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 照片占位符
// ============================================================
class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.image_outlined,
        color: Color(0xFFCCCCCC),
        size: 28,
      ),
    );
  }
}

// ============================================================
// 营业时间内容区（7 天列表）
// ============================================================
class _HoursContent extends StatelessWidget {
  const _HoursContent({required this.hours});

  final List<BusinessHours> hours;

  @override
  Widget build(BuildContext context) {
    if (hours.isEmpty) {
      return const Text(
        'No business hours configured',
        style: TextStyle(fontSize: 14, color: Color(0xFFBBBBBB)),
      );
    }

    // 按 day_of_week 排序（0-6）
    final sortedHours = [...hours]
      ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));

    return Column(
      children: sortedHours.map((h) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              // 星期名称（固定宽度对齐）
              SizedBox(
                width: 100,
                child: Text(
                  BusinessHours.dayName(h.dayOfWeek),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF555555),
                  ),
                ),
              ),
              // 营业时间
              Text(
                h.displayText,
                style: TextStyle(
                  fontSize: 13,
                  color: h.isClosed
                      ? const Color(0xFFBBBBBB)
                      : const Color(0xFF333333),
                  fontWeight:
                      h.isClosed ? FontWeight.w400 : FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ============================================================
// 标签内容区
// ============================================================
class _TagsContent extends StatelessWidget {
  const _TagsContent({required this.store});

  final StoreInfo store;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 类别（只读）
        if (store.category != null) ...[
          const Text(
            'Category',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF999999),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3EE),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFCCB3)),
            ),
            child: Text(
              store.category!,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFFF6B35),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // 标签（只读展示）
        const Text(
          'Tags',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF999999),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        store.tags.isEmpty
            ? const Text(
                'No tags added yet',
                style: TextStyle(fontSize: 14, color: Color(0xFFBBBBBB)),
              )
            : TagChipList(
                tags: store.tags,
                readOnly: true,
              ),
      ],
    );
  }
}

// ============================================================
// 审核状态横幅（pending / rejected）
// ============================================================
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final isPending = status == 'pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isPending
            ? const Color(0xFFFFF8E1)
            : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPending
              ? const Color(0xFFFFCC02)
              : const Color(0xFFEF9A9A),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPending
                ? Icons.hourglass_top_rounded
                : Icons.warning_amber_rounded,
            color: isPending
                ? const Color(0xFFF9A825)
                : const Color(0xFFE53935),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isPending
                  ? 'Your store is under review. Changes will be visible after approval.'
                  : 'Your application was rejected. Please update and resubmit.',
              style: TextStyle(
                fontSize: 13,
                color: isPending
                    ? const Color(0xFFF9A825)
                    : const Color(0xFFE53935),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 加载骨架屏
// ============================================================
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          4,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 错误视图（带重试按钮）
// ============================================================
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: Color(0xFFCCCCCC),
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to load store info',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
