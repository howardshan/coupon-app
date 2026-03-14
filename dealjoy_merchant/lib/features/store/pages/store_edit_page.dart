// 门店基本信息编辑页面
// 表单字段: Store Name / Description / Phone / Address
// 保存时调用 storeProvider.updateBasicInfo

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/store_provider.dart';

// ============================================================
// StoreEditPage — 基本信息编辑页（ConsumerStatefulWidget）
// ============================================================
class StoreEditPage extends ConsumerStatefulWidget {
  const StoreEditPage({super.key});

  @override
  ConsumerState<StoreEditPage> createState() => _StoreEditPageState();
}

class _StoreEditPageState extends ConsumerState<StoreEditPage> {
  // 表单 Key，用于触发验证
  final _formKey = GlobalKey<FormState>();

  // 文本控制器
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  bool _isInitialized = false; // 是否已用门店数据初始化控制器
  bool _isSaving = false;       // 保存中状态

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // 用当前门店数据初始化表单（只执行一次）
  void _initFormIfNeeded() {
    if (_isInitialized) return;
    final store = ref.read(storeProvider).valueOrNull;
    if (store == null) return;

    _nameController.text = store.name;
    _descriptionController.text = store.description ?? '';
    _phoneController.text = store.phone ?? '';
    _addressController.text = store.address ?? '';
    _isInitialized = true;
  }

  // 保存表单
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      await ref.read(storeProvider.notifier).updateBasicInfo(
            name: _nameController.text.trim(),
            description: _descriptionController.text.trim(),
            phone: _phoneController.text.trim(),
            address: _addressController.text.trim(),
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Store info updated successfully'),
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
    final storeAsync = ref.watch(storeProvider);

    // 数据加载完成后初始化表单
    storeAsync.whenData((_) => _initFormIfNeeded());

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
          'Edit Basic Info',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        actions: [
          // 保存按钮
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
        data: (_) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- Store Name ----
                _FieldCard(
                  child: _FormField(
                    label: 'Store Name',
                    required: true,
                    child: TextFormField(
                      key: const ValueKey('store_edit_name_field'),
                      controller: _nameController,
                      decoration: _inputDecoration('Enter store name'),
                      maxLength: 100,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Store name is required';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ---- Description ----
                _FieldCard(
                  child: _FormField(
                    label: 'Description',
                    hint: 'Help customers know your store',
                    child: TextFormField(
                      key: const ValueKey('store_edit_desc_field'),
                      controller: _descriptionController,
                      decoration: _inputDecoration(
                        'A brief introduction to your store...',
                      ),
                      maxLength: 500,
                      maxLines: 4,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ---- Phone ----
                _FieldCard(
                  child: _FormField(
                    label: 'Contact Phone',
                    child: TextFormField(
                      key: const ValueKey('store_edit_phone_field'),
                      controller: _phoneController,
                      decoration: _inputDecoration('e.g. (214) 555-0100'),
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v != null && v.trim().isNotEmpty) {
                          // 简单校验：去除非数字后至少 7 位
                          final digits = v.replaceAll(RegExp(r'\D'), '');
                          if (digits.length < 7) {
                            return 'Please enter a valid phone number';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ---- Address ----
                _FieldCard(
                  child: _FormField(
                    label: 'Store Address',
                    hint: 'Full address (street, city, state, zip)',
                    child: TextFormField(
                      key: const ValueKey('store_edit_address_field'),
                      controller: _addressController,
                      decoration: _inputDecoration(
                        'e.g. 123 Main St, Dallas, TX 75201',
                      ),
                      maxLines: 2,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _save(),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ---- Save Changes 按钮 ----
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    key: const ValueKey('store_edit_save_btn'),
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
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 统一的输入框装饰
  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
      filled: false,
      border: InputBorder.none,
      contentPadding: EdgeInsets.zero,
      counterText: '',
    );
  }
}

// ============================================================
// 表单卡片包装器（白色圆角卡片）
// ============================================================
class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
      child: child,
    );
  }
}

// ============================================================
// 单个表单字段（含标签 + 可选提示 + 表单控件）
// ============================================================
class _FormField extends StatelessWidget {
  const _FormField({
    required this.label,
    required this.child,
    this.hint,
    this.required = false,
  });

  final String label;
  final Widget child;
  final String? hint;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 字段标签
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF555555),
              ),
            ),
            if (required) ...[
              const SizedBox(width: 3),
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
        // 可选提示文字
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(
            hint!,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFAAAAAA),
            ),
          ),
        ],
        const SizedBox(height: 8),
        const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),
        const SizedBox(height: 8),
        // 表单控件
        child,
      ],
    );
  }
}
