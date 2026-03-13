// 菜品创建/编辑页
// editItem 不为 null 时为编辑模式
// 分类使用商家自定义的 menu_categories

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../models/menu_item.dart' as model;
import '../providers/menu_provider.dart';
import '../providers/category_provider.dart';

// ============================================================
// MenuEditPage — 菜品创建/编辑
// ============================================================
class MenuEditPage extends ConsumerStatefulWidget {
  const MenuEditPage({super.key, this.editItem, this.initialName});

  final model.MenuItem? editItem;

  /// 创建模式下预填的菜品名称（从 Deal 确认页传入）
  final String? initialName;

  @override
  ConsumerState<MenuEditPage> createState() => _MenuEditPageState();
}

class _MenuEditPageState extends ConsumerState<MenuEditPage> {
  static const _primaryOrange = Color(0xFFFF6B35);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  String? _selectedCategoryId;
  bool _isSignature = false;
  String? _imageUrl;
  XFile? _pickedImage;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final item = widget.editItem;
    _nameController = TextEditingController(text: item?.name ?? widget.initialName ?? '');
    _priceController = TextEditingController(
      text: item?.price != null ? item!.price!.toStringAsFixed(2) : '',
    );
    if (item != null) {
      _selectedCategoryId = item.categoryId;
      _isSignature = item.isSignature;
      _imageUrl = item.imageUrl;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _pickedImage = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final notifier = ref.read(menuProvider.notifier);

      // 上传图片（如有新选择）
      String? finalImageUrl = _imageUrl;
      if (_pickedImage != null) {
        finalImageUrl = await notifier.uploadImage(_pickedImage!);
      }

      final price = double.tryParse(_priceController.text);

      if (widget.editItem != null) {
        // 编辑模式
        await notifier.updateItem(
          widget.editItem!.copyWith(
            name: _nameController.text.trim(),
            price: price,
            categoryId: _selectedCategoryId,
            clearCategoryId: _selectedCategoryId == null,
            isSignature: _isSignature,
            imageUrl: finalImageUrl,
          ),
        );
      } else {
        // 创建模式
        await notifier.createItem(
          model.MenuItem(
            id: '',
            merchantId: notifier.merchantId,
            name: _nameController.text.trim(),
            price: price,
            categoryId: _selectedCategoryId,
            isSignature: _isSignature,
            imageUrl: finalImageUrl,
          ),
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.editItem != null ? 'Item updated' : 'Item added'),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
        ),
      );

      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editItem != null;
    final categoriesAsync = ref.watch(categoryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          isEditing ? 'Edit Item' : 'Add Item',
          style: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 图片
              _buildImagePicker(),
              const SizedBox(height: 20),

              // 名称
              TextFormField(
                key: const ValueKey('menu_edit_name_field'),
                controller: _nameController,
                maxLength: 100,
                decoration: _inputDecoration(
                  label: 'Item Name',
                  hint: 'e.g. Smoked Beef Brisket',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Name is required';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 价格
              TextFormField(
                key: const ValueKey('menu_edit_price_field'),
                controller: _priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                decoration: _inputDecoration(
                  label: 'Price',
                  hint: '0.00',
                ).copyWith(prefixText: '\$ '),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Price is required';
                  final price = double.tryParse(v);
                  if (price == null || price <= 0) return 'Enter a valid price';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 分类选择（动态）
              const Text(
                'Category',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF555555),
                ),
              ),
              const SizedBox(height: 8),
              _buildCategorySelector(categoriesAsync),
              const SizedBox(height: 16),

              // 招牌菜开关
              SwitchListTile(
                title: const Text(
                  'Signature Item',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                subtitle: const Text(
                  'Mark as a must-try dish',
                  style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
                ),
                value: _isSignature,
                activeThumbColor: _primaryOrange,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) => setState(() => _isSignature = val),
              ),
              const SizedBox(height: 24),

              // 提交按钮
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          isEditing ? 'Save Changes' : 'Add Item',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 分类选择器（Chip 列表，包含 Uncategorized + 自定义分类）
  Widget _buildCategorySelector(AsyncValue categoriesAsync) {
    return categoriesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(color: _primaryOrange),
      ),
      error: (err, _) {
        // 加载失败时降级为只显示 Uncategorized
        debugPrint('Category load error: $err');
        return Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Uncategorized'),
              selected: true,
              selectedColor: _primaryOrange,
              labelStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              backgroundColor: const Color(0xFFF5F5F5),
              side: const BorderSide(color: _primaryOrange),
              onSelected: (_) {},
            ),
          ],
        );
      },
      data: (categories) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // "Uncategorized" 选项
            ChoiceChip(
              label: const Text('Uncategorized'),
              selected: _selectedCategoryId == null,
              selectedColor: _primaryOrange,
              labelStyle: TextStyle(
                color: _selectedCategoryId == null
                    ? Colors.white
                    : const Color(0xFF555555),
                fontWeight: FontWeight.w500,
              ),
              backgroundColor: const Color(0xFFF5F5F5),
              side: BorderSide(
                color: _selectedCategoryId == null
                    ? _primaryOrange
                    : const Color(0xFFE0E0E0),
              ),
              onSelected: (val) {
                if (val) setState(() => _selectedCategoryId = null);
              },
            ),
            // 商家自定义分类
            ...categories.map((cat) {
              final selected = _selectedCategoryId == cat.id;
              return ChoiceChip(
                label: Text(cat.name),
                selected: selected,
                selectedColor: _primaryOrange,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF555555),
                  fontWeight: FontWeight.w500,
                ),
                backgroundColor: const Color(0xFFF5F5F5),
                side: BorderSide(
                  color: selected ? _primaryOrange : const Color(0xFFE0E0E0),
                ),
                onSelected: (val) {
                  if (val) setState(() => _selectedCategoryId = cat.id);
                },
              );
            }),
          ],
        );
      },
    );
  }

  // 图片选择区域
  Widget _buildImagePicker() {
    Widget imageWidget;

    if (_pickedImage != null) {
      imageWidget = Image.file(
        File(_pickedImage!.path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: 180,
      );
    } else if (_imageUrl != null && _imageUrl!.isNotEmpty) {
      imageWidget = Image.network(
        _imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 180,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    } else {
      imageWidget = _buildPlaceholder();
    }

    return GestureDetector(
      onTap: _pickImage,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: imageWidget,
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      height: 180,
      color: const Color(0xFFF0F0F0),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 40, color: Color(0xFF999999)),
          SizedBox(height: 8),
          Text(
            'Tap to add photo',
            style: TextStyle(fontSize: 14, color: Color(0xFF999999)),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8F9FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _primaryOrange, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE53935)),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }
}
