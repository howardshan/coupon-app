// 品牌信息编辑页面
// 从 brand_manage_page.dart 提取，独立路由 /brand-manage/info

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/store_provider.dart';
import '../models/brand_info.dart';

class BrandInfoPage extends ConsumerStatefulWidget {
  const BrandInfoPage({super.key});

  @override
  ConsumerState<BrandInfoPage> createState() => _BrandInfoPageState();
}

class _BrandInfoPageState extends ConsumerState<BrandInfoPage> {
  bool _isEditing = false;
  bool _isSaving = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  BrandInfo? _brand;

  static const _primaryOrange = Color(0xFFFF6B35);

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _descCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // 初始化控制器文本
  void _initControllers(BrandInfo brand) {
    if (_brand?.id != brand.id) {
      _brand = brand;
      _nameCtrl.text = brand.name;
      _descCtrl.text = brand.description ?? '';
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
        title: const Text(
          'Brand Info',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: storeAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _primaryOrange),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (storeInfo) {
          final brand = storeInfo.brand;
          if (brand == null) {
            return const Center(
              child: Text('No brand found.',
                  style: TextStyle(color: Color(0xFF757575))),
            );
          }
          _initControllers(brand);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 品牌 Logo + 名称
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: brand.logoUrl != null && brand.logoUrl!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  brand.logoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.business,
                                    color: _primaryOrange,
                                    size: 32,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.business,
                                color: _primaryOrange,
                                size: 32,
                              ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              brand.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF212121),
                              ),
                            ),
                            if (brand.description != null &&
                                brand.description!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                brand.description!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF757575),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _isEditing ? Icons.close : Icons.edit,
                          color: const Color(0xFF757575),
                        ),
                        onPressed: () => setState(() {
                          _isEditing = !_isEditing;
                          if (!_isEditing) {
                            _nameCtrl.text = brand.name;
                            _descCtrl.text = brand.description ?? '';
                          }
                        }),
                      ),
                    ],
                  ),
                ),

                // 编辑表单
                if (_isEditing) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Edit Brand Info',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF212121),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('brand_info_name_field'),
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Brand Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const ValueKey('brand_info_desc_field'),
                          controller: _descCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            key: const ValueKey('brand_info_save_btn'),
                            onPressed: _isSaving ? null : _saveBrandInfo,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryOrange,
                              foregroundColor: Colors.white,
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // 品牌详情（只读）
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Column(
                    children: [
                      _InfoRow(label: 'Brand ID', value: brand.id),
                      if (brand.storeCount != null)
                        _InfoRow(
                          label: 'Locations',
                          value: '${brand.storeCount} stores',
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 保存品牌信息到后端
  Future<void> _saveBrandInfo() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brand name is required')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final service = ref.read(storeServiceProvider);
      await service.updateBrand(
        name: name,
        description: _descCtrl.text.trim(),
      );
      ref.invalidate(storeProvider);
      if (mounted) {
        setState(() {
          _isEditing = false;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Brand info updated'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// 信息行
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF212121),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
