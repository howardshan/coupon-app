import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/merchant_after_sales_request.dart';
import '../providers/after_sales_providers.dart';

class AfterSalesDetailPage extends ConsumerStatefulWidget {
  const AfterSalesDetailPage({super.key, required this.requestId});

  final String requestId;

  @override
  ConsumerState<AfterSalesDetailPage> createState() => _AfterSalesDetailPageState();
}

class _AfterSalesDetailPageState extends ConsumerState<AfterSalesDetailPage> {
  bool _isActioning = false;

  @override
  Widget build(BuildContext context) {
    final requestAsync = ref.watch(afterSalesDetailProvider(widget.requestId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('After-Sales Detail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(afterSalesDetailProvider(widget.requestId).notifier).refresh(),
          ),
        ],
      ),
      body: requestAsync.when(
        data: (request) => RefreshIndicator(
          onRefresh: () => ref.read(afterSalesDetailProvider(widget.requestId).notifier).refresh(),
          color: const Color(0xFFFF6B35),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryCard(request: request),
              if (request.merchantOrderContext?.hasAnyContext == true) ...[
                const SizedBox(height: 16),
                _MerchantOrderContextCard(
                  contextInfo: request.merchantOrderContext!,
                ),
              ],
              const SizedBox(height: 16),
              _AttachmentSection(title: 'User attachments', attachments: request.userAttachments),
              if (request.merchantAttachments.isNotEmpty) ...[
                const SizedBox(height: 16),
                _AttachmentSection(title: 'Merchant attachments', attachments: request.merchantAttachments),
              ],
              if (request.platformAttachments.isNotEmpty) ...[
                const SizedBox(height: 16),
                _AttachmentSection(title: 'Platform attachments', attachments: request.platformAttachments),
              ],
              const SizedBox(height: 16),
              _TimelineCard(entries: request.timeline),
              const SizedBox(height: 32),
              if (request.awaitingAction)
                _DecisionButtons(
                  isLoading: _isActioning,
                  onApprove: () => _handleApprove(request.id),
                  onReject: () => _handleReject(request.id),
                ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: error.toString(),
          onRetry: () => ref.read(afterSalesDetailProvider(widget.requestId).notifier).refresh(),
        ),
      ),
    );
  }

