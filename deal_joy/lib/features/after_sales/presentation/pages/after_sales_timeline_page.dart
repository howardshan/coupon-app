import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../data/models/after_sales_request_model.dart';
import '../../domain/providers/after_sales_provider.dart';
import '../pages/after_sales_screen_args.dart';

class AfterSalesTimelinePage extends ConsumerStatefulWidget {
  const AfterSalesTimelinePage({super.key, required this.args});

  final AfterSalesScreenArgs args;

  @override
  ConsumerState<AfterSalesTimelinePage> createState() => _AfterSalesTimelinePageState();
}

class _AfterSalesTimelinePageState extends ConsumerState<AfterSalesTimelinePage> {
  bool _isEscalating = false;

  @override
  Widget build(BuildContext context) {
    final requestAsync = ref.watch(afterSalesRequestProvider(widget.args.orderId));
    return Scaffold(
      appBar: AppBar(title: const Text('After-Sales Support')),
      body: requestAsync.when(
        data: (request) => request == null ? _buildEmptyState(context) : _buildTimeline(context, request),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(error: error, onRetry: () => ref.invalidate(afterSalesRequestProvider(widget.args.orderId))),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.support_agent_outlined, size: 72, color: AppColors.textHint),
          const SizedBox(height: 18),
          const Text(
            'Need help after redemption?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'You can submit an after-sales request within 7 days of redeeming your coupon.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          AppButton(
            label: 'Start After-Sales Request',
            icon: Icons.post_add_outlined,
            onPressed: () => context.push(
              '/after-sales/${widget.args.orderId}/request',
              extra: widget.args,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(BuildContext context, AfterSalesRequestModel request) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(afterSalesRequestProvider(widget.args.orderId));
        await ref.read(afterSalesRequestProvider(widget.args.orderId).future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryCard(request: request, args: widget.args),
          const SizedBox(height: 16),
          _TimelineCard(entries: request.timeline),
          const SizedBox(height: 16),
          if (request.merchantFeedback?.isNotEmpty == true)
            _FeedbackCard(title: 'Merchant Response', body: request.merchantFeedback!, attachments: request.merchantAttachments),
          if (request.platformFeedback?.isNotEmpty == true) ...[
            const SizedBox(height: 16),
            _FeedbackCard(title: 'Crunchy Plum Decision', body: request.platformFeedback!, attachments: request.platformAttachments),
          ],
          const SizedBox(height: 32),
          if (request.merchantRejected && !request.awaitingPlatform && !request.completed)
            AppButton(
              label: 'Escalate to Crunchy Plum',
              icon: Icons.flag_outlined,
              isLoading: _isEscalating,
              onPressed: _isEscalating ? null : () => _confirmEscalate(request.id),
            ),
          if (!request.completed) ...[
            const SizedBox(height: 12),
            AppButton(
              label: 'Back to Order',
              isOutlined: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ] else
            AppButton(
              label: 'Back to Order',
              isOutlined: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 升级至平台前先确认，避免误触
  Future<void> _confirmEscalate(String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Escalate to Crunchy Plum?'),
        content: const Text(
          'This sends your refund case to the Crunchy Plum team for review. '
          'We typically respond within 24 hours. Tap Escalate only if you want to proceed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Escalate'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _escalate(requestId);
    }
  }

  Future<void> _escalate(String requestId) async {
    setState(() => _isEscalating = true);
    try {
      final repo = ref.read(afterSalesRepositoryProvider);
      await repo.escalate(requestId);
      ref.invalidate(afterSalesRequestProvider(widget.args.orderId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escalated to Crunchy Plum. We will review within 24 hours.')),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to escalate: $err')),
      );
    } finally {
      if (mounted) setState(() => _isEscalating = false);
    }
  }
}

/// 状态/原因标签芯片
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveLabel = label.isNotEmpty ? label : '—';
    final bgColor = color ?? AppColors.surfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        effectiveLabel,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color != null ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.request, required this.args});

  final AfterSalesRequestModel request;
  final AfterSalesScreenArgs args;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Text(args.dealTitle, style: theme.textTheme.titleMedium),
          if (args.merchantName != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                args.merchantName!,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _StatusChip(label: request.status.toUpperCase(), color: _statusColor(request.status)),
              _StatusChip(label: request.reason?.label ?? request.reasonCode),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            request.reasonDetail,
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          if (request.userAttachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            _AttachmentRow(title: 'Your attachments', urls: request.userAttachments),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'refunded':
        return AppColors.success;
      case 'merchant_rejected':
      case 'platform_rejected':
        return AppColors.error;
      case 'awaiting_platform':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
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
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: const Text('Timeline not available yet.'),
      );
    }
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
          const Text(
            'Status Timeline',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...entries.map((entry) => _TimelineEntryTile(entry: entry)),
        ],
      ),
    );
  }
}

class _TimelineEntryTile extends StatelessWidget {
  const _TimelineEntryTile({required this.entry});

