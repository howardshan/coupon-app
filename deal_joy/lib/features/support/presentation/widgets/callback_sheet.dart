import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/support_provider.dart';

/// 回拨请求底部弹窗
class CallbackSheet extends ConsumerStatefulWidget {
  /// 预填的电话号码（来自用户 profile）
  final String? initialPhone;

  const CallbackSheet({super.key, this.initialPhone});

  @override
  ConsumerState<CallbackSheet> createState() => _CallbackSheetState();
}

class _CallbackSheetState extends ConsumerState<CallbackSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phoneCtrl;
  final _descCtrl = TextEditingController();
  String _selectedSlot = 'morning';
  bool _submitting = false;

  static const _timeSlots = [
    ('morning', 'Morning', '9am – 12pm'),
    ('afternoon', 'Afternoon', '12 – 5pm'),
    ('evening', 'Evening', '5 – 9pm'),
  ];

  @override
  void initState() {
    super.initState();
    _phoneCtrl = TextEditingController(
      text: widget.initialPhone != 'skipped' ? (widget.initialPhone ?? '') : '',
    );
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      await ref.read(supportRepositoryProvider).submitCallbackRequest(
        phone: _phoneCtrl.text.trim(),
        timeSlot: _selectedSlot,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request submitted! We\'ll call you back soon.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖拽指示条
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 标题
            const Text(
              'Request a Call Back',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Leave your number and we\'ll call you back.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),

            // 电话号码
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                hintText: 'e.g. +1 234 567 8900',
                prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Please enter your phone number';
                if (v.trim().length < 7) return 'Please enter a valid phone number';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 时间段选择
            const Text(
              'Preferred Time',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _timeSlots.map((slot) {
                final isSelected = _selectedSlot == slot.$1;
                return ChoiceChip(
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(slot.$2),
                      Text(
                        slot.$3,
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected ? Colors.white70 : AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  onSelected: (_) => setState(() => _selectedSlot = slot.$1),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // 问题描述（可选）
            TextFormField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Describe your issue (optional)',
                alignLabelWithHint: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 提交按钮
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
