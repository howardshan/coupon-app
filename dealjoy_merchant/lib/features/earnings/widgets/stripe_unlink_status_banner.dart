// Stripe 解绑申请状态条 + 申请底部表单（Sprint4）
// UI 文案英文

import 'package:flutter/material.dart';
import '../models/earnings_data.dart';

// =============================================================
// 根据列表展示最近一条或 pending 状态
// =============================================================
class StripeUnlinkRequestStatusBanner extends StatelessWidget {
  const StripeUnlinkRequestStatusBanner({
    super.key,
    required this.items,
  });

  final List<StripeUnlinkRequestItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final pending = items.where((e) => e.status == 'pending').toList();
    final first = pending.isNotEmpty
        ? pending.first
        : items.first;
    return _StatusBody(item: first, hasOlder: items.length > 1);
  }
}

class _StatusBody extends StatelessWidget {
  const _StatusBody({required this.item, required this.hasOlder});

  final StripeUnlinkRequestItem item;
  final bool hasOlder;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color border, Color text, IconData icon, String line1) =
        _resolve(item);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: text),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  line1,
                  style: TextStyle(
                    fontSize: 13,
                    color: text,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (item.status == 'rejected' &&
              (item.rejectedReason != null &&
                  item.rejectedReason!.trim().isNotEmpty)) ...[
            const SizedBox(height: 6),
            Text(
              item.rejectedReason!.trim(),
              style: TextStyle(
                fontSize: 12,
                color: text.withAlpha(220),
                height: 1.35,
              ),
            ),
          ],
          if (item.createdAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Submitted ${_formatDate(item.createdAt!)}',
              style: TextStyle(
                fontSize: 11,
                color: text.withAlpha(180),
              ),
            ),
          ],
          if (hasOlder) ...[
            const SizedBox(height: 4),
            Text(
              'Older requests are available in your history (last 20 shown on server).',
              style: TextStyle(
                fontSize: 11,
                color: text.withAlpha(160),
              ),
            ),
          ],
        ],
      ),
    );
  }

  (Color, Color, Color, IconData, String) _resolve(StripeUnlinkRequestItem o) {
    switch (o.status) {
      case 'pending':
        return (
          const Color(0xFFFF9800).withAlpha(22),
          const Color(0xFFFF9800).withAlpha(90),
          const Color(0xFFE65100),
          Icons.pending_actions_outlined,
          'A request to disconnect Stripe is pending review.',
        );
      case 'approved':
        return (
          const Color(0xFF4CAF50).withAlpha(20),
          const Color(0xFF4CAF50).withAlpha(70),
          const Color(0xFF2E7D32),
          Icons.verified_outlined,
          o.unbindAppliedAt != null
              ? 'Your disconnect request was approved. Changes are being applied on our side. Tap Refresh Status after processing completes.'
              : 'Your disconnect request was approved. You will receive a confirmation email when the account is unlinked on our side.',
        );
      case 'rejected':
        return (
          const Color(0xFFE53935).withAlpha(20),
          const Color(0xFFE53935).withAlpha(70),
          const Color(0xFFC62828),
          Icons.block_outlined,
          'Your disconnect request was declined.',
        );
      default:
        return (
          Colors.grey.shade200,
          Colors.grey.shade400,
          Colors.grey.shade800,
          Icons.info_outline,
          'Unlink request status: ${o.status}.',
        );
    }
  }

  String _formatDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}

// =============================================================
// 底部表单：可选说明 + 提交
// =============================================================
const int kStripeUnlinkNoteMaxLength = 2000;

/// cancel=true 表示用户点取消；否则携带可选备注（可为空串表示无说明）
typedef StripeUnlinkRequestSheetResult = ({bool cancel, String? note});

Future<StripeUnlinkRequestSheetResult?> showStripeUnlinkRequestSheet(
  BuildContext context, {
  String title = 'Request to Unlink Stripe',
  String? subtitle,
  String? confirmLabel,
}) {
  final cLabel = confirmLabel ?? 'Submit request';
  return showModalBottomSheet<StripeUnlinkRequestSheetResult?>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + bottom,
        ),
        child: _UnlinkRequestForm(
          title: title,
          subtitle: subtitle,
          confirmLabel: cLabel,
        ),
      );
    },
  );
}

class _UnlinkRequestForm extends StatefulWidget {
  const _UnlinkRequestForm({
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
  });

  final String title;
  final String? subtitle;
  final String confirmLabel;

  @override
  State<_UnlinkRequestForm> createState() => _UnlinkRequestFormState();
}

class _UnlinkRequestFormState extends State<_UnlinkRequestForm> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
        if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            widget.subtitle!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _c,
          onChanged: (_) => setState(() {}),
          maxLength: kStripeUnlinkNoteMaxLength,
          maxLines: 4,
          minLines: 2,
          decoration: InputDecoration(
            hintText: 'Optional note to DealJoy (e.g. why you are disconnecting)',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop(
                    (cancel: true, note: null),
                  );
                },
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  final t = _c.text.trim();
                  Navigator.of(context).pop(
                    (cancel: false, note: t.isEmpty ? null : t),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF635BFF),
                  foregroundColor: Colors.white,
                ),
                child: Text(widget.confirmLabel),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