  final AfterSalesTimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(Icons.check_circle, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.status.replaceAll('_', ' ').toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${entry.actor} · ${DateFormat('MMM d, h:mm a').format(entry.timestamp.toLocal())}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                if (entry.note?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text(entry.note!, style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.title, required this.body, this.attachments = const []});

  final String title;
  final String body;
  final List<String> attachments;

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
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: AppColors.textSecondary)),
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            _AttachmentRow(urls: attachments),
          ],
        ],
      ),
    );
  }
}

/// 根据 URL 路径后缀判断是否适合用内嵌图片预览（忽略 query）
bool _isLikelyImageUrl(String raw) {
  try {
    final uri = Uri.parse(raw);
    final path = uri.path.toLowerCase();
    const exts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.heif'];
    return exts.any(path.endsWith);
  } catch (_) {
    return false;
  }
}

Future<void> _openAttachmentUrlExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// 先预览；图片全屏缩放查看，其它类型引导用浏览器打开
Future<void> _showAfterSalesAttachmentPreview(
  BuildContext context,
  String url,
  int attachmentNumber,
) async {
  final label = 'Attachment $attachmentNumber';
  if (!_isLikelyImageUrl(url)) {
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label, style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text(
                  'In-app preview is not available for this file. You can open it in your browser to view or save.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _openAttachmentUrlExternal(url);
                  },
                  child: const Text('Open in browser'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
    return;
  }

  if (!context.mounted) return;
  final mq = MediaQuery.sizeOf(context);
  final dpr = MediaQuery.devicePixelRatioOf(context);
  final memW = (mq.width * dpr).round();

  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(label, style: const TextStyle(color: Colors.white)),
            actions: [
              IconButton(
                icon: const Icon(Icons.open_in_browser),
                tooltip: 'Open in browser',
                onPressed: () => _openAttachmentUrlExternal(url),
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                memCacheWidth: memW,
                placeholder: (c, _) => const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
                ),
                errorWidget: (c, u, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 56),
                      const SizedBox(height: 12),
                      const Text(
                        'Could not load preview.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => _openAttachmentUrlExternal(url),
                        child: const Text('Open in browser'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({this.title, required this.urls});

  final String? title;
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: urls
              .asMap()
              .entries
              .map(
                (entry) => ActionChip(
                  avatar: Icon(Icons.attach_file, size: 18, color: AppColors.textPrimary),
                  label: Text(
                    'Attachment ${entry.key + 1}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  onPressed: () => _showAfterSalesAttachmentPreview(context, entry.value, entry.key + 1),
                  backgroundColor: AppColors.surfaceVariant,
                  side: const BorderSide(color: AppColors.textHint, width: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text('Failed to load: $error'),
          const SizedBox(height: 8),
          AppButton(label: 'Retry', onPressed: onRetry, isOutlined: true),
        ],
      ),
    );
  }
}
