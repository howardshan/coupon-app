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
import '../../menu/providers/menu_provider.dart';

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
  late final TextEditingController _shortNameController;
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
  // 使用规则标签列表
  late List<String> _usageRules;
  // 每账户限购输入框
  late final TextEditingController _maxPerAccountController;

  // 核销后小费（可选）
  bool _tipsEnabled = false;
  String _tipsMode = 'percent';
  late final TextEditingController _tipsP1Controller;
  late final TextEditingController _tipsP2Controller;
  late final TextEditingController _tipsP3Controller;

  // 多店适用（仅连锁店显示）
  bool _isMultiStore = false;
  final Set<String> _selectedStoreIds = {};

  // 选项组（"几选几"功能）
  late List<DealOptionGroup> _optionGroups;

  // Step 5: 图片
  final List<XFile> _newImages = [];
  // 使用须知附图（已有 URL + 新增文件）
  late List<String> _existingUsageNoteImageUrls;
  final List<XFile> _newUsageNoteImageFiles = [];
  // 竖版详情图（已有 URL + 新增文件）
  late List<String> _existingDetailImageUrls;
  final List<XFile> _newDetailImageFiles = [];

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

  /// 与 package 一致：未重选菜品时保留原 dishes，避免 toJson 发 [] 覆盖克隆行
  List<String> get _dishesPayload {
    if (_selectedMenuItems.isEmpty) {
      return List<String>.from(widget.deal.dishes);
    }
    return _selectedMenuItems
        .map((s) {
          final name = s.menuItem.name;
          final qty = s.quantity;
          final subtotal = ((s.menuItem.price ?? 0) * qty).toStringAsFixed(0);
          return '$name::$qty::$subtotal';
        })
        .toList();
  }

  @override
  void initState() {
    super.initState();
    final deal = widget.deal;

    _titleController = TextEditingController(text: deal.title);
    _shortNameController = TextEditingController(text: deal.shortName ?? '');
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
    // 每账户限购：-1 表示无限制，显示为空
    _maxPerAccountController = TextEditingController(
      text: deal.maxPerAccount > 0 ? deal.maxPerAccount.toString() : '',
    );

    _selectedDealCategoryId = deal.dealCategoryId;
    _isUnlimited = deal.isUnlimited;
    _validityType = deal.validityType;
    _endDate = deal.expiresAt;
    _isStackable = deal.isStackable;
    if (deal.usageDays.isNotEmpty) {
      _selectedDays.addAll(deal.usageDays);
    }
    // 多店适用回填
    if (deal.applicableMerchantIds != null &&
        deal.applicableMerchantIds!.isNotEmpty) {
      _isMultiStore = true;
      _selectedStoreIds.addAll(deal.applicableMerchantIds!);
    }
    // 选项组回填
    _optionGroups = List.of(deal.optionGroups);
    // 使用规则回填
    _usageRules = List.of(deal.usageRules);
    _tipsEnabled = deal.tipsEnabled;
    _tipsMode = deal.tipsMode ?? 'percent';
    _tipsP1Controller = TextEditingController(
      text: _fmtTipPreset(deal.tipsPreset1),
    );
    _tipsP2Controller = TextEditingController(
      text: _fmtTipPreset(deal.tipsPreset2),
    );
    _tipsP3Controller = TextEditingController(
      text: _fmtTipPreset(deal.tipsPreset3),
    );
    // 使用须知附图回填
    _existingUsageNoteImageUrls = List.of(deal.usageNoteImages);
    // 竖版详情图回填
    _existingDetailImageUrls = List.of(deal.detailImages);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _shortNameController.dispose();
    _descriptionController.dispose();
    _usageNotesController.dispose();
    _dealPriceController.dispose();
    _stockController.dispose();
    _validityDaysController.dispose();
    _maxPerPersonController.dispose();
    _maxPerAccountController.dispose();
    _tipsP1Controller.dispose();
    _tipsP2Controller.dispose();
    _tipsP3Controller.dispose();
    super.dispose();
  }

  String _fmtTipPreset(double? v) {
    if (v == null) return '';
    if (v % 1 == 0) return v.toInt().toString();
    return v.toString();
  }

  // --------------------------------------------------------
  // 提交更新
  // --------------------------------------------------------
  // 判断是否只修改了库存
  bool _isStockOnlyChange() {
    final old = widget.deal;
    final newStock = _isUnlimited ? -1 : (int.tryParse(_stockController.text) ?? old.stockLimit);
    if (newStock == old.stockLimit) return false; // 库存没变

    final dealPrice = double.tryParse(_dealPriceController.text) ?? old.discountPrice;
    // 检查其他字段是否有变化
    if (_titleController.text.trim() != old.title) return false;
    if (_descriptionController.text.trim() != old.description) return false;
    if (_originalPrice != old.originalPrice) return false;
    if (dealPrice != old.discountPrice) return false;
    if (_usageNotesController.text.trim() != (old.usageNotes ?? '')) return false;
    if (_packageContentsText != (old.packageContents ?? '')) return false;
    if (_validityType != old.validityType) return false;
    if (_isStackable != old.isStackable) return false;
    if (_tipsEnabled != old.tipsEnabled) return false;
    if (_tipsEnabled) {
      if (_tipsMode != (old.tipsMode ?? 'percent')) return false;
      if (_tipsP1Controller.text.trim() != _fmtTipPreset(old.tipsPreset1)) {
        return false;
      }
      if (_tipsP2Controller.text.trim() != _fmtTipPreset(old.tipsPreset2)) {
        return false;
      }
      if (_tipsP3Controller.text.trim() != _fmtTipPreset(old.tipsPreset3)) {
        return false;
      }
    }
    if (_newImages.isNotEmpty) return false; // 有新图片
    return true;
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    try {
      final notifier = ref.read(dealsProvider.notifier);

      // 仅修改库存：原地更新，不克隆不重审
      if (_isStockOnlyChange()) {
        final newStock = _isUnlimited ? -1 : (int.tryParse(_stockController.text) ?? widget.deal.stockLimit);
        await notifier.updateStockOnly(widget.deal.id, newStock);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stock updated successfully!'),
            backgroundColor: Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.pop();
        return;
      }

      // 其他修改：走克隆逻辑（后端处理）
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

      // 验证 shortName（必填，最多10字符）
      final shortNameText = _shortNameController.text.trim();
      if (shortNameText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Short name is required'),
            backgroundColor: Color(0xFFE53935),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isSubmitting = false);
        return;
      }
      if (shortNameText.length > 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Short name must be 10 characters or less'),
            backgroundColor: Color(0xFFE53935),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isSubmitting = false);
        return;
      }

      // 上传新增的使用须知附图
      final allUsageNoteUrls = List<String>.from(_existingUsageNoteImageUrls);
      if (_newUsageNoteImageFiles.isNotEmpty) {
        final service = ref.read(dealsServiceProvider);
        for (final file in _newUsageNoteImageFiles) {
          final url = await service.uploadUsageNoteImage(
            merchantId: widget.deal.merchantId,
            file: file,
          );
          allUsageNoteUrls.add(url);
        }
      }

      // 上传新增的竖版详情图
      final allDetailUrls = List<String>.from(_existingDetailImageUrls);
      if (_newDetailImageFiles.isNotEmpty) {
        final service = ref.read(dealsServiceProvider);
        for (final file in _newDetailImageFiles) {
          final url = await service.uploadDetailImage(
            merchantId: widget.deal.merchantId,
            dealId: widget.deal.id,
            file: file,
          );
          allDetailUrls.add(url);
        }
      }

      final deal = MerchantDeal(
        id: widget.deal.id,
        merchantId: widget.deal.merchantId,
        title: _titleController.text.trim(),
        shortName: shortNameText,
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
        usageNoteImages: allUsageNoteUrls,
        detailImages: allDetailUrls,
        validityType: _validityType,
        expiresAt: expiresAt,
        validityDays: (_validityType == ValidityType.shortAfterPurchase ||
                       _validityType == ValidityType.longAfterPurchase)
            ? int.tryParse(_validityDaysController.text)
            : null,
        usageDays: _selectedDays.toList(),
        maxPerPerson: _maxPerPersonController.text.isNotEmpty
            ? int.tryParse(_maxPerPersonController.text)
            : null,
        isStackable: _isStackable,
        dealCategoryId: _selectedDealCategoryId,
        applicableMerchantIds: _isMultiStore && _selectedStoreIds.isNotEmpty
            ? _selectedStoreIds.toList()
            : null,
        optionGroups: _optionGroups,
        // 使用规则和每账户限购
        usageRules: _usageRules,
        maxPerAccount: _maxPerAccountController.text.isNotEmpty
            ? (int.tryParse(_maxPerAccountController.text) ?? -1)
            : -1,
        tipsEnabled: _tipsEnabled,
        tipsMode: _tipsEnabled ? _tipsMode : null,
        tipsPreset1: _tipsEnabled && _tipsP1Controller.text.trim().isNotEmpty
            ? double.tryParse(_tipsP1Controller.text.trim())
            : null,
        tipsPreset2: _tipsEnabled && _tipsP2Controller.text.trim().isNotEmpty
            ? double.tryParse(_tipsP2Controller.text.trim())
            : null,
        tipsPreset3: _tipsEnabled && _tipsP3Controller.text.trim().isNotEmpty
            ? double.tryParse(_tipsP3Controller.text.trim())
            : null,
        dishes: _dishesPayload,
        images: widget.deal.images,
        createdAt: widget.deal.createdAt,
        updatedAt: DateTime.now(),
      );

      final newDeal = await notifier.updateDeal(deal);

      // 上传新图片到克隆后的新 deal（必须用服务端返回的 id）
      if (_newImages.isNotEmpty) {
        for (int i = 0; i < _newImages.length; i++) {
          await notifier.uploadImage(
            dealId: newDeal.id,
            file: _newImages[i],
            sortOrder: newDeal.images.length + i,
            isPrimary: newDeal.images.isEmpty && i == 0,
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

      // 克隆后旧 deal 已下架，回到列表页而非 detail 页
      final isBrandDeal = widget.deal.applicableMerchantIds != null &&
          widget.deal.applicableMerchantIds!.isNotEmpty;
      if (isBrandDeal) {
        context.go('/brand-manage/deals');
      } else {
        context.go('/deals');
      }
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

            // 4b. 小费（核销后）
            _buildSection(
              sectionKey: 'tipping',
              icon: Icons.volunteer_activism_outlined,
              title: 'Tipping (after redemption)',
              summaryBuilder: _buildTippingSummary,
              editBuilder: _buildTippingEdit,
            ),

            const SizedBox(height: 12),

            // 5. 选项组
            _buildSection(
              sectionKey: 'options',
              icon: Icons.checklist_outlined,
              title: 'Option Groups',
              summaryBuilder: _buildOptionGroupsSummary,
              editBuilder: _buildOptionGroupsEdit,
            ),

            const SizedBox(height: 12),

            // 6. 图片
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
                key: const ValueKey('deal_edit_submit_btn'),
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
        if (_shortNameController.text.isNotEmpty)
          _summaryRow('Short Name', _shortNameController.text),
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
            fieldKey: const ValueKey('deal_edit_title_field'),
            controller: _titleController,
            label: 'Deal Title',
            hint: 'e.g. 2-Person BBQ Set',
            maxLength: 100,
          ),
          const SizedBox(height: 12),

          // 短名称（最多10字符，用于变体选择器展示）
          _buildTextField(
            fieldKey: const ValueKey('deal_short_name_field'),
            controller: _shortNameController,
            label: 'Short Name (max 10 chars)',
            hint: 'Used in variant selector',
            maxLength: 10,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            fieldKey: const ValueKey('deal_edit_desc_field'),
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
            fieldKey: const ValueKey('deal_edit_usage_notes_field'),
            controller: _usageNotesController,
            label: 'Usage Notes (Optional)',
            hint: 'e.g. Reservation required 24 hours in advance',
            maxLines: 3,
            maxLength: 500,
          ),
          const SizedBox(height: 12),
          _buildUsageNoteImagesSection(),
        ],
      ),
    );
  }

  // 使用须知附图区域（编辑模式：已有 URL + 新增文件）
  Widget _buildUsageNoteImagesSection() {
    final totalCount = _existingUsageNoteImageUrls.length + _newUsageNoteImageFiles.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Usage Note Photos (Optional)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF333333)),
        ),
        const SizedBox(height: 4),
        const Text(
          'Add photos to help explain purchase/usage notes',
          style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // 已有的远程图片
            for (int i = 0; i < _existingUsageNoteImageUrls.length; i++)
              _usageNoteImageTile(
                child: Image.network(
                  _existingUsageNoteImageUrls[i],
                  width: 80, height: 80, fit: BoxFit.cover,
                ),
                onRemove: () => setState(() => _existingUsageNoteImageUrls.removeAt(i)),
              ),
            // 新选择的本地图片
            for (int i = 0; i < _newUsageNoteImageFiles.length; i++)
              _usageNoteImageTile(
                child: Image.file(
                  File(_newUsageNoteImageFiles[i].path),
                  width: 80, height: 80, fit: BoxFit.cover,
                ),
                onRemove: () => setState(() => _newUsageNoteImageFiles.removeAt(i)),
              ),
            // 添加按钮
            if (totalCount < 5)
              GestureDetector(
                onTap: () async {
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 1200,
                    maxHeight: 1200,
                    imageQuality: 85,
                  );
                  if (picked != null) {
                    setState(() => _newUsageNoteImageFiles.add(picked));
                  }
                },
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDDDDDD)),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 24, color: Color(0xFF999999)),
                      SizedBox(height: 2),
                      Text('Add', style: TextStyle(fontSize: 11, color: Color(0xFF999999))),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // 使用须知图片单元（带删除按钮）
  Widget _usageNoteImageTile({required Widget child, required VoidCallback onRemove}) {
    return Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
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
          key: const ValueKey('deal_edit_discount_price_field'),
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
        if (_validityType == ValidityType.shortAfterPurchase ||
            _validityType == ValidityType.longAfterPurchase)
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
            fieldKey: const ValueKey('deal_edit_stock_field'),
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ValidityTypeChip(
              label: 'Fixed Date',
              selected: _validityType == ValidityType.fixedDate,
              onTap: () => setState(() => _validityType = ValidityType.fixedDate),
            ),
            _ValidityTypeChip(
              label: 'Short-term',
              selected: _validityType == ValidityType.shortAfterPurchase,
              onTap: () => setState(() {
                _validityType = ValidityType.shortAfterPurchase;
                final days = int.tryParse(_validityDaysController.text) ?? 0;
                if (days > 7) _validityDaysController.clear();
              }),
            ),
            _ValidityTypeChip(
              label: 'Long-term',
              selected: _validityType == ValidityType.longAfterPurchase,
              onTap: () => setState(() {
                _validityType = ValidityType.longAfterPurchase;
                final days = int.tryParse(_validityDaysController.text) ?? 0;
                if (days > 0 && days < 8) _validityDaysController.clear();
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_validityType == ValidityType.fixedDate)
          _buildDatePicker()
        else
          _buildTextField(
            fieldKey: const ValueKey('deal_edit_validity_days_field'),
            controller: _validityDaysController,
            label: _validityType == ValidityType.shortAfterPurchase
                ? 'Valid for (1–7 days)'
                : 'Valid for (8–90 days)',
            hint: _validityType == ValidityType.shortAfterPurchase ? 'e.g. 3' : 'e.g. 30',
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
          lastDate: DateTime.now().add(const Duration(days: 90)), // 最�� 3 个月
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
        _summaryRow(
          'Max Per Account',
          _maxPerAccountController.text.isNotEmpty
              ? _maxPerAccountController.text
              : 'No Limit',
        ),
        if (_usageRules.isNotEmpty)
          _summaryRow('Usage Rules', _usageRules.join(', ')),
        if (_isMultiStore && _selectedStoreIds.isNotEmpty)
          _summaryRow('Locations', '${_selectedStoreIds.length} stores'),
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
          fieldKey: const ValueKey('deal_edit_max_per_person_field'),
          controller: _maxPerPersonController,
          label: 'Max Per Person (Optional)',
          hint: 'Leave empty for no limit',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 12),
        // 每账户限购数量
        _buildTextField(
          fieldKey: const ValueKey('deal_edit_max_per_account_field'),
          controller: _maxPerAccountController,
          label: 'Max Per Account (Optional)',
          hint: 'Leave empty for no limit',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 16),
        // 使用规则标签（多条文本，可添加/删除）
        _sectionLabel('Usage Rules (Optional)'),
        const SizedBox(height: 8),
        _buildUsageRulesInput(
          rules: _usageRules,
          onChanged: (rules) => setState(() => _usageRules = rules),
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
        // 多店适用选择（仅连锁店显示）
        _buildMultiStoreSection(),
      ],
    );
  }

  // 4b. 小费 — 概览
  Widget _buildTippingSummary() {
    if (!_tipsEnabled) {
      return const Text('Tips disabled', style: TextStyle(fontSize: 14, color: Color(0xFF666666)));
    }
    final mode = _tipsMode == 'fixed' ? 'Fixed (USD)' : 'Percent of purchase';
    final p1 = _tipsP1Controller.text.trim();
    final p2 = _tipsP2Controller.text.trim();
    final p3 = _tipsP3Controller.text.trim();
    final presets = [p1, p2, p3].where((s) => s.isNotEmpty).join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryRow('Tips', 'Enabled'),
        _summaryRow('Mode', mode),
        if (presets.isNotEmpty) _summaryRow('Presets', presets),
      ],
    );
  }

  // 4b. 小费 — 编辑
  Widget _buildTippingEdit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable optional tips after redemption'),
          value: _tipsEnabled,
          activeThumbColor: _orange,
          onChanged: (v) => setState(() => _tipsEnabled = v),
        ),
        if (_tipsEnabled) ...[
          const SizedBox(height: 8),
          const Text('Tip type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'percent', label: Text('Percent')),
              ButtonSegment(value: 'fixed', label: Text('Fixed USD')),
            ],
            selected: {_tipsMode},
            onSelectionChanged: (s) => setState(() => _tipsMode = s.first),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            fieldKey: const ValueKey('deal_edit_tips_p1'),
            controller: _tipsP1Controller,
            label: _tipsMode == 'percent' ? 'Preset 1 (%, e.g. 10)' : 'Preset 1 (USD)',
            hint: _tipsMode == 'percent' ? '10' : '2.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          ),
          const SizedBox(height: 8),
          _buildTextField(
            fieldKey: const ValueKey('deal_edit_tips_p2'),
            controller: _tipsP2Controller,
            label: _tipsMode == 'percent' ? 'Preset 2 (%)' : 'Preset 2 (USD)',
            hint: _tipsMode == 'percent' ? '15' : '3.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          ),
          const SizedBox(height: 8),
          _buildTextField(
            fieldKey: const ValueKey('deal_edit_tips_p3'),
            controller: _tipsP3Controller,
            label: _tipsMode == 'percent' ? 'Preset 3 (%)' : 'Preset 3 (USD)',
            hint: _tipsMode == 'percent' ? '20' : '5.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          ),
          const SizedBox(height: 8),
          Text(
            'Customers will also see a custom amount option (including \$0).',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ],
    );
  }

  // ============================================================
  // 使用规则标签输入组件（Chip 方式，可添加/删除多条规则）
  // ============================================================
  Widget _buildUsageRulesInput({
    required List<String> rules,
    required ValueChanged<List<String>> onChanged,
  }) {
    final controller = TextEditingController();
    return StatefulBuilder(
      builder: (context, setLocalState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 已添加的规则 Chip 列表
            if (rules.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: rules.map((rule) {
                  return Chip(
                    label: Text(
                      rule,
                      style: const TextStyle(fontSize: 13),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      final updated = List<String>.from(rules)..remove(rule);
                      onChanged(updated);
                    },
                    backgroundColor: const Color(0xFFFFF3EE),
                    side: const BorderSide(color: Color(0xFFFF6B35)),
                    labelStyle: const TextStyle(color: Color(0xFFFF6B35)),
                  );
                }).toList(),
              ),
            if (rules.isNotEmpty) const SizedBox(height: 8),
            // 输入框 + 添加按钮
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: 'e.g. No takeout, Reservation required',
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFAAAAAA),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
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
                        borderSide: const BorderSide(color: Color(0xFFFF6B35)),
                      ),
                    ),
                    onSubmitted: (val) {
                      final trimmed = val.trim();
                      if (trimmed.isEmpty || rules.contains(trimmed)) return;
                      final updated = List<String>.from(rules)..add(trimmed);
                      onChanged(updated);
                      controller.clear();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    final trimmed = controller.text.trim();
                    if (trimmed.isEmpty || rules.contains(trimmed)) return;
                    final updated = List<String>.from(rules)..add(trimmed);
                    onChanged(updated);
                    controller.clear();
                  },
                  icon: const Icon(Icons.add, size: 18, color: Color(0xFFFF6B35)),
                  label: const Text(
                    'Add',
                    style: TextStyle(color: Color(0xFFFF6B35)),
                  ),
                ),
              ],
            ),
          ],
        );
      },
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
        const SizedBox(height: 16),
        _sectionLabel('Applicable Stores'),
        const SizedBox(height: 8),
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
                    value: _isMultiStore,
                    activeThumbColor: _orange,
                    onChanged: (v) => setState(() {
                      _isMultiStore = v;
                      if (!v) _selectedStoreIds.clear();
                    }),
                  ),
                ],
              ),
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
                        ...stores.map((store) => CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              activeColor: _orange,
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
                              value: _selectedStoreIds.contains(store.id),
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selectedStoreIds.add(store.id);
                                  } else {
                                    _selectedStoreIds.remove(store.id);
                                  }
                                });
                              },
                            )),
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
  // 5. 选项组 — 概览
  // ============================================================
  Widget _buildOptionGroupsSummary() {
    if (_optionGroups.isEmpty) {
      return const Text(
        'No option groups',
        style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _optionGroups.map((g) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          '${g.name} — ${g.displayLabel}',
          style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
        ),
      )).toList(),
    );
  }

  // ============================================================
  // 5. 选项组 — 编辑
  // ============================================================
  Widget _buildOptionGroupsEdit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 已有选项组列表
        ..._optionGroups.asMap().entries.map((entry) {
          final idx = entry.key;
          final group = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${group.name} (${group.displayLabel})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _editOptionGroupInEditPage(idx),
                      child: const Icon(Icons.edit_outlined,
                          size: 18, color: Color(0xFFFF6B35)),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() =>
                          _optionGroups = List.of(_optionGroups)..removeAt(idx)),
                      child: const Icon(Icons.delete_outline,
                          size: 18, color: Color(0xFFE53935)),
                    ),
                  ],
                ),
                if (group.items.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...group.items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Text('• ', style: TextStyle(color: Color(0xFF666666))),
                        Expanded(child: Text(item.name,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF666666)))),
                        Text('\$${item.price.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
                      ],
                    ),
                  )),
                ],
              ],
            ),
          );
        }),
        // 添加按钮
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addOptionGroupInEditPage,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Option Group'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _orange,
              side: BorderSide(color: _orange),
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

  void _addOptionGroupInEditPage() {
    _showOptionGroupDialogEdit(
      onSave: (group) {
        setState(() => _optionGroups = [..._optionGroups, group]);
      },
    );
  }

  void _editOptionGroupInEditPage(int index) {
    _showOptionGroupDialogEdit(
      existingGroup: _optionGroups[index],
      onSave: (group) {
        setState(() {
          final updated = List<DealOptionGroup>.of(_optionGroups);
          updated[index] = group;
          _optionGroups = updated;
        });
      },
    );
  }

  // 选项组编辑弹窗（编辑页版本）
  void _showOptionGroupDialogEdit({
    DealOptionGroup? existingGroup,
    required void Function(DealOptionGroup) onSave,
  }) {
    final nameCtrl = TextEditingController(text: existingGroup?.name ?? '');
    final selectCountCtrl = TextEditingController(
        text: existingGroup?.selectMin.toString() ?? '1');
    List<DealOptionItem> items = existingGroup?.items.toList() ?? [];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existingGroup != null ? 'Edit Option Group' : 'Add Option Group'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Group Name',
                      hintText: 'e.g. Main Course',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: selectCountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Select Count',
                      hintText: 'e.g. 2',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 16),
                  const Text('Items', style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...items.asMap().entries.map((entry) {
                    final itemIdx = entry.key;
                    final item = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Text(item.name,
                              style: const TextStyle(fontSize: 13))),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: Text(
                              '\$${item.price.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 13))),
                          GestureDetector(
                            onTap: () => _showOptionItemEditDialogEdit(
                              existingItem: item,
                              onSave: (updated) {
                                setDialogState(() {
                                  items = List.of(items);
                                  items[itemIdx] = updated;
                                });
                              },
                            ),
                            child: const Icon(Icons.edit_outlined,
                                size: 16, color: Color(0xFF999999)),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => setDialogState(() =>
                                items = List.of(items)..removeAt(itemIdx)),
                            child: const Icon(Icons.close,
                                size: 16, color: Color(0xFFE53935)),
                          ),
                        ],
                      ),
                    );
                  }),
                  TextButton.icon(
                    onPressed: () => _showMenuItemSelectorForOptionEdit(
                      existingItems: items,
                      onSave: (item) {
                        setDialogState(() => items = [...items, item]);
                      },
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Item'),
                    style: TextButton.styleFrom(foregroundColor: _orange),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final count = int.tryParse(selectCountCtrl.text) ?? 1;
                if (count < 1) return;
                final sortedItems = items.asMap().entries.map((e) =>
                    e.value.copyWith(sortOrder: e.key)).toList();
                onSave(DealOptionGroup(
                  id: existingGroup?.id,
                  name: name,
                  selectMin: count,
                  selectMax: count,
                  sortOrder: 0,
                  items: sortedItems,
                ));
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // 从菜单中选择选项项（底部弹窗，编辑页版本）
  void _showMenuItemSelectorForOptionEdit({
    required List<DealOptionItem> existingItems,
    required void Function(DealOptionItem) onSave,
  }) {
    final existingNames = existingItems.map((e) => e.name).toSet();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.3,
          expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Select from Menu',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Consumer(builder: (_, cRef, __) {
                  final menuAsync = cRef.watch(activeMenuItemsProvider);
                  return menuAsync.when(
                    loading: () => const Center(
                        child: CircularProgressIndicator(color: Color(0xFFFF6B35))),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (items) {
                      if (items.isEmpty) {
                        return const Center(
                          child: Text('No active menu items',
                              style: TextStyle(color: Color(0xFF999999))),
                        );
                      }
                      return ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final item = items[i];
                          final alreadyAdded = existingNames.contains(item.name);
                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 44, height: 44,
                                child: item.imageUrl != null &&
                                        item.imageUrl!.isNotEmpty
                                    ? Image.network(item.imageUrl!,
                                        fit: BoxFit.cover)
                                    : Container(
                                        color: Colors.grey.shade100,
                                        child: const Icon(Icons.restaurant,
                                            size: 20, color: Colors.grey)),
                              ),
                            ),
                            title: Text(item.name,
                                style: const TextStyle(fontSize: 14)),
                            subtitle: Text(
                              item.price != null
                                  ? '\$${item.price!.toStringAsFixed(2)}'
                                  : 'No price',
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF666666)),
                            ),
                            trailing: alreadyAdded
                                ? const Icon(Icons.check_circle,
                                    color: Colors.green, size: 20)
                                : const Icon(Icons.add_circle_outline,
                                    color: Color(0xFFFF6B35), size: 20),
                            onTap: alreadyAdded
                                ? null
                                : () {
                                    onSave(DealOptionItem(
                                      name: item.name,
                                      price: item.price ?? 0,
                                    ));
                                    Navigator.pop(ctx);
                                  },
                          );
                        },
                      );
                    },
                  );
                  }),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 选项项编辑弹窗（仅编辑已有项，编辑页版本）
  void _showOptionItemEditDialogEdit({
    required DealOptionItem existingItem,
    required void Function(DealOptionItem) onSave,
  }) {
    final nameCtrl = TextEditingController(text: existingItem.name);
    final priceCtrl = TextEditingController(
        text: existingItem.price.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Item Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              decoration: const InputDecoration(
                labelText: 'Price',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final price = double.tryParse(priceCtrl.text) ?? 0;
              if (name.isEmpty) return;
              onSave(DealOptionItem(
                id: existingItem.id,
                name: name,
                price: price,
              ));
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 6. 图片 — 概览
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
        // 显示竖版详情图数量（如有）
        if (_existingDetailImageUrls.isNotEmpty ||
            _newDetailImageFiles.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '${_existingDetailImageUrls.length + _newDetailImageFiles.length} detail photo${(_existingDetailImageUrls.length + _newDetailImageFiles.length) > 1 ? 's' : ''}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
          ),
        ],
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

        // ---- 竖版详情图区域 ----
        const SizedBox(height: 20),
        const Divider(height: 1, color: Color(0xFFEEEEEE)),
        const SizedBox(height: 16),
        _buildDetailImagesSection(),
      ],
    );
  }

  // ============================================================
  // 竖版详情图区域（编辑模式：已有 URL + 新增文件）
  // ============================================================
  Widget _buildDetailImagesSection() {
    final totalCount =
        _existingDetailImageUrls.length + _newDetailImageFiles.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        Row(
          children: [
            const Icon(Icons.photo_size_select_actual_outlined,
                size: 18, color: _orange),
            const SizedBox(width: 6),
            const Text(
              'Detail Photos (Portrait)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Optional',
                style: TextStyle(fontSize: 10, color: Color(0xFFF57C00)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Max 5 portrait photos for deal detail page',
          style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // 已有的远程竖版图片
            for (int i = 0; i < _existingDetailImageUrls.length; i++)
              _detailImageTile(
                child: Image.network(
                  _existingDetailImageUrls[i],
                  width: 80,
                  height: 120,
                  fit: BoxFit.cover,
                ),
                onRemove: () =>
                    setState(() => _existingDetailImageUrls.removeAt(i)),
              ),
            // 新选的本地竖版图片
            for (int i = 0; i < _newDetailImageFiles.length; i++)
              _detailImageTile(
                child: Image.file(
                  File(_newDetailImageFiles[i].path),
                  width: 80,
                  height: 120,
                  fit: BoxFit.cover,
                ),
                onRemove: () =>
                    setState(() => _newDetailImageFiles.removeAt(i)),
              ),
            // 添加按钮
            if (totalCount < 5)
              GestureDetector(
                onTap: () async {
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 1200,
                    maxHeight: 2400,
                    imageQuality: 85,
                  );
                  if (picked != null) {
                    setState(() => _newDetailImageFiles.add(picked));
                  }
                },
                child: Container(
                  width: 80,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDDDDDD)),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined,
                          size: 24, color: Color(0xFF999999)),
                      SizedBox(height: 4),
                      Text('Add',
                          style:
                              TextStyle(fontSize: 11, color: Color(0xFF999999))),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // 竖版详情图单元（带删除按钮）
  Widget _detailImageTile({
    required Widget child,
    required VoidCallback onRemove,
  }) {
    return Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: const BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
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
    Key? fieldKey,
  }) {
    return TextFormField(
      key: fieldKey,
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
