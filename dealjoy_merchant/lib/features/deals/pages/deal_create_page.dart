// Deal创建/编辑页面
// 5步 Stepper 表单: 基本信息 → 价格 → 库存+有效期 → 使用规则 → 图片上传
// editDeal 不为 null 时为编辑模式

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../models/merchant_deal.dart';
import '../models/deal_category.dart';
import '../providers/deals_provider.dart';
import '../../store/providers/store_provider.dart';
import '../../menu/models/menu_item.dart';
import '../../menu/widgets/menu_item_picker.dart';

// ============================================================
// DealCreatePage — Deal创建/编辑页面（ConsumerStatefulWidget）
// ============================================================
class DealCreatePage extends ConsumerStatefulWidget {
  const DealCreatePage({super.key, this.editDeal});

  /// 不为 null 时为编辑模式（回填表单数据）
  final MerchantDeal? editDeal;

  @override
  ConsumerState<DealCreatePage> createState() => _DealCreatePageState();
}

class _DealCreatePageState extends ConsumerState<DealCreatePage> {
  // 当前步骤索引（0-based）
  int _currentStep = 0;

  // Step 1: 基本信息
  final _step1Key = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _usageNotesController;

  // Step 1: 套餐菜品（从选择器选出）
  List<SelectedMenuItem> _selectedMenuItems = [];

  // Step 1: Deal 分类
  String? _selectedDealCategoryId;

  // Step 2: 价格（originalPrice 由选中菜品自动计算）
  final _step2Key = GlobalKey<FormState>();
  double? _dealPrice;

  // Step 3: 库存和有效期
  final _step3Key = GlobalKey<FormState>();
  bool _isUnlimited = false;
  late final TextEditingController _stockController;
  ValidityType _validityType = ValidityType.fixedDate;
  DateTime? _endDate;
  late final TextEditingController _validityDaysController;

  // Step 4: 使用规则
  final _step4Key = GlobalKey<FormState>();
  final Set<String> _selectedDays = {};
  late final TextEditingController _maxPerPersonController;
  bool _isStackable = true;

  // Step 4b: 多店适用（仅连锁店显示）
  bool _isMultiStore = false;
  final Set<String> _selectedStoreIds = {};
  // 品牌管理员预确认的门店（打勾 = 已确认该门店有此菜品，审核通过后直接 active）
  final Set<String> _confirmedStoreIds = {};

  // Step 5: 图片
  final List<XFile> _selectedImages = [];
  bool _isSubmitting = false;

