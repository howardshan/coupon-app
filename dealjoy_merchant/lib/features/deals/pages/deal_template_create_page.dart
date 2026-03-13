// V2.2 Deal 模板创建页面
// 单页滚动表单，分组展示模板核心字段
// 创建成功后返回模板列表页

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/deal_template.dart';
import '../providers/deals_provider.dart';

// ============================================================
// DealTemplateCreatePage — 模板创建页面（ConsumerStatefulWidget）
// ============================================================
class DealTemplateCreatePage extends ConsumerStatefulWidget {
  const DealTemplateCreatePage({super.key});

  @override
  ConsumerState<DealTemplateCreatePage> createState() =>
      _DealTemplateCreatePageState();
}

class _DealTemplateCreatePageState
    extends ConsumerState<DealTemplateCreatePage> {
  // 表单 Key
  final _formKey = GlobalKey<FormState>();

  // ── Basic Info ──────────────────────────────────────────────
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _selectedCategory;

  // ── Pricing ─────────────────────────────────────────────────
  final _originalPriceController = TextEditingController();
  final _discountPriceController = TextEditingController();
  final _discountLabelController = TextEditingController();

  // ── Rules ───────────────────────────────────────────────────
  final _stockLimitController = TextEditingController(text: '100');
  final _maxPerPersonController = TextEditingController();
  String _validityType = 'fixed_date';
  final _validityDaysController = TextEditingController();
  final _usageNotesController = TextEditingController();
  final _usageDaysController = TextEditingController();
  final Set<String> _selectedUsageDays = {};
  bool _isStackable = true;
  final _refundPolicyController =
      TextEditingController(text: 'Refund anytime before use, refund when expired');

  // ── Other ───────────────────────────────────────────────────
  String _dealType = 'regular';
  final _badgeTextController = TextEditingController();

  // 提交状态
  bool _isSubmitting = false;

  // 主题色
  static const _primaryColor = Color(0xFFFF6B35);

  // 分类选项
  static const _categoryOptions = [
    'Food & Drink',
    'Beauty & Spa',
    'Activities',
    'Health & Fitness',
    'Retail',
    'Services',
    'Travel',
    'Other',
  ];

  // 有效期类型选项
  static const _validityTypeOptions = [
    ('fixed_date', 'Fixed Date'),
    ('days_after_purchase', 'Days After Purchase'),
  ];

  // 使用星期选项
  static const _dayOptions = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  // deal_type 选项
  static const _dealTypeOptions = [
    ('regular', 'Regular'),
    ('flash', 'Flash Deal'),
    ('exclusive', 'Exclusive'),
    ('bundle', 'Bundle'),
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _originalPriceController.dispose();
    _discountPriceController.dispose();
    _discountLabelController.dispose();
    _stockLimitController.dispose();
    _maxPerPersonController.dispose();
    _validityDaysController.dispose();
    _usageNotesController.dispose();
    _usageDaysController.dispose();
    _refundPolicyController.dispose();
    _badgeTextController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────
  // 提交表单：构建 DealTemplate 并调用 Provider
  // ──────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final now = DateTime.now();
      final template = DealTemplate(
        id: '', // 由后端生成
        brandId: '', // 由后端从 JWT 中提取
        createdBy: '', // 由后端从 JWT 中提取
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory ?? '',
        originalPrice:
            double.tryParse(_originalPriceController.text.trim()) ?? 0,
        discountPrice:
            double.tryParse(_discountPriceController.text.trim()) ?? 0,
        discountLabel: _discountLabelController.text.trim(),
        stockLimit: int.tryParse(_stockLimitController.text.trim()) ?? 100,
        packageContents: '',
        usageNotes: _usageNotesController.text.trim(),
        usageDays: _selectedUsageDays.toList(),
        maxPerPerson: _maxPerPersonController.text.trim().isNotEmpty
            ? int.tryParse(_maxPerPersonController.text.trim())
            : null,
        isStackable: _isStackable,
        validityType: _validityType,
        validityDays: _validityDaysController.text.trim().isNotEmpty
            ? int.tryParse(_validityDaysController.text.trim())
            : null,
        refundPolicy: _refundPolicyController.text.trim(),
        imageUrls: const [],
        dealType: _dealType,
        badgeText: _badgeTextController.text.trim().isNotEmpty
            ? _badgeTextController.text.trim()
            : null,
        dealCategoryId: null, // 可后续扩展
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      await ref.read(dealTemplatesProvider.notifier).createTemplate(template);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template created successfully')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create template: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Template'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey[200]),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Basic Info 分组 ────────────────────────────
            _SectionHeader(title: 'Basic Info'),
            const SizedBox(height: 12),

            // 标题（必填）
            TextFormField(
              controller: _titleController,
              decoration: _inputDecoration('Title *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),

            // 描述
            TextFormField(
              controller: _descriptionController,
              decoration: _inputDecoration('Description'),
              maxLines: 3,
              minLines: 2,
            ),
            const SizedBox(height: 12),

            // 分类下拉
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: _inputDecoration('Category'),
              items: _categoryOptions
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedCategory = v),
            ),
            const SizedBox(height: 24),

            // ── Pricing 分组 ───────────────────────────────
            _SectionHeader(title: 'Pricing'),
            const SizedBox(height: 12),

            // 原价（必填）
            TextFormField(
              controller: _originalPriceController,
              decoration: _inputDecoration('Original Price (\$) *'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Original price is required';
                }
                final num = double.tryParse(v.trim());
                if (num == null || num <= 0) return 'Enter a valid price';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // 折扣价（必填）
            TextFormField(
              controller: _discountPriceController,
              decoration: _inputDecoration('Discount Price (\$) *'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Discount price is required';
                }
                final num = double.tryParse(v.trim());
                if (num == null || num <= 0) return 'Enter a valid price';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // 折扣标签
            TextFormField(
              controller: _discountLabelController,
              decoration: _inputDecoration('Discount Label (e.g. 20% OFF)'),
            ),
            const SizedBox(height: 24),

            // ── Rules 分组 ─────────────────────────────────
            _SectionHeader(title: 'Rules'),
            const SizedBox(height: 12),

            // 库存限制
            TextFormField(
              controller: _stockLimitController,
              decoration: _inputDecoration('Stock Limit'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = int.tryParse(v.trim());
                if (n == null || n <= 0) return 'Enter a valid number';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // 每人最多购买
            TextFormField(
              controller: _maxPerPersonController,
              decoration: _inputDecoration('Max Per Person (optional)'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 12),

            // 有效期类型下拉
            DropdownButtonFormField<String>(
              value: _validityType,
              decoration: _inputDecoration('Validity Type'),
              items: _validityTypeOptions
                  .map((opt) =>
                      DropdownMenuItem(value: opt.$1, child: Text(opt.$2)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _validityType = v);
              },
            ),
            const SizedBox(height: 12),

            // 有效期天数（仅 days_after_purchase 时显示）
            if (_validityType == 'days_after_purchase') ...[
              TextFormField(
                controller: _validityDaysController,
                decoration: _inputDecoration('Valid for (days)'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (_validityType != 'days_after_purchase') return null;
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter validity days';
                  }
                  final n = int.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: 12),
            ],

            // 使用备注
            TextFormField(
              controller: _usageNotesController,
              decoration: _inputDecoration('Usage Notes'),
              maxLines: 2,
              minLines: 1,
            ),
            const SizedBox(height: 12),

            // 使用星期多选
            Text(
              'Usage Days',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _dayOptions.map((day) {
                final isSelected = _selectedUsageDays.contains(day);
                return FilterChip(
                  label: Text(day),
                  selected: isSelected,
                  selectedColor: _primaryColor.withValues(alpha: 0.15),
                  checkmarkColor: _primaryColor,
                  labelStyle: TextStyle(
                    color: isSelected ? _primaryColor : Colors.black87,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected ? _primaryColor : Colors.grey[300]!,
                  ),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedUsageDays.add(day);
                      } else {
                        _selectedUsageDays.remove(day);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // Stackable 开关
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stackable with Other Deals',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        'Can be used together with other promotions',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isStackable,
                  activeThumbColor: _primaryColor,
                  onChanged: (v) => setState(() => _isStackable = v),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 退款政策
            TextFormField(
              controller: _refundPolicyController,
              decoration: _inputDecoration('Refund Policy'),
              maxLines: 2,
              minLines: 1,
            ),
            const SizedBox(height: 24),

            // ── Other 分组 ─────────────────────────────────
            _SectionHeader(title: 'Other'),
            const SizedBox(height: 12),

            // Deal 类型下拉
            DropdownButtonFormField<String>(
              value: _dealType,
              decoration: _inputDecoration('Deal Type'),
              items: _dealTypeOptions
                  .map((opt) =>
                      DropdownMenuItem(value: opt.$1, child: Text(opt.$2)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _dealType = v);
              },
            ),
            const SizedBox(height: 12),

            // Badge 文本
            TextFormField(
              controller: _badgeTextController,
              decoration: _inputDecoration('Badge Text (optional, e.g. HOT)'),
            ),
            const SizedBox(height: 32),

            // ── 提交按钮 ───────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Create Template',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // 统一输入框样式
  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _primaryColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }
}

// ============================================================
// _SectionHeader — 分组标题组件
// ============================================================
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
