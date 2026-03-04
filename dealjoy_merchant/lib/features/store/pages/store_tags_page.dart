// 门店类别与标签管理页面
// 类别只读展示（在注册时已确定，不可修改）
// 标签支持从预定义列表添加/删除，最多 10 个

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/store_provider.dart';
import '../widgets/tag_chip_list.dart';

// ============================================================
// StoreTagsPage — 标签管理页（ConsumerStatefulWidget）
// ============================================================
class StoreTagsPage extends ConsumerStatefulWidget {
  const StoreTagsPage({super.key});

  @override
  ConsumerState<StoreTagsPage> createState() => _StoreTagsPageState();
}

class _StoreTagsPageState extends ConsumerState<StoreTagsPage> {
  // 本地标签列表（编辑中的临时状态）
  List<String>? _localTags;
  bool _isInitialized = false;
  bool _isSaving = false;

  // 从 provider 初始化本地标签（只执行一次）
  void _initIfNeeded(List<String> serverTags) {
    if (_isInitialized) return;
    _localTags = List.from(serverTags);
    _isInitialized = true;
  }

  // 添加标签
  void _addTag(String tag) {
    if (_localTags == null) return;
    if (_localTags!.contains(tag)) return;
    if (_localTags!.length >= kMaxTags) return;
    setState(() => _localTags = [..._localTags!, tag]);
  }

  // 移除标签
  void _removeTag(String tag) {
    if (_localTags == null) return;
    setState(() => _localTags = _localTags!.where((t) => t != tag).toList());
  }

  // 保存标签
  Future<void> _save() async {
    if (_localTags == null) return;

    setState(() => _isSaving = true);

    try {
      await ref.read(storeProvider.notifier).updateTags(_localTags!);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tags updated successfully'),
          backgroundColor: Color(0xFF4CAF50),
          duration: Duration(seconds: 2),
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save tags: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(storeProvider);

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
          'Category & Tags',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
      ),
      body: storeAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
        ),
        error: (e, _) => Center(
          child: Text(
            'Failed to load store: $e',
            style: const TextStyle(color: Colors.red),
          ),
        ),
        data: (store) {
          _initIfNeeded(store.tags);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ---- 类别区块（只读）----
                      _SectionCard(
                        title: 'Category',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Your business category is set during registration and cannot be changed.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF999999),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (store.category != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3EE),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFFFFCCB3),
                                  ),
                                ),
                                child: Text(
                                  store.category!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFFFF6B35),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else
                              const Text(
                                'No category assigned',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFFBBBBBB),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ---- 标签区块（可编辑）----
                      _SectionCard(
                        title: 'Tags',
                        trailing: Text(
                          '${_localTags?.length ?? 0}/$kMaxTags',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF999999),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Add tags to help customers find your store. Tags are shown on your store and deal pages.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF999999),
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (_localTags != null)
                              TagChipList(
                                tags: _localTags!,
                                readOnly: false,
                                onTagRemoved: _removeTag,
                                onTagAdded: _addTag,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ---- 预定义标签说明 ----
                      _SectionCard(
                        title: 'Available Tags',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tap a tag below to add it to your store:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF999999),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: kPredefinedTags.map((tag) {
                                final isSelected =
                                    _localTags?.contains(tag) ?? false;
                                return GestureDetector(
                                  onTap: isSelected
                                      ? () => _removeTag(tag)
                                      : () => _addTag(tag),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFFFFF3EE)
                                          : const Color(0xFFF8F9FA),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFFFF6B35)
                                            : const Color(0xFFE0E0E0),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isSelected) ...[
                                          const Icon(
                                            Icons.check_rounded,
                                            size: 14,
                                            color: Color(0xFFFF6B35),
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        Text(
                                          tag,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: isSelected
                                                ? const Color(0xFFFF6B35)
                                                : const Color(0xFF555555),
                                            fontWeight: isSelected
                                                ? FontWeight.w500
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // ---- 底部保存按钮 ----
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B35),
                        disabledBackgroundColor:
                            const Color(0xFFFF6B35).withValues(alpha: 0.5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// 通用区块卡片（标题 + 可选的右侧附加元素 + 内容）
// ============================================================
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

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
              trailing ?? const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