  Future<void> _handleApprove(String requestId) async {
    final result = await _collectDecisionNote(
      title: 'Approve request',
      hint: 'Explain why the refund is approved',
      minLength: 5,
      requireEvidence: false,
    );
    if (result == null) return;

    setState(() => _isActioning = true);
    try {
      final repo = ref.read(merchantAfterSalesRepositoryProvider);
      await repo.approve(requestId: requestId, note: result.note);
      await _refreshAfterAction();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request approved and refunded.')),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approve failed: $err')),
      );
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  Future<void> _handleReject(String requestId) async {
    final result = await _collectDecisionNote(
      title: 'Reject request',
      hint: 'Add a clear reason (min 10 characters)',
      minLength: 10,
      requireEvidence: true,
    );
    if (result == null) return;

    setState(() => _isActioning = true);
    try {
      final repo = ref.read(merchantAfterSalesRepositoryProvider);
      await repo.reject(
        requestId: requestId,
        note: result.note,
        attachments: result.attachments,
      );
      await _refreshAfterAction();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rejection submitted and sent to customer.')),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reject failed: $err')),
      );
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  Future<void> _refreshAfterAction() async {
    ref.invalidate(afterSalesDetailProvider(widget.requestId));
    await ref.read(afterSalesListProvider.notifier).refresh();
  }

  Future<_DecisionInput?> _collectDecisionNote({
    required String title,
    required String hint,
    required int minLength,
    required bool requireEvidence,
  }) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final attachments = <String>[];
    final picker = ImagePicker();

    _DecisionInput? result;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> pickEvidence() async {
                if (attachments.length >= 3) return;
                final sheetCtx = context;
                final choice = await showModalBottomSheet<String>(
                  context: sheetCtx,
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.photo_library_outlined),
                          title: const Text('Photo from gallery'),
                          onTap: () => Navigator.pop(ctx, 'image'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.picture_as_pdf_outlined),
                          title: const Text('PDF document'),
                          onTap: () => Navigator.pop(ctx, 'pdf'),
                        ),
                      ],
                    ),
                  ),
                );
                if (!sheetCtx.mounted) return;
                if (choice == null) return;

                final repo = ref.read(merchantAfterSalesRepositoryProvider);
                final messenger = ScaffoldMessenger.of(sheetCtx);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Uploading evidence…')),
                );
                try {
                  late final String remotePath;
                  if (choice == 'image') {
                    final file = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 2000,
                    );
                    if (!sheetCtx.mounted) return;
                    if (file == null) return;
                    remotePath = await repo.uploadEvidence(file);
                  } else if (choice == 'pdf') {
                    final res = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['pdf'],
                      withData: true,
                    );
                    if (!sheetCtx.mounted) return;
                    if (res == null || res.files.isEmpty) return;
                    final pf = res.files.single;
                    // withData: true 保证移动端/Web 均可拿到字节，避免依赖 dart:io（Web 构建）
                    final Uint8List? bytes = pf.bytes;
                    if (bytes == null || bytes.isEmpty) {
                      if (!sheetCtx.mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Could not read PDF file')),
                      );
                      return;
                    }
                    var name = pf.name.trim().isNotEmpty ? pf.name.trim() : 'evidence.pdf';
                    if (!name.toLowerCase().endsWith('.pdf')) {
                      name = '$name.pdf';
                    }
                    remotePath = await repo.uploadEvidenceBytes(
                      filename: name,
                      bytes: bytes,
                      mimeType: 'application/pdf',
                    );
                  } else {
                    return;
                  }
                  if (!sheetCtx.mounted) return;
                  setModalState(() => attachments.add(remotePath));
                } catch (err) {
                  if (!sheetCtx.mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text('Upload failed: $err')),
                  );
                }
              }

              bool canSubmit() {
                if (controller.text.trim().length < minLength) return false;
                if (requireEvidence && attachments.isEmpty) return false;
                return true;
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: hint,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: attachments.length >= 3 ? null : pickEvidence,
                        icon: const Icon(Icons.attachment_outlined),
                        label: Text('Add photo or PDF (${attachments.length}/3)'),
                      ),
                      const SizedBox(width: 8),
                      if (attachments.isNotEmpty)
                        TextButton(
                          onPressed: () => setModalState(attachments.clear),
                          child: const Text('Clear all'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (attachments.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      children: attachments
                          .map(
                            (path) => Chip(
                              avatar: const Icon(Icons.insert_drive_file_outlined, size: 16),
                              label: Text(path.split('/').last),
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: canSubmit()
                          ? () {
                              result = _DecisionInput(note: controller.text.trim(), attachments: List.of(attachments));
                              Navigator.of(context).pop();
                            }
                          : null,
                      child: const Text('Submit'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    controller.dispose();
    focusNode.dispose();
    return result;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.request});

  final MerchantAfterSalesRequest request;

  @override
  Widget build(BuildContext context) {
    final amountFmt = NumberFormat.simpleCurrency();
    final statusLabel = request.status.replaceAll('_', ' ').toUpperCase();
    final expires = request.expiresAt != null
        ? DateFormat('MMM d, HH:mm').format(request.expiresAt!.toLocal())
        : '—';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.userDisplayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Customer (masked)',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      request.reasonDetail,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              _StatusPill(statusLabel: statusLabel),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Refund amount', style: TextStyle(color: Colors.black54)),
                    Text(amountFmt.format(request.refundAmount), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SLA deadline', style: TextStyle(color: Colors.black54)),
                    Text(expires, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          if (request.createdAt != null) ...[
            const Divider(height: 28),
            _SummaryTimeRow(
              label: 'Request submitted',
              dateTime: request.createdAt!,
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryTimeRow extends StatelessWidget {
  const _SummaryTimeRow({required this.label, required this.dateTime});

  final String label;
  final DateTime dateTime;

  @override
  Widget build(BuildContext context) {
    final formatted =
        DateFormat('MMM d, yyyy · HH:mm').format(dateTime.toLocal());
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            formatted,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ),
      ],
    );
  }
}

/// 订单/Deal/券上下文 + 跳转入口（不含用户全名）
class _MerchantOrderContextCard extends StatelessWidget {
  const _MerchantOrderContextCard({required this.contextInfo});

  final MerchantOrderContext contextInfo;

  static String _fmt(DateTime dt) =>
      DateFormat('MMM d, yyyy · HH:mm').format(dt.toLocal());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order & voucher',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          if (contextInfo.orderCreatedAt != null)
            _CtxRow(
              label: 'Order placed',
              value: _fmt(contextInfo.orderCreatedAt!),
            ),
          if (contextInfo.orderPaidAt != null)
            _CtxRow(
              label: 'Paid at',
              value: _fmt(contextInfo.orderPaidAt!),
            ),
          if (contextInfo.orderNumber != null &&
              contextInfo.orderNumber!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 132,
                    child: Text(
                      'Order #',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contextInfo.orderNumber!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        if (contextInfo.orderId != null &&
                            contextInfo.orderId!.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => context.push(
                                '/orders/${contextInfo.orderId}',
                              ),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                foregroundColor: scheme.primary,
                              ),
                              child: const Text('View order details'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if ((contextInfo.dealTitle != null &&
                  contextInfo.dealTitle!.isNotEmpty) ||
              (contextInfo.dealId != null &&
                  contextInfo.dealId!.isNotEmpty)) ...[
            if (contextInfo.dealTitle != null &&
                contextInfo.dealTitle!.isNotEmpty)
              _CtxRow(label: 'Deal', value: contextInfo.dealTitle!),
            if (contextInfo.dealSummary != null &&
                contextInfo.dealSummary!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 132, bottom: 8),
                child: Text(
                  contextInfo.dealSummary!.trim(),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            if (contextInfo.dealId != null && contextInfo.dealId!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 132, bottom: 8),
                child: TextButton(
                  onPressed: () =>
                      context.push('/deals/${contextInfo.dealId}'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: scheme.primary,
                  ),
                  child: const Text('View deal details'),
                ),
              ),
          ],
          if (contextInfo.couponCodeTail != null &&
              contextInfo.couponCodeTail!.isNotEmpty)
            _CtxRow(label: 'Voucher code', value: contextInfo.couponCodeTail!),
          if (contextInfo.redeemedAt != null)
            _CtxRow(
              label: 'Verified / redeemed',
              value: _fmt(contextInfo.redeemedAt!),
            ),
        ],
      ),
    );
  }
}

class _CtxRow extends StatelessWidget {
  const _CtxRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentSection extends StatelessWidget {
  const _AttachmentSection({required this.title, required this.attachments});

  final String title;
  final List<String> attachments;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: attachments
              .map(
                (url) => _AttachmentPreview(url: url),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    // signed URL 末尾是 ?token=xxx，需用 path 判断扩展名
    final path = Uri.tryParse(url)?.path ?? url;
    final lower = path.toLowerCase();
    final isImage = lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
    final isPdf = lower.endsWith('.pdf');
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          image: isImage
              ? DecorationImage(
                  image: NetworkImage(url),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: isImage
            ? null
            : Center(
                child: Icon(
                  isPdf ? Icons.picture_as_pdf_outlined : Icons.insert_drive_file_outlined,
                  color: Colors.black54,
                  size: 40,
                ),
              ),
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.entries});

  final List<AfterSalesTimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Text('Timeline not available yet.'),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Timeline', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...entries.map((entry) => _TimelineTile(entry: entry)),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.entry});

  final AfterSalesTimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('MMM d, HH:mm').format(entry.timestamp.toLocal());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(Icons.check_circle, size: 18, color: Color(0xFF0F62FE)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.status.replaceAll('_', ' ').toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${entry.actor} · $dateLabel', style: const TextStyle(color: Colors.black54)),
                if (entry.note?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(entry.note!),
                  ),
                // 附件统一在上方 User attachments 区打开，避免与 Timeline 重复入口
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DecisionButtons extends StatelessWidget {
  const _DecisionButtons({
    required this.isLoading,
    required this.onApprove,
    required this.onReject,
  });

  final bool isLoading;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FilledButton.icon(
          onPressed: isLoading ? null : onApprove,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Approve & Refund'),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: isLoading ? null : onReject,
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Reject with evidence'),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.statusLabel});

  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE0E7FF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        statusLabel,
        style: const TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecisionInput {
  const _DecisionInput({required this.note, this.attachments = const []});

  final String note;
  final List<String> attachments;
}
