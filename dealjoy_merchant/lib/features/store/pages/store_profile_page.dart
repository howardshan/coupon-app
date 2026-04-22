// 门店信息主页面（只读展示，各区块右上角有 Edit 按钮）
// 分段展示: 门头照横幅 / 基本信息 / 专业资料 / 门店照片 / 营业时间 / 标签

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/store_facility_model.dart';
import '../models/store_info.dart';
import '../providers/facilities_provider.dart';
import '../providers/store_provider.dart';
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
      body: storeAsync.when(
        loading: () => const _LoadingView(),
        error: (e, _) => _ErrorView(error: e.toString(), onRetry: () {
          ref.read(storeProvider.notifier).refresh();
        }),
        data: (store) => RefreshIndicator(
          color: const Color(0xFFFF6B35),
          onRefresh: () => ref.read(storeProvider.notifier).refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 门头照 + 店名 SliverAppBar
              _StorefrontHeader(store: store),

              // 内容区
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // 审核状态横幅
                    if (store.status != 'approved') ...[
                      _StatusBanner(status: store.status),
                      const SizedBox(height: 12),
                    ],

                    // 修改需审核提示
                    _ReviewNoticeBanner(),
                    const SizedBox(height: 12),

                    // 区块 1: 基本信息
                    _SectionCard(
                      title: 'Basic Info',
                      onEdit: () => context.push('/store/edit'),
                      child: _BasicInfoContent(store: store),
                    ),
                    const SizedBox(height: 12),

                    // 区块 2: 专业资料（注册时填写的商业信息）
                    _SectionCard(
                      title: 'Professional Info',
                      onEdit: () => context.push('/store/edit'),
                      child: _ProfessionalInfoContent(store: store),
                    ),
                    const SizedBox(height: 12),

                    // 区块 3: 证件执照
                    if (store.documents.isNotEmpty) ...[
                      _SectionCard(
                        title: 'Licenses & Documents',
                        onEdit: () {}, // 证件不允许在此编辑，需重新提交审核
                        child: _DocumentsContent(documents: store.documents),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 区块 4: 门店照片
                    _SectionCard(
                      title: 'Store Photos',
                      onEdit: () => context.push('/store/photos'),
                      child: _PhotosContent(store: store),
                    ),
                    const SizedBox(height: 12),

                    // 区块 4: 营业时间
                    _SectionCard(
                      title: 'Business Hours',
                      onEdit: () => context.push('/store/hours'),
                      child: _HoursContent(hours: store.hours),
                    ),
                    const SizedBox(height: 12),

                    // 区块 5: 全局分类（用户端首页筛选用）
                    _SectionCard(
                      title: 'Global Categories',
                      onEdit: () => context.push('/store/categories'),
                      child: _GlobalCategoriesContent(store: store),
                    ),
                    const SizedBox(height: 12),

                    // 区块 6: 商家类别和标签
                    _SectionCard(
                      title: 'Category & Tags',
                      onEdit: () => context.push('/store/tags'),
                      child: _TagsContent(store: store),
                    ),
                    const SizedBox(height: 12),

                    // 区块 7: 设施与服务
                    _SectionCard(
                      title: 'Facilities & Services',
                      onEdit: () => context.push('/store/facilities'),
                      child: _FacilitiesContent(),
                    ),
                    const SizedBox(height: 24),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 门头照 Hero 区域 + 店名叠加（SliverAppBar）
// ============================================================
class _StorefrontHeader extends StatelessWidget {
  const _StorefrontHeader({required this.store});

  final StoreInfo store;

  @override
  Widget build(BuildContext context) {
    final storefrontUrl = store.bestStorefrontUrl;
    final hasPhoto = storefrontUrl != null && storefrontUrl.isNotEmpty;

    return SliverAppBar(
      expandedHeight: hasPhoto ? 220 : 120,
      pinned: true,
      backgroundColor: const Color(0xFFFF6B35),
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: hasPhoto
            ? Stack(
                fit: StackFit.expand,
                children: [
                  // 门头照
                  CachedNetworkImage(
                    imageUrl: storefrontUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      color: const Color(0xFFEEEEEE),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFF6B35),
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                    errorWidget: (_, _, _) => Container(
                      color: const Color(0xFFFF6B35),
                      child: const Icon(Icons.store, size: 48, color: Colors.white54),
                    ),
                  ),
                  // 渐变遮罩（让底部文字清晰）
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                  // 店名和状态
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            shadows: [Shadow(blurRadius: 4, color: Colors.black38)],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (store.category != null) ...[
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    store.category!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Icon(
                              store.isOpenNow ? Icons.circle : Icons.circle_outlined,
                              size: 8,
                              color: store.isOpenNow ? Colors.greenAccent : Colors.white54,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              store.isOpenNow ? 'Open Now' : 'Closed',
                              style: TextStyle(
                                color: store.isOpenNow ? Colors.greenAccent : Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Container(
                color: const Color(0xFFFF6B35),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 40),
                      const Icon(Icons.store, size: 36, color: Colors.white70),
                      const SizedBox(height: 8),
                      Text(
                        store.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          onPressed: () {
            // 通过 context 找到 WidgetRef 不太方便，用 ProviderScope 外的方式
            // 这里留空，用下拉刷新代替
          },
        ),
      ],
    );
  }
}

// ============================================================
// 修改需审核提示横幅
// ============================================================
class _ReviewNoticeBanner extends StatelessWidget {
  const _ReviewNoticeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: const Row(
        children: [
          Icon(Icons.verified_user_outlined, size: 18, color: Color(0xFF1976D2)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'All profile changes require admin review before being visible to customers.',
              style: TextStyle(fontSize: 12, color: Color(0xFF1565C0)),
            ),
          ),
        ],
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
// 专业资料内容区（注册时填写的商业信息）
// ============================================================
class _ProfessionalInfoContent extends StatelessWidget {
  const _ProfessionalInfoContent({required this.store});

  final StoreInfo store;

  @override
  Widget build(BuildContext context) {
    // 检查是否有任何专业资料
    final hasData = (store.companyName?.isNotEmpty ?? false) ||
        (store.contactName?.isNotEmpty ?? false) ||
        (store.ein?.isNotEmpty ?? false);

    if (!hasData) {
      return const Text(
        'No professional info available. This information is filled during registration.',
        style: TextStyle(fontSize: 13, color: Color(0xFFBBBBBB)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (store.companyName?.isNotEmpty == true) ...[
          _InfoRow(label: 'Company Name', value: store.companyName!),
          const SizedBox(height: 10),
        ],
        if (store.contactName?.isNotEmpty == true) ...[
          _InfoRow(label: 'Contact Person', value: store.contactName!),
          const SizedBox(height: 10),
        ],
        if (store.contactEmail?.isNotEmpty == true) ...[
          _InfoRow(label: 'Contact Email', value: store.contactEmail!),
          const SizedBox(height: 10),
        ],
        if (store.ein?.isNotEmpty == true) ...[
          _InfoRow(
            label: 'EIN / Tax ID',
            value: _maskEin(store.ein!),
          ),
          const SizedBox(height: 10),
        ],
        if (store.category?.isNotEmpty == true)
          _InfoRow(label: 'Category', value: store.category!),
        if (store.city?.isNotEmpty == true) ...[
          const SizedBox(height: 10),
          _InfoRow(label: 'City', value: store.city!),
        ],
        if (store.website?.isNotEmpty == true) ...[
          const SizedBox(height: 10),
          _InfoRow(label: 'Website', value: store.website!),
        ],
      ],
    );
  }

  // 部分遮盖 EIN（安全考虑，只显示前两位和后两位）
  String _maskEin(String ein) {
    if (ein.length < 4) return '***';
    return '${ein.substring(0, 2)}-*****${ein.substring(ein.length - 2)}';
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
// ============================================================
// 证件执照内容区（注册时上传的证件图片）
// ============================================================
class _DocumentsContent extends StatelessWidget {
  const _DocumentsContent({required this.documents});

  final List<MerchantDoc> documents;

  @override
  Widget build(BuildContext context) {
    // 过滤掉门头照（已在顶部 Hero 区展示）
    final licenseDocs = documents
        .where((d) => d.documentType != 'storefront_photo')
        .toList();

    if (licenseDocs.isEmpty) {
      return const Text(
        'No documents uploaded',
        style: TextStyle(fontSize: 13, color: Color(0xFFBBBBBB)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: licenseDocs.map((doc) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 证件缩略图
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: doc.fileUrl,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    width: 72,
                    height: 72,
                    color: const Color(0xFFF0F0F0),
                    child: const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFFF6B35),
                        ),
                      ),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    width: 72,
                    height: 72,
                    color: const Color(0xFFF0F0F0),
                    child: const Icon(Icons.description_outlined,
                        color: Color(0xFFCCCCCC), size: 28),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 证件名称和状态
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.displayLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.check_circle, size: 14, color: Color(0xFF4CAF50)),
                        const SizedBox(width: 4),
                        const Text(
                          'Uploaded',
                          style: TextStyle(fontSize: 12, color: Color(0xFF4CAF50)),
                        ),
                      ],
                    ),
                  ],
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
// 照片内容区（只读缩略图预览）
// ============================================================
class _PhotosContent extends StatelessWidget {
  const _PhotosContent({required this.store});

  final StoreInfo store;

  @override
  Widget build(BuildContext context) {
    final storefrontUrl = store.bestStorefrontUrl;
    final envCount = store.environmentPhotos.length;
    final productCount = store.productPhotos.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 门头照预览
        Row(
          children: [
            // 缩略图
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: storefrontUrl != null
                  ? CachedNetworkImage(
                      imageUrl: storefrontUrl,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => _PhotoPlaceholder(size: 64),
                    )
                  : _PhotoPlaceholder(size: 64),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text(
                        'Storefront',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF333333),
                        ),
                      ),
                      SizedBox(width: 4),
                      Text(
                        '*',
                        style: TextStyle(color: Color(0xFFFF6B35), fontSize: 14),
                      ),
                    ],
                  ),
                  Text(
                    storefrontUrl != null ? 'Uploaded' : 'Not uploaded',
                    style: TextStyle(
                      fontSize: 12,
                      color: storefrontUrl != null
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFFF6B35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 环境照和菜品照计数
        Row(
          children: [
            Expanded(
              child: _PhotoCountBadge(
                label: 'Environment',
                count: envCount,
                max: 10,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PhotoCountBadge(
                label: 'Products',
                count: productCount,
                max: 10,
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
              Expanded(
                child: Text(
                  h.displayText,
                  style: TextStyle(
                    fontSize: 13,
                    color: h.isClosed
                        ? const Color(0xFFBBBBBB)
                        : const Color(0xFF333333),
                    fontWeight:
                        h.isClosed ? FontWeight.w400 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
// 全局分类内容区（用户端首页筛选用的分类）
// ============================================================
class _GlobalCategoriesContent extends StatelessWidget {
  const _GlobalCategoriesContent({required this.store});

  final StoreInfo store;

  @override
  Widget build(BuildContext context) {
    final categories = store.globalCategories;

    if (categories.isEmpty) {
      return const Text(
        'No categories selected. Add categories so customers can find your deals.',
        style: TextStyle(fontSize: 13, color: Color(0xFFBBBBBB)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories.map((cat) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3EE),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFCCB3)),
          ),
          child: Text(
            cat.name,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFFF6B35),
              fontWeight: FontWeight.w500,
            ),
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

// ============================================================
// 设施区块内容（从 facilitiesProvider 读取，显示前 4 个）
// ============================================================
class _FacilitiesContent extends ConsumerWidget {
  const _FacilitiesContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facilitiesAsync = ref.watch(facilitiesProvider);

    return facilitiesAsync.when(
      loading: () => const SizedBox(
        height: 32,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF6B35)),
          ),
        ),
      ),
      error: (_, __) => const Text(
        'Failed to load facilities',
        style: TextStyle(fontSize: 13, color: Colors.grey),
      ),
      data: (facilities) {
        if (facilities.isEmpty) {
          return const Text(
            'No facilities added',
            style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
          );
        }
        final shown = facilities.take(4).toList();
        final extra = facilities.length - shown.length;
        return Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ...shown.map((f) => _FacilityChip(facility: f)),
            if (extra > 0)
              Chip(
                label: Text(
                  '+$extra more',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                ),
                backgroundColor: const Color(0xFFF0F0F0),
                visualDensity: VisualDensity.compact,
              ),
          ],
        );
      },
    );
  }
}

class _FacilityChip extends StatelessWidget {
  const _FacilityChip({required this.facility});

  final StoreFacilityModel facility;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(facility.icon, size: 14, color: const Color(0xFFFF6B35)),
      label: Text(
        facility.name,
        style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
      ),
      backgroundColor: const Color(0xFFFFF4EF),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide.none,
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