  static const _dayOptions = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // 计算原价（选中菜品的价格总和）
  double get _originalPrice {
    if (_selectedMenuItems.isEmpty) return 0;
    return _selectedMenuItems.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  // 生成套餐内容文本
  String get _packageContentsText {
    if (_selectedMenuItems.isEmpty) return '';
    return _selectedMenuItems
        .map((s) {
          final price = s.menuItem.price ?? 0;
          return '• ${s.quantity}× ${s.menuItem.name} @$price';
        })
        .join('\n');
  }

  @override
  void initState() {
    super.initState();
    final deal = widget.editDeal;

    // 若为编辑模式，回填数据
    _titleController       = TextEditingController(text: deal?.title ?? '');
    _descriptionController = TextEditingController(text: deal?.description ?? '');
    _usageNotesController  = TextEditingController(text: deal?.usageNotes ?? '');
    _stockController       = TextEditingController(
      text: deal != null && !deal.isUnlimited ? deal.stockLimit.toString() : '',
    );
    _validityDaysController = TextEditingController(
      text: deal?.validityDays?.toString() ?? '',
    );
    _maxPerPersonController = TextEditingController(
      text: deal?.maxPerPerson?.toString() ?? '',
    );

    if (deal != null) {
      _dealPrice      = deal.discountPrice;
      _isUnlimited    = deal.isUnlimited;
      _validityType   = deal.validityType;
      _endDate        = deal.expiresAt;
      _isStackable    = deal.isStackable;
      _selectedDealCategoryId = deal.dealCategoryId;
      if (deal.usageDays.isNotEmpty) {
        _selectedDays.addAll(deal.usageDays);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _usageNotesController.dispose();
    _stockController.dispose();
    _validityDaysController.dispose();
    _maxPerPersonController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------
  // Step 验证方法
  // --------------------------------------------------------
  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        if (!(_step1Key.currentState?.validate() ?? false)) return false;
        if (_selectedMenuItems.isEmpty) {
          _showSnack('Please select at least one menu item');
          return false;
        }
        return true;
      case 1:
        if (!(_step2Key.currentState?.validate() ?? false)) return false;
        if (_dealPrice == null) {
          _showSnack('Please enter the deal price');
          return false;
        }
        if (_dealPrice! >= _originalPrice) {
          _showSnack('Deal price must be less than original price');
          return false;
        }
        return true;
      case 2:
        if (!(_step3Key.currentState?.validate() ?? false)) return false;
        if (_validityType == ValidityType.fixedDate && _endDate == null) {
          _showSnack('Please select an expiry date');
          return false;
        }
        return true;
      case 3:
        return _step4Key.currentState?.validate() ?? true;
      case 4:
        if (_selectedImages.isEmpty && widget.editDeal == null) {
          _showSnack('Please upload at least 1 image');
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFE53935),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --------------------------------------------------------
  // 打开菜品选择器
  // --------------------------------------------------------
  Future<void> _openMenuItemPicker() async {
    final result = await Navigator.push<List<SelectedMenuItem>>(
      context,
      MaterialPageRoute(
        builder: (_) => MenuItemPicker(initialSelection: _selectedMenuItems),
      ),
    );

    if (result != null) {
      setState(() => _selectedMenuItems = result);
    }
  }

  // --------------------------------------------------------
  // 最终提交
  // --------------------------------------------------------
  Future<void> _submit() async {
    if (!_validateCurrentStep()) return;

    setState(() => _isSubmitting = true);

    try {
      final notifier = ref.read(dealsProvider.notifier);
      final merchantId = notifier.merchantId;

      // 获取商家类别
      final storeInfo = ref.read(storeProvider).valueOrNull;
      final category = storeInfo?.category ?? 'Other';

      // 计算过期时间
      DateTime expiresAt;
      if (_validityType == ValidityType.fixedDate) {
        expiresAt = _endDate!;
      } else {
        // days_after_purchase: 设置远期过期（实际在购买时计算）
        expiresAt = DateTime.now().add(const Duration(days: 730));
      }

      // 构造 Deal 对象
      final deal = MerchantDeal(
        id:              widget.editDeal?.id ?? '',
        merchantId:      merchantId,
        title:           _titleController.text.trim(),
        description:     _descriptionController.text.trim(),
        category:        category,
        originalPrice:   _originalPrice,
        discountPrice:   _dealPrice!,
        stockLimit:      _isUnlimited ? -1 : int.parse(_stockController.text),
        totalSold:       widget.editDeal?.totalSold ?? 0,
        rating:          widget.editDeal?.rating ?? 0.0,
        reviewCount:     widget.editDeal?.reviewCount ?? 0,
        isActive:        false,
        dealStatus:      DealStatus.pending,
        packageContents: _packageContentsText,
        usageNotes:      _usageNotesController.text.trim(),
        validityType:    _validityType,
        expiresAt:       expiresAt,
        validityDays:    _validityType == ValidityType.daysAfterPurchase
            ? int.tryParse(_validityDaysController.text)
            : null,
        usageDays:       _selectedDays.toList(),
        maxPerPerson:    _maxPerPersonController.text.isNotEmpty
            ? int.tryParse(_maxPerPersonController.text)
            : null,
        isStackable:     _isStackable,
        dealCategoryId:  _selectedDealCategoryId,
        applicableMerchantIds: _isMultiStore && _selectedStoreIds.isNotEmpty
            ? _selectedStoreIds.toList()
            : null,
        // 门店预确认数据，格式：[{ store_id, pre_confirmed }]，传给 Edge Function 用于写 deal_applicable_stores
        storeConfirmations: _isMultiStore && _selectedStoreIds.isNotEmpty
            ? _selectedStoreIds.map((id) => {
                'store_id': id,
                'pre_confirmed': _confirmedStoreIds.contains(id),
              }).toList()
            : null,
        images:          widget.editDeal?.images ?? [],
        createdAt:       widget.editDeal?.createdAt ?? DateTime.now(),
        updatedAt:       DateTime.now(),
      );

      MerchantDeal savedDeal;

      if (widget.editDeal != null) {
        // 编辑模式：更新
        await notifier.updateDeal(deal);
        savedDeal = deal;
      } else {
        // 创建模式：先创建 Deal，再上传图片
        savedDeal = await notifier.createDeal(deal);

        // 上传图片（按顺序，第一张设为主图）
        for (int i = 0; i < _selectedImages.length; i++) {
          await notifier.uploadImage(
            dealId:    savedDeal.id,
            file:      _selectedImages[i],
            sortOrder: i,
            isPrimary: i == 0,
          );
        }
      }

      if (!mounted) return;

      // 成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deal submitted for review!'),
          backgroundColor: Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
        ),
      );

      context.pop();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to submit deal: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // --------------------------------------------------------
  // 图片选择
  // --------------------------------------------------------
  Future<void> _pickImage() async {
    if (_selectedImages.length >= 5) {
      _showSnack('Maximum 5 images allowed');
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );

    if (picked != null) {
      setState(() => _selectedImages.add(picked));
    }
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  // --------------------------------------------------------
  // Build
  // --------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editDeal != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Color(0xFF333333)),
          onPressed: () => context.pop(),
        ),
        title: Text(
          isEditing ? 'Edit Deal' : 'Create Deal',
          style: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // 禁用 overscroll 拉伸效果
      body: ScrollConfiguration(
        behavior: const ScrollBehavior().copyWith(overscroll: false),
        child: Stepper(
          currentStep: _currentStep,
          onStepTapped: (step) {
            // 允许向后导航（点击已完成的步骤）
            if (step < _currentStep) {
              setState(() => _currentStep = step);
            }
          },
          controlsBuilder: (context, details) {
            final isLast = _currentStep == 4;
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  // 继续/提交按钮
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () {
                              if (isLast) {
                                _submit();
                              } else {
                                if (_validateCurrentStep()) {
                                  setState(() => _currentStep++);
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B35),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
                              isLast ? 'Submit for Review' : 'Continue',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  if (_currentStep > 0) ...[
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () => setState(() => _currentStep--),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF666666),
                        side: const BorderSide(color: Color(0xFFDDDDDD)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                      ),
                      child: const Text('Back'),
                    ),
                  ],
                ],
              ),
            );
          },
          steps: [
            _buildStep1(),
            _buildStep2(),
            _buildStep3(),
            _buildStep4(),
            _buildStep5(),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Step 1: 基本信息
  // ============================================================
  Step _buildStep1() {
    // 从 storeProvider 获取商家类别
    final storeAsync = ref.watch(storeProvider);
    final category = storeAsync.valueOrNull?.category ?? 'Loading...';

    return Step(
      title: const Text('Basic Info'),
      subtitle: const Text('Title, description and package'),
      isActive: _currentStep >= 0,
      state: _currentStep > 0 ? StepState.complete : StepState.indexed,
      content: Form(
        key: _step1Key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            _buildTextField(
              controller: _titleController,
              label: 'Deal Title',
              hint: 'e.g. 2-Person BBQ Set for 2',
              maxLength: 100,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Title is required';
                if (v.trim().length < 5) return 'Title must be at least 5 characters';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 类别（只读，从注册时的类别继承）
            _sectionLabel('Category'),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.category_outlined,
                      size: 18, color: Color(0xFF999999)),
                  const SizedBox(width: 8),
                  Text(
                    category,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF555555),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.lock_outline,
                      size: 14, color: Color(0xFFBBBBBB)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Deal 分类选择
            _sectionLabel('Deal Category (Optional)'),
            const SizedBox(height: 6),
            _buildDealCategoryDropdown(),
            const SizedBox(height: 16),

            // 描述
            _buildTextField(
              controller: _descriptionController,
              label: 'Description',
              hint: 'Describe what customers will get...',
              maxLines: 4,
              maxLength: 500,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Description is required';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 套餐内容（从菜品选择器选择）
            _sectionLabel('Package Contents'),
            const SizedBox(height: 8),
            _buildPackageContentsSection(),
            const SizedBox(height: 16),

            // 使用须知
            _buildTextField(
              controller: _usageNotesController,
              label: 'Usage Notes (Optional)',
              hint: 'e.g. Reservation required 24 hours in advance',
              maxLines: 3,
              maxLength: 500,
            ),
          ],
        ),
      ),
    );
  }

  // 套餐内容区域
  // Deal 分类下拉选择器
  Widget _buildDealCategoryDropdown() {
    final categoriesAsync = ref.watch(dealCategoriesProvider);
    return categoriesAsync.when(
      loading: () => const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => const Text('Failed to load categories',
          style: TextStyle(color: Colors.red, fontSize: 13)),
      data: (categories) {
        if (categories.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: const Text(
              'No categories yet. Manage in Deals page.',
              style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
            ),
          );
        }
        return DropdownButtonFormField<String?>(
          value: _selectedDealCategoryId,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
          ),
          hint: const Text('Select a category', style: TextStyle(fontSize: 14)),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('None', style: TextStyle(color: Color(0xFF999999))),
            ),
            ...categories.map((c) => DropdownMenuItem<String?>(
                  value: c.id,
                  child: Text(c.name),
                )),
          ],
          onChanged: (value) => setState(() => _selectedDealCategoryId = value),
        );
      },
    );
  }

