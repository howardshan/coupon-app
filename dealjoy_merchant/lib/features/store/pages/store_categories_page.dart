// 全局分类选择页面
// 商家可以多选分类（最多5个），用于用户端首页分类筛选

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/store_info.dart';
import '../providers/store_provider.dart';

// ============================================================
// StoreCategoriesPage — 全局分类多选页面
// ============================================================
class StoreCategoriesPage extends ConsumerStatefulWidget {
  const StoreCategoriesPage({super.key});

  @override
  ConsumerState<StoreCategoriesPage> createState() =>
      _StoreCategoriesPageState();
}

class _StoreCategoriesPageState extends ConsumerState<StoreCategoriesPage> {
  // 所有可用分类
  List<Map<String, dynamic>> _allCategories = [];
  // 当前选中的分类 ID 集合
  Set<int> _selectedIds = {};
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final service = ref.read(storeServiceProvider);
      final result = await service.fetchCategories();
      if (!mounted) return;
      setState(() {
        _allCategories = result.categories;
        _selectedIds = result.selectedIds.toSet();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      // 构建选中的 GlobalCategory 列表
      final selectedCategories = _allCategories
          .where((c) => _selectedIds.contains(c['id'] as int))
          .map((c) => GlobalCategory.fromJson(c))
          .toList();

      await ref
          .read(storeProvider.notifier)
          .updateGlobalCategories(selectedCategories);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Categories updated successfully'),
          backgroundColor: Color(0xFF4CAF50),
          duration: Duration(seconds: 2),
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
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
          'Global Categories',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _isSaving
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFFF6B35),
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: _save,
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        color: Color(0xFFFF6B35),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Error: $_error',
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _error = null;
                          });
                          _loadCategories();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 提示信息
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: const Color(0xFFF0F7FF),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 18, color: Color(0xFF1976D2)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Select up to 5 categories. Customers use these to find your deals on the homepage. (${_selectedIds.length}/5 selected)',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 分类列表
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _allCategories.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final cat = _allCategories[index];
                          final catId = cat['id'] as int;
                          final catName = cat['name'] as String? ?? '';
                          final isSelected = _selectedIds.contains(catId);

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedIds.remove(catId);
                                } else if (_selectedIds.length < 5) {
                                  _selectedIds.add(catId);
                                } else {
                                  // 已达上限，提示
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Maximum 5 categories allowed'),
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFFFF3EE)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFFF6B35)
                                      : const Color(0xFFE0E0E0),
                                  width: isSelected ? 1.5 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // 分类图标
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFFFF6B35)
                                              .withValues(alpha: 0.15)
                                          : const Color(0xFFF5F5F5),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: _categoryIcon(
                                        catName,
                                        cat['icon'] as String?,
                                        isSelected,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  // 分类名称
                                  Expanded(
                                    child: Text(
                                      catName,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? const Color(0xFFFF6B35)
                                            : const Color(0xFF333333),
                                      ),
                                    ),
                                  ),
                                  // 勾选状态
                                  Icon(
                                    isSelected
                                        ? Icons.check_circle_rounded
                                        : Icons.circle_outlined,
                                    color: isSelected
                                        ? const Color(0xFFFF6B35)
                                        : const Color(0xFFCCCCCC),
                                    size: 24,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // 底部保存按钮
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: Color(0xFFEEEEEE)),
                        ),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
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
                              : Text(
                                  'Save (${_selectedIds.length} selected)',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  // 渲染分类图标：优先使用 DB 的 icon 字段（URL / emoji），无则用内置映射
  Widget _categoryIcon(String name, String? iconValue, bool isSelected) {
    final color =
        isSelected ? const Color(0xFFFF6B35) : const Color(0xFF999999);

    // URL 图标 → 网络图片
    if (iconValue != null && iconValue.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: iconValue,
        width: 22,
        height: 22,
        fit: BoxFit.contain,
        placeholder: (_, __) =>
            Icon(Icons.category_outlined, color: color, size: 22),
        errorWidget: (_, __, ___) =>
            Icon(Icons.category_outlined, color: color, size: 22),
      );
    }

    // emoji 图标 → 文字
    if (iconValue != null && iconValue.isNotEmpty &&
        !iconValue.startsWith('Icons.')) {
      return Text(iconValue, style: const TextStyle(fontSize: 20));
    }

    // 内置映射（向下兼容旧分类）
    const iconMap = <String, IconData>{
      'BBQ': Icons.outdoor_grill,
      'Hot Pot': Icons.ramen_dining,
      'Coffee': Icons.coffee,
      'Dessert': Icons.cake,
      'Massage': Icons.spa,
      'Sushi': Icons.set_meal,
      'Pizza': Icons.local_pizza,
      'Ramen': Icons.ramen_dining,
      'Korean': Icons.rice_bowl,
    };
    return Icon(iconMap[name] ?? Icons.category_outlined, color: color, size: 22);
  }
}
