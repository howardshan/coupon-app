// Deal编辑页面（概览模式）
// 以卡片形式展示已有数据，点击某个区块可展开编辑
// 与 DealCreatePage 的 Stepper 模式分开，提供更好的编辑体验

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
// DealEditPage — Deal编辑页面（概览+点击展开编辑）
// ============================================================
class DealEditPage extends ConsumerStatefulWidget {
  const DealEditPage({super.key, required this.deal});

  final MerchantDeal deal;

  @override
  ConsumerState<DealEditPage> createState() => _DealEditPageState();
}

class _DealEditPageState extends ConsumerState<DealEditPage> {
  static const _orange = Color(0xFFFF6B35);

  // 哪个区块正在编辑（null=都不在编辑，显示概览）
  String? _editingSection;

  // Step 1: 基本信息
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _usageNotesController;
  List<SelectedMenuItem> _selectedMenuItems = [];
  String? _selectedDealCategoryId;

  // Step 2: 价格
  late final TextEditingController _dealPriceController;

  // Step 3: 库存和有效期
  late final TextEditingController _stockController;
  late final TextEditingController _validityDaysController;
  bool _isUnlimited = false;
  ValidityType _validityType = ValidityType.fixedDate;
  DateTime? _endDate;

  // Step 4: 使用规则
  late final TextEditingController _maxPerPersonController;
  final Set<String> _selectedDays = {};
  bool _isStackable = true;

  // Step 5: 图片
  final List<XFile> _newImages = [];

  bool _isSubmitting = false;
  final _formKey = GlobalKey<FormState>();

