import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../data/models/after_sales_request_model.dart';
import '../../domain/providers/after_sales_provider.dart';
import 'after_sales_screen_args.dart';

class AfterSalesRequestFormPage extends ConsumerStatefulWidget {
  const AfterSalesRequestFormPage({super.key, required this.args});

  final AfterSalesScreenArgs args;

  @override
  ConsumerState<AfterSalesRequestFormPage> createState() => _AfterSalesRequestFormPageState();
}

class _AfterSalesRequestFormPageState extends ConsumerState<AfterSalesRequestFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _detailController = TextEditingController();
  AfterSalesReason _reason = AfterSalesReason.badExperience;
  final _attachments = <XFile>[];
  bool _isSubmitting = false;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = NumberFormat.simpleCurrency().format(widget.args.totalAmount);
    return Scaffold(
      appBar: AppBar(title: const Text('After-Sales Request')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OrderSummary(args: widget.args, amount: amount),
              const SizedBox(height: 16),
              _InfoBanner(usedAt: widget.args.couponUsedAt),
              const SizedBox(height: 24),
              Text('Reason', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<AfterSalesReason>(
                value: _reason,
                items: AfterSalesReason.values
                    .map((reason) => DropdownMenuItem(value: reason, child: Text(reason.label)))
                    .toList(),
                onChanged: (value) => setState(() => _reason = value ?? AfterSalesReason.badExperience),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 24),
              Text('Details', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              TextFormField(
                controller: _detailController,
                maxLines: 5,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: 'Describe what happened during your visit. These details go to the merchant reviewer.',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().length < 20) {
                    return 'Please provide at least 20 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Attachments (optional)', style: Theme.of(context).textTheme.titleSmall),
                  Text('${_attachments.length}/3', style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ..._attachments.map((file) => _AttachmentPreview(file: file, onRemove: () => _removeAttachment(file))),
                  if (_attachments.length < 3)
                    GestureDetector(
                      onTap: _pickAttachment,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.surfaceVariant),
                        ),
                        child: const Icon(Icons.add_a_photo_outlined, color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              AppButton(
                label: 'Submit Request',
                icon: Icons.send_outlined,
                isLoading: _isSubmitting,
                onPressed: _isSubmitting ? null : _submit,
              ),
              const SizedBox(height: 12),
              AppButton(
                label: 'Cancel',
                isOutlined: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAttachment() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (file != null) {
      setState(() => _attachments.add(file));
    }
  }

  void _removeAttachment(XFile file) {
    setState(() => _attachments.remove(file));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(afterSalesRepositoryProvider);
      final uploadPaths = <String>[];
      for (final file in _attachments) {
        final path = await repo.uploadEvidence(file);
        uploadPaths.add(path);
      }
      final submitted = await repo.submitRequest(
        orderId: widget.args.orderId,
        couponId: widget.args.couponId,
        reason: _reason,
        detail: _detailController.text.trim(),
        attachmentPaths: uploadPaths,
      );
      // 提交接口已返回完整 request；写入乐观缓存，避免返回时间线时 GET 尚未查到而空白
      ref
          .read(afterSalesOptimisticProvider(widget.args.orderId).notifier)
          .state = submitted;
      ref.invalidate(afterSalesRequestProvider(widget.args.orderId));
      ref.invalidate(afterSalesListProvider(widget.args.orderId));
      ref.invalidate(afterSalesListProvider(null));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('After-sales request submitted. We will notify you soon.')),
      );
      Navigator.of(context).pop();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit: $err')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.args, required this.amount});

  final AfterSalesScreenArgs args;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(args.dealTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (args.merchantName != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(args.merchantName!, style: const TextStyle(color: AppColors.textSecondary)),
            ),
          const SizedBox(height: 8),
          Text('Order ID: ${args.orderId}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (args.couponCode != null)
            Text('Coupon: ${args.couponCode}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('Amount: $amount', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({this.usedAt});

  final DateTime? usedAt;

  @override
  Widget build(BuildContext context) {
    final text = usedAt == null
        ? 'After-sales window: within 7 days of redemption. Please describe what happened at the merchant.'
        : 'Redeemed on ${DateFormat.yMMMd().format(usedAt!.toLocal())}. You can submit after-sales requests within 7 days.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.info),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.file, required this.onRemove});

  final XFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(file.path),
            width: 96,
            height: 96,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