  Widget _buildPackageContentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 已选菜品列表
        if (_selectedMenuItems.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._selectedMenuItems.map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${s.quantity}× ${s.menuItem.name}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF333333),
                          ),
                        ),
                      ),
                      Text(
                        '\$${s.subtotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ],
                  ),
                )),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total (Original Price)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF666666),
                      ),
                    ),
                    Text(
                      '\$${_originalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFF6B35),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        // 选择/修改按钮
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openMenuItemPicker,
            icon: Icon(
              _selectedMenuItems.isEmpty ? Icons.add : Icons.edit_outlined,
              size: 18,
            ),
            label: Text(
              _selectedMenuItems.isEmpty
                  ? 'Select Menu Items'
                  : 'Change Selection',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF6B35),
              side: const BorderSide(color: Color(0xFFFF6B35)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // Step 2: 价格
  // ============================================================
  Step _buildStep2() {
    final discountPercent = (_originalPrice > 0 && _dealPrice != null && _dealPrice! < _originalPrice)
        ? ((1 - _dealPrice! / _originalPrice) * 100).round()
        : null;

    return Step(
      title: const Text('Pricing'),
      subtitle: const Text('Set deal price'),
      isActive: _currentStep >= 1,
      state: _currentStep > 1 ? StepState.complete : StepState.indexed,
      content: Form(
        key: _step2Key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 原价（自动计算，只读展示）
            _sectionLabel('Original Price (from selected items)'),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Text(
                _originalPrice > 0
                    ? '\$${_originalPrice.toStringAsFixed(2)}'
                    : 'Select items first',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _originalPrice > 0
                      ? const Color(0xFF333333)
                      : const Color(0xFF999999),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 折扣百分比标签
            if (discountPercent != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$discountPercent% OFF',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 现价（手动输入）
            TextFormField(
              initialValue: _dealPrice?.toStringAsFixed(2),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              decoration: _inputDecoration(
                label: 'Deal Price',
                hint: '0.00',
              ).copyWith(prefixText: '\$ '),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Deal price is required';
                final price = double.tryParse(v);
                if (price == null || price <= 0) return 'Enter a valid price';
                if (_originalPrice > 0 && price >= _originalPrice) {
                  return 'Must be less than original price';
                }
                return null;
              },
              onChanged: (v) {
                setState(() => _dealPrice = double.tryParse(v));
              },
            ),

            const SizedBox(height: 12),
            const Text(
              'Tip: Set a competitive deal price to attract more customers.',
              style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Step 3: 库存和有效期
  // ============================================================
  Step _buildStep3() {
    return Step(
      title: const Text('Stock & Validity'),
      subtitle: const Text('Quantity and expiration'),
      isActive: _currentStep >= 2,
      state: _currentStep > 2 ? StepState.complete : StepState.indexed,
      content: Form(
        key: _step3Key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 库存 ---
            _sectionLabel('Stock Quantity'),
            const SizedBox(height: 8),

            // 无限制 Toggle
            Row(
              children: [
                Switch(
                  value: _isUnlimited,
                  activeThumbColor: const Color(0xFFFF6B35),
                  onChanged: (v) => setState(() => _isUnlimited = v),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Unlimited',
                  style: TextStyle(fontSize: 14, color: Color(0xFF333333)),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 库存数量输入（unlimited 时禁用）
            if (!_isUnlimited)
              TextFormField(
                controller: _stockController,
                enabled: !_isUnlimited,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (_isUnlimited) return null;
                  if (v == null || v.isEmpty) return 'Stock quantity is required';
                  final qty = int.tryParse(v);
                  if (qty == null || qty < 1) return 'Must be at least 1';
                  return null;
                },
                decoration: _inputDecoration(
                  label: 'Stock Quantity',
                  hint: 'e.g. 50',
                ),
              ),

            const SizedBox(height: 24),

            // --- 有效期 ---
            _sectionLabel('Validity Period'),
            const SizedBox(height: 8),

            // 有效期类型选择
            Row(
              children: [
                _ValidityTypeChip(
                  label: 'Fixed Date',
                  selected: _validityType == ValidityType.fixedDate,
                  onTap: () => setState(() => _validityType = ValidityType.fixedDate),
                ),
                const SizedBox(width: 8),
                _ValidityTypeChip(
                  label: 'Days After Purchase',
                  selected: _validityType == ValidityType.daysAfterPurchase,
                  onTap: () => setState(
                    () => _validityType = ValidityType.daysAfterPurchase,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 根据有效期类型显示对应输入
            if (_validityType == ValidityType.fixedDate)
              _buildDateRangePicker()
            else
              _buildDaysAfterPurchaseInput(),

            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Color(0xFFF57C00)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _validityType == ValidityType.daysAfterPurchase
                          ? 'Expired deals will be automatically refunded. DealJoy\'s customer guarantee.'
                          : 'Deals purchased before expiry but not used will be automatically refunded.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFF57C00),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangePicker() {
    return Column(
      children: [
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _endDate ?? DateTime.now().add(const Duration(days: 30)),
              firstDate: DateTime.now().add(const Duration(days: 1)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: Color(0xFFFF6B35),
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (picked != null) {
              setState(() => _endDate = picked);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF999999)),
                const SizedBox(width: 10),
                Text(
                  _endDate != null
                      ? 'Expires: ${_endDate!.month}/${_endDate!.day}/${_endDate!.year}'
                      : 'Select expiry date',
                  style: TextStyle(
                    fontSize: 14,
                    color: _endDate != null
                        ? const Color(0xFF333333)
                        : const Color(0xFF999999),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDaysAfterPurchaseInput() {
    return TextFormField(
      controller: _validityDaysController,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: (v) {
        if (_validityType != ValidityType.daysAfterPurchase) return null;
        if (v == null || v.isEmpty) return 'Number of days is required';
        final days = int.tryParse(v);
        if (days == null || days < 1 || days > 365) {
          return 'Must be between 1 and 365 days';
        }
        return null;
      },
      decoration: _inputDecoration(
        label: 'Valid for (days)',
        hint: 'e.g. 30',
      ).copyWith(
        suffixText: 'days after purchase',
        suffixStyle: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
      ),
    );
  }

  // ============================================================
  // Step 4: 使用规则
  // ============================================================
  Step _buildStep4() {
    return Step(
      title: const Text('Usage Rules'),
      subtitle: const Text('Days, limits and stacking'),
      isActive: _currentStep >= 3,
      state: _currentStep > 3 ? StepState.complete : StepState.indexed,
      content: Form(
        key: _step4Key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 可用日期（多选）
            _sectionLabel('Available Days (leave empty for all days)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _dayOptions.map((day) {
                final selected = _selectedDays.contains(day);
                return FilterChip(
                  label: Text(day),
                  selected: selected,
                  selectedColor: const Color(0xFFFF6B35),
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF555555),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  backgroundColor: const Color(0xFFF5F5F5),
                  side: BorderSide(
                    color: selected
                        ? const Color(0xFFFF6B35)
                        : const Color(0xFFE0E0E0),
                  ),
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedDays.add(day);
                      } else {
                        _selectedDays.remove(day);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // 每人限用数量
            _buildTextField(
              controller: _maxPerPersonController,
              label: 'Max Per Person (Optional)',
              hint: 'Leave empty for no limit',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                final n = int.tryParse(v);
                if (n == null || n < 1 || n > 99) {
                  return 'Must be between 1 and 99';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 是否可叠加
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Allow Stacking',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF333333),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Can be used with other promotions',
                        style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
                      ),
                    ],
                  ),
                  Switch(
                    value: _isStackable,
                    activeThumbColor: const Color(0xFFFF6B35),
                    onChanged: (v) => setState(() => _isStackable = v),
                  ),
                ],
              ),
            ),

            // 多店适用（仅连锁店显示）
            _buildMultiStoreSection(),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 多店适用选择（仅连锁店品牌管理员显示）
  // ============================================================
  Widget _buildMultiStoreSection() {
    final storeInfo = ref.watch(storeProvider).valueOrNull;
    final isChain = storeInfo?.isChainStore ?? false;
    if (!isChain) return const SizedBox.shrink();

    final storesAsync = ref.watch(brandStoresProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _sectionLabel('Applicable Stores'),
        const SizedBox(height: 8),
        // 切换: 仅本店 / 多店通用
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Multiple Locations',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF333333),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Available at other store locations',
                        style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
                      ),
                    ],
                  ),
                  Switch(
                    key: const ValueKey('deal_scope_multi_store_btn'),
                    value: _isMultiStore,
                    activeThumbColor: const Color(0xFFFF6B35),
                    onChanged: (v) => setState(() {
                      _isMultiStore = v;
                      if (!v) _selectedStoreIds.clear();
                    }),
                  ),
                ],
              ),
              // 门店勾选列表
              if (_isMultiStore)
                storesAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                      child: SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('Failed to load stores',
                        style: TextStyle(color: Colors.red[400], fontSize: 13)),
                  ),
                  data: (stores) {
                    if (stores.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('No other stores found',
                            style: TextStyle(fontSize: 13, color: Color(0xFF999999))),
                      );
                    }
                    return Column(
                      children: [
                        const Divider(height: 16),
                        // 说明文字
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Select stores and confirm which locations carry this item. '
                            'Confirmed locations go live immediately after platform review. '
                            'Unconfirmed locations receive a pending notification.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF666666),
                            ),
                          ),
                        ),
                        // 全选按钮
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  if (_selectedStoreIds.length == stores.length) {
                                    _selectedStoreIds.clear();
                                  } else {
                                    _selectedStoreIds.addAll(
                                      stores.map((s) => s.id),
                                    );
                                  }
                                });
                              },
                              child: Text(
                                _selectedStoreIds.length == stores.length
                                    ? 'Deselect All'
                                    : 'Select All',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFFFF6B35),
                                ),
                              ),
                            ),
                          ],
                        ),
                        ...stores.map((store) {
                              final isSelected = _selectedStoreIds.contains(store.id);
                              final isConfirmed = _confirmedStoreIds.contains(store.id);
                              return Column(
                                children: [
                                  CheckboxListTile(
                                    key: ValueKey('deal_store_checkbox_${store.id}'),
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    activeColor: const Color(0xFFFF6B35),
                                    title: Text(store.name,
                                        style: const TextStyle(fontSize: 14)),
                                    subtitle: store.address != null &&
                                            store.address!.isNotEmpty
                                        ? Text(store.address!,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF999999)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis)
                                        : null,
                                    value: isSelected,
                                    onChanged: (v) {
                                      setState(() {
                                        if (v == true) {
                                          _selectedStoreIds.add(store.id);
                                        } else {
                                          _selectedStoreIds.remove(store.id);
                                          _confirmedStoreIds.remove(store.id);
                                        }
                                      });
                                    },
                                  ),
                                  // 选中后显示预确认行
                                  if (isSelected)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 16, bottom: 6, right: 4),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isConfirmed
                                                ? Icons.check_circle
                                                : Icons.radio_button_unchecked,
                                            size: 16,
                                            color: isConfirmed
                                                ? const Color(0xFF4CAF50)
                                                : const Color(0xFF999999),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () => setState(() {
                                                if (isConfirmed) {
                                                  _confirmedStoreIds.remove(store.id);
                                                } else {
                                                  _confirmedStoreIds.add(store.id);
                                                }
                                              }),
                                              child: Text(
                                                isConfirmed
                                                    ? 'Confirmed — carries this item'
                                                    : 'Tap to confirm this location carries this item',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isConfirmed
                                                      ? const Color(0xFF4CAF50)
                                                      : const Color(0xFF999999),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              );
                            }),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // Step 5: 图片上传
  // ============================================================
  Step _buildStep5() {
    return Step(
      title: const Text('Images'),
      subtitle: const Text('Upload 1-5 photos'),
      isActive: _currentStep >= 4,
      state: StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Upload 1 to 5 images. The first image will be the cover photo shown in listings.',
            style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
          ),
          const SizedBox(height: 16),

          // 图片预览网格
          if (_selectedImages.isNotEmpty) ...[
            SizedBox(
              height: 100,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedImages.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = _selectedImages.removeAt(oldIndex);
                    _selectedImages.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final file = _selectedImages[index];
                  return _ImagePreviewTile(
                    key: ValueKey(file.path),
                    file: file,
                    index: index,
                    isPrimary: index == 0,
                    onRemove: () => _removeImage(index),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 添加图片按钮
          if (_selectedImages.length < 5)
            InkWell(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFDDDDDD),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 32,
                      color: _selectedImages.isEmpty
                          ? const Color(0xFFFF6B35)
                          : const Color(0xFF999999),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _selectedImages.isEmpty
                          ? 'Add Cover Image'
                          : 'Add More Photos (${_selectedImages.length}/5)',
                      style: TextStyle(
                        fontSize: 13,
                        color: _selectedImages.isEmpty
                            ? const Color(0xFFFF6B35)
                            : const Color(0xFF999999),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 说明文字
          const SizedBox(height: 12),
          const Text(
            'Tip: Drag to reorder images. The leftmost image is the cover.',
            style: TextStyle(fontSize: 12, color: Color(0xFFBBBBBB)),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 辅助 Widget 构建方法
  // ============================================================
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int? maxLines,
    int? maxLength,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    FormFieldValidator<String>? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines ?? 1,
      maxLength: maxLength,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
      decoration: _inputDecoration(label: label, hint: hint ?? ''),
    );
  }

  /// 统一输入框样式
  InputDecoration _inputDecoration({required String label, required String hint}) {
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
        borderSide: const BorderSide(color: Color(0xFFFF6B35), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE53935)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF555555),
      ),
    );
  }
}

// ============================================================
// 有效期类型选择 Chip
// ============================================================
class _ValidityTypeChip extends StatelessWidget {
  const _ValidityTypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF6B35) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFFFF6B35) : const Color(0xFFE0E0E0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 图片预览卡片（可拖拽重排）
// ============================================================
class _ImagePreviewTile extends StatelessWidget {
  const _ImagePreviewTile({
    super.key,
    required this.file,
    required this.index,
    required this.isPrimary,
    required this.onRemove,
  });

  final XFile file;
  final int index;
  final bool isPrimary;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      margin: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          // 图片
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(file.path),
              width: 88,
              height: 88,
              fit: BoxFit.cover,
            ),
          ),

          // 主图标签
          if (isPrimary)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Cover',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

          // 删除按钮
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Color(0xFF333333),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