  static const _dayOptions = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // 计算原价
  double get _originalPrice {
    // 编辑模式优先用已有原价（因为可能没有选中菜品数据）
    if (_selectedMenuItems.isEmpty) return widget.deal.originalPrice;
    return _selectedMenuItems.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  // 生成套餐内容文本
  String get _packageContentsText {
    if (_selectedMenuItems.isEmpty) return widget.deal.packageContents;
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
    final deal = widget.deal;

    _titleController = TextEditingController(text: deal.title);
    _descriptionController = TextEditingController(text: deal.description);
    _usageNotesController = TextEditingController(text: deal.usageNotes);
    _dealPriceController = TextEditingController(
      text: deal.discountPrice.toStringAsFixed(2),
    );
    _stockController = TextEditingController(
      text: deal.isUnlimited ? '' : deal.stockLimit.toString(),
    );
    _validityDaysController = TextEditingController(
      text: deal.validityDays?.toString() ?? '',
    );
    _maxPerPersonController = TextEditingController(
      text: deal.maxPerPerson?.toString() ?? '',
    );

    _selectedDealCategoryId = deal.dealCategoryId;
    _isUnlimited = deal.isUnlimited;
    _validityType = deal.validityType;
    _endDate = deal.expiresAt;
    _isStackable = deal.isStackable;
    if (deal.usageDays.isNotEmpty) {
      _selectedDays.addAll(deal.usageDays);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _usageNotesController.dispose();
    _dealPriceController.dispose();
    _stockController.dispose();
    _validityDaysController.dispose();
    _maxPerPersonController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------
  // 提交更新
  // --------------------------------------------------------
  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    try {
      final notifier = ref.read(dealsProvider.notifier);
      final storeInfo = ref.read(storeProvider).valueOrNull;
      final category = storeInfo?.category ?? widget.deal.category;

      // 计算过期时间
      DateTime expiresAt;
      if (_validityType == ValidityType.fixedDate) {
        expiresAt = _endDate ?? widget.deal.expiresAt;
      } else {
        expiresAt = DateTime.now().add(const Duration(days: 730));
      }

      final dealPrice = double.tryParse(_dealPriceController.text) ??
          widget.deal.discountPrice;

      final deal = MerchantDeal(
        id: widget.deal.id,
        merchantId: widget.deal.merchantId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: category,
        originalPrice: _originalPrice,
        discountPrice: dealPrice,
        stockLimit: _isUnlimited ? -1 : (int.tryParse(_stockController.text) ?? widget.deal.stockLimit),
        totalSold: widget.deal.totalSold,
        rating: widget.deal.rating,
        reviewCount: widget.deal.reviewCount,
        isActive: false,
        dealStatus: DealStatus.pending,
        packageContents: _packageContentsText,
        usageNotes: _usageNotesController.text.trim(),
        validityType: _validityType,
        expiresAt: expiresAt,
        validityDays: _validityType == ValidityType.daysAfterPurchase
            ? int.tryParse(_validityDaysController.text)
            : null,
        usageDays: _selectedDays.toList(),
        maxPerPerson: _maxPerPersonController.text.isNotEmpty
            ? int.tryParse(_maxPerPersonController.text)
            : null,
        isStackable: _isStackable,
        dealCategoryId: _selectedDealCategoryId,
        images: widget.deal.images,
        createdAt: widget.deal.createdAt,
        updatedAt: DateTime.now(),
      );

      await notifier.updateDeal(deal);

      // 上传新图片（如有）
      if (_newImages.isNotEmpty) {
        for (int i = 0; i < _newImages.length; i++) {
          await notifier.uploadImage(
            dealId: widget.deal.id,
            file: _newImages[i],
            sortOrder: widget.deal.images.length + i,
            isPrimary: widget.deal.images.isEmpty && i == 0,
          );
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deal updated and submitted for review!'),
          backgroundColor: Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
        ),
      );

      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // 打开菜品选择器
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

  // 选择图片
  Future<void> _pickImage() async {
    final totalImages = widget.deal.images.length + _newImages.length;
    if (totalImages >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 5 images allowed'),
          backgroundColor: Color(0xFFE53935),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
      setState(() => _newImages.add(picked));
    }
  }

  // --------------------------------------------------------
  // Build
  // --------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF333333)),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Edit Deal',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 提示：修改后需重新审核
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Color(0xFFF57C00)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Changes will be submitted for review before going live.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFF57C00)),
                    ),
                  ),
                ],
              ),
            ),

            // 1. 基本信息
            _buildSection(
              sectionKey: 'basic',
              icon: Icons.info_outlined,
              title: 'Basic Info',
              summaryBuilder: _buildBasicInfoSummary,
              editBuilder: _buildBasicInfoEdit,
            ),

            const SizedBox(height: 12),

            // 2. 价格
            _buildSection(
              sectionKey: 'pricing',
              icon: Icons.attach_money_rounded,
              title: 'Pricing',
              summaryBuilder: _buildPricingSummary,
              editBuilder: _buildPricingEdit,
            ),

            const SizedBox(height: 12),

            // 3. 库存和有效期
            _buildSection(
              sectionKey: 'stock',
              icon: Icons.inventory_2_outlined,
              title: 'Stock & Validity',
              summaryBuilder: _buildStockSummary,
              editBuilder: _buildStockEdit,
            ),

            const SizedBox(height: 12),

            // 4. 使用规则
            _buildSection(
              sectionKey: 'rules',
              icon: Icons.rule_outlined,
              title: 'Usage Rules',
              summaryBuilder: _buildRulesSummary,
              editBuilder: _buildRulesEdit,
            ),

            const SizedBox(height: 12),

            // 5. 图片
            _buildSection(
              sectionKey: 'images',
              icon: Icons.photo_library_outlined,
              title: 'Images',
              summaryBuilder: _buildImagesSummary,
              editBuilder: _buildImagesEdit,
            ),

            const SizedBox(height: 24),

            // 保存按钮
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _orange,
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
                    : const Text(
                        'Save & Submit for Review',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 通用可展开区块
  // ============================================================
  Widget _buildSection({
    required String sectionKey,
    required IconData icon,
    required String title,
    required Widget Function() summaryBuilder,
    required Widget Function() editBuilder,
  }) {
    final isEditing = _editingSection == sectionKey;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEditing ? _orange.withOpacity(0.3) : const Color(0xFFE8E8E8),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏（点击切换编辑状态）
          InkWell(
            onTap: () {
              setState(() {
                _editingSection = isEditing ? null : sectionKey;
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: _orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  // 编辑/收起按钮
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isEditing
                          ? _orange.withOpacity(0.1)
                          : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isEditing ? Icons.check_rounded : Icons.edit_outlined,
                          size: 14,
                          color: isEditing ? _orange : const Color(0xFF666666),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isEditing ? 'Done' : 'Edit',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isEditing ? _orange : const Color(0xFF666666),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 内容区域
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: isEditing ? editBuilder() : summaryBuilder(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 1. 基本信息 — 概览
  // ============================================================
  Widget _buildBasicInfoSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryRow('Title', _titleController.text),
        _summaryRow('Description', _descriptionController.text),
        if (widget.deal.packageContents.isNotEmpty)
          _summaryRow('Package', _selectedMenuItems.isNotEmpty
              ? _packageContentsText
              : widget.deal.packageContents),
        if (_usageNotesController.text.isNotEmpty)
          _summaryRow('Usage Notes', _usageNotesController.text),
      ],
    );
  }

  // 1. 基本信息 — 编辑
  Widget _buildBasicInfoEdit() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField(
            controller: _titleController,
            label: 'Deal Title',
            hint: 'e.g. 2-Person BBQ Set',
            maxLength: 100,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _descriptionController,
            label: 'Description',
            hint: 'Describe what customers will get...',
            maxLines: 4,
            maxLength: 500,
          ),
          const SizedBox(height: 12),
          // 套餐内容
          _sectionLabel('Package Contents'),
          const SizedBox(height: 8),
          if (widget.deal.packageContents.isNotEmpty &&
              _selectedMenuItems.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Text(
                widget.deal.packageContents,
                style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
              ),
            ),
          if (_selectedMenuItems.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Column(
                children: [
                  ..._selectedMenuItems.map((s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${s.quantity}× ${s.menuItem.name}',
                            style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
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
                ],
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openMenuItemPicker,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Change Package Items'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _orange,
                side: const BorderSide(color: _orange),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Deal 分类下拉框
          _buildDealCategoryDropdown(),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _usageNotesController,
            label: 'Usage Notes (Optional)',
            hint: 'e.g. Reservation required 24 hours in advance',
            maxLines: 3,
            maxLength: 500,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 2. 价格 — 概览
  // ============================================================
  Widget _buildPricingSummary() {
    final dealPrice = double.tryParse(_dealPriceController.text) ?? widget.deal.discountPrice;
    final percent = (_originalPrice > 0 && dealPrice < _originalPrice)
        ? ((1 - dealPrice / _originalPrice) * 100).round()
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryRow('Original Price', '\$${_originalPrice.toStringAsFixed(2)}'),
        Row(
          children: [
            Expanded(child: _summaryRow('Deal Price', '\$${dealPrice.toStringAsFixed(2)}')),
            if (percent != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _orange,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$percent% OFF',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // 2. 价格 — 编辑
  Widget _buildPricingEdit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Original Price'),
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
            '\$${_originalPrice.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF333333),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _dealPriceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
          ],
          decoration: _inputDecoration(
            label: 'Deal Price',
            hint: '0.00',
          ).copyWith(prefixText: '\$ '),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  // ============================================================
  // 3. 库存和有效期 — 概览
  // ============================================================
  Widget _buildStockSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryRow(
          'Stock',
          _isUnlimited
              ? 'Unlimited'
              : '${_stockController.text.isNotEmpty ? _stockController.text : widget.deal.stockLimit}',
        ),
        _summaryRow('Validity Type', _validityType.displayLabel),
        if (_validityType == ValidityType.fixedDate && _endDate != null)
          _summaryRow(
            'Expires',
            '${_endDate!.month}/${_endDate!.day}/${_endDate!.year}',
          ),
        if (_validityType == ValidityType.daysAfterPurchase)
          _summaryRow(
            'Valid For',
            '${_validityDaysController.text.isNotEmpty ? _validityDaysController.text : '-'} days after purchase',
          ),
      ],
    );
  }

  // 3. 库存和有效期 — 编辑
  Widget _buildStockEdit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Stock Quantity'),
        const SizedBox(height: 8),
        Row(
          children: [
            Switch(
              value: _isUnlimited,
              activeThumbColor: _orange,
              onChanged: (v) => setState(() => _isUnlimited = v),
            ),
            const SizedBox(width: 8),
            const Text('Unlimited',
                style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
          ],
        ),
        if (!_isUnlimited) ...[
          const SizedBox(height: 8),
          _buildTextField(
            controller: _stockController,
            label: 'Stock Quantity',
            hint: 'e.g. 50',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ],
        const SizedBox(height: 16),
        _sectionLabel('Validity Period'),
        const SizedBox(height: 8),
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
        if (_validityType == ValidityType.fixedDate)
          _buildDatePicker()
        else
          _buildTextField(
            controller: _validityDaysController,
            label: 'Valid for (days)',
            hint: 'e.g. 30',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
      ],
    );
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _endDate ?? DateTime.now().add(const Duration(days: 30)),
          firstDate: DateTime.now().add(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(primary: _orange),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) setState(() => _endDate = picked);
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
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: Color(0xFF999999)),
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
    );
  }

  // ============================================================
  // 4. 使用规则 — 概览
  // ============================================================
  Widget _buildRulesSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryRow(
          'Available Days',
          _selectedDays.isEmpty ? 'All Days' : _selectedDays.join(', '),
        ),
        _summaryRow(
          'Max Per Person',
          _maxPerPersonController.text.isNotEmpty
              ? _maxPerPersonController.text
              : 'No Limit',
        ),
        _summaryRow('Stacking', _isStackable ? 'Allowed' : 'Not Allowed'),
      ],
    );
  }

  // 4. 使用规则 — 编辑
  Widget _buildRulesEdit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              selectedColor: _orange,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                color: selected ? Colors.white : const Color(0xFF555555),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              backgroundColor: const Color(0xFFF5F5F5),
              side: BorderSide(
                color: selected ? _orange : const Color(0xFFE0E0E0),
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
        const SizedBox(height: 16),
        _buildTextField(
          controller: _maxPerPersonController,
          label: 'Max Per Person (Optional)',
          hint: 'Leave empty for no limit',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 12),
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
                activeThumbColor: _orange,
                onChanged: (v) => setState(() => _isStackable = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 5. 图片 — 概览
  // ============================================================
  Widget _buildImagesSummary() {
    final totalImages = widget.deal.images.length + _newImages.length;
    if (totalImages == 0) {
      return const Text(
        'No images uploaded',
        style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // 已有图片
              ...widget.deal.images.map((img) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    img.imageUrl,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 80,
                      height: 80,
                      color: const Color(0xFFEEEEEE),
                      child: const Icon(Icons.broken_image, color: Color(0xFFCCCCCC)),
                    ),
                  ),
                ),
              )),
              // 新选择的图片
              ..._newImages.map((file) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(file.path),
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
              )),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$totalImages image${totalImages > 1 ? 's' : ''}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
        ),
      ],
    );
  }

  // 5. 图片 — 编辑
  Widget _buildImagesEdit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 已有图片
        if (widget.deal.images.isNotEmpty) ...[
          _sectionLabel('Current Images'),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: widget.deal.images.length,
              itemBuilder: (_, index) {
                final img = widget.deal.images[index];
                return Container(
                  width: 88,
                  height: 88,
                  margin: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          img.imageUrl,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 88,
                            height: 88,
                            color: const Color(0xFFEEEEEE),
                            child: const Icon(Icons.broken_image,
                                color: Color(0xFFCCCCCC)),
                          ),
                        ),
                      ),
                      if (img.isPrimary)
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: _orange,
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
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 新选择的图片
        if (_newImages.isNotEmpty) ...[
          _sectionLabel('New Images'),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _newImages.length,
              itemBuilder: (_, index) {
                return Container(
                  width: 88,
                  height: 88,
                  margin: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(_newImages[index].path),
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _newImages.removeAt(index)),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Color(0xFF333333),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 添加图片按钮
        if (widget.deal.images.length + _newImages.length < 5)
          InkWell(
            onTap: _pickImage,
            child: Container(
              width: double.infinity,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFDDDDDD)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_photo_alternate_outlined,
                      size: 28, color: _orange),
                  const SizedBox(height: 4),
                  Text(
                    'Add Photo (${widget.deal.images.length + _newImages.length}/5)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ============================================================
  // 辅助方法
  // ============================================================

  // 概览行
  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF999999),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF333333),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int? maxLines,
    int? maxLength,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines ?? 1,
      maxLength: maxLength,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
      decoration: _inputDecoration(label: label, hint: hint ?? ''),
      onChanged: (_) => setState(() {}),
    );
  }

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
        borderSide: const BorderSide(color: _orange, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
    );
  }

  // Deal 分类下拉选择器
  Widget _buildDealCategoryDropdown() {
    final categoriesAsync = ref.watch(dealCategoriesProvider);
    return categoriesAsync.when(
      loading: () => const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const Text('Failed to load categories',
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
            labelText: 'Deal Category',
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
// 有效期类型选择 Chip（复用）
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
