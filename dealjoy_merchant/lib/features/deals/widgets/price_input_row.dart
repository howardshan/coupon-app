// 价格输入行 Widget
// 原价/现价双输入框，实时计算并显示折扣百分比

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================
// PriceInputRow — 原价/现价输入行（StatefulWidget）
// 回调: onOriginalPriceChanged, onDealPriceChanged
// ============================================================
class PriceInputRow extends StatefulWidget {
  const PriceInputRow({
    super.key,
    this.initialOriginalPrice,
    this.initialDealPrice,
    required this.onOriginalPriceChanged,
    required this.onDealPriceChanged,
    this.enabled = true,
  });

  /// 初始原价（编辑时回填）
  final double? initialOriginalPrice;

  /// 初始现价（编辑时回填）
  final double? initialDealPrice;

  final ValueChanged<double?> onOriginalPriceChanged;
  final ValueChanged<double?> onDealPriceChanged;
  final bool enabled;

  @override
  State<PriceInputRow> createState() => _PriceInputRowState();
}

class _PriceInputRowState extends State<PriceInputRow> {
  late final TextEditingController _originalController;
  late final TextEditingController _dealController;

  double? _originalPrice;
  double? _dealPrice;

  @override
  void initState() {
    super.initState();
    _originalPrice = widget.initialOriginalPrice;
    _dealPrice = widget.initialDealPrice;

    _originalController = TextEditingController(
      text: widget.initialOriginalPrice?.toStringAsFixed(2) ?? '',
    );
    _dealController = TextEditingController(
      text: widget.initialDealPrice?.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void dispose() {
    _originalController.dispose();
    _dealController.dispose();
    super.dispose();
  }

  /// 计算折扣百分比
  int? get _discountPercent {
    if (_originalPrice == null || _dealPrice == null) return null;
    if (_originalPrice! <= 0) return null;
    if (_dealPrice! >= _originalPrice!) return null;
    return ((1 - _dealPrice! / _originalPrice!) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final discount = _discountPercent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 折扣百分比标签（实时显示）
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: discount != null
              ? Container(
                  key: ValueKey(discount),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$discount% OFF',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (discount != null) const SizedBox(height: 12),

        // 价格输入行（原价 + 现价并排）
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 原价输入框
            Expanded(
              child: _PriceField(
                controller: _originalController,
                label: 'Original Price',
                hint: '0.00',
                enabled: widget.enabled,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Required';
                  }
                  final price = double.tryParse(value);
                  if (price == null || price <= 0) {
                    return 'Invalid price';
                  }
                  return null;
                },
                onChanged: (value) {
                  setState(() {
                    _originalPrice = double.tryParse(value);
                  });
                  widget.onOriginalPriceChanged(_originalPrice);
                },
              ),
            ),
            const SizedBox(width: 12),

            // 现价输入框
            Expanded(
              child: _PriceField(
                controller: _dealController,
                label: 'Deal Price',
                hint: '0.00',
                enabled: widget.enabled,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Required';
                  }
                  final price = double.tryParse(value);
                  if (price == null || price <= 0) {
                    return 'Invalid price';
                  }
                  if (_originalPrice != null && price >= _originalPrice!) {
                    return 'Must be < original';
                  }
                  return null;
                },
                onChanged: (value) {
                  setState(() {
                    _dealPrice = double.tryParse(value);
                  });
                  widget.onDealPriceChanged(_dealPrice);
                },
              ),
            ),
          ],
        ),

        // 价格逻辑错误提示
        if (_originalPrice != null &&
            _dealPrice != null &&
            _dealPrice! >= _originalPrice!) ...[
          const SizedBox(height: 6),
          const Text(
            'Deal price must be less than original price',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFE53935),
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// 单个价格输入框（内部 Widget）
// ============================================================
class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onChanged,
    this.validator,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;
  final FormFieldValidator<String>? validator;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        // 只允许数字和一个小数点
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
      ],
      validator: validator,
      onChanged: onChanged,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1A1A1A),
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        // 美元符号前缀
        prefixText: '\$ ',
        prefixStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF555555),
        ),
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
      ),
    );
  }
}
