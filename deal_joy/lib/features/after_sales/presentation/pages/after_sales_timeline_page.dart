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
    final theme = Theme.of(context);
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
            _FeedbackCard(title: 'DealJoy Decision', body: request.platformFeedback!, attachments: request.platformAttachments),
          ],
          const SizedBox(height: 32),
          if (request.merchantRejected && !request.awaitingPlatform && !request.completed)
            AppButton(
              label: 'Escalate to DealJoy',
              icon: Icons.flag_outlined,
              isLoading: _isEscalating,
              onPressed: _isEscalating ? null : () => _escalate(request.id),
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
          const SizedBox(height: 32),
          Text(
            'Events',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _EventsList(events: request.events),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Future<void> _escalate(String requestId) async {
    setState(() => _isEscalating = true);
    try {
      final repo = ref.read(afterSalesRepositoryProvider);
      await repo.escalate(requestId);
      ref.invalidate(afterSalesRequestProvider(widget.args.orderId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escalated to DealJoy. We will review within 24 hours.')),
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
          ...entries.map((entry) => _TimelineEntryTile(entry: entry)).toList(),
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
    final subtitle = <Widget>[];
    if (entry.note?.isNotEmpty == true) {
      subtitle.add(Text(entry.note!, style: const TextStyle(color: AppColors.textSecondary)));
    }
    if (entry.attachments.isNotEmpty) {
      subtitle.add(const SizedBox(height: 6));
      subtitle.add(_AttachmentRow(urls: entry.attachments));
    }
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
                if (subtitle.isNotEmpty) ...subtitle,
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
          children: urls
              .asMap()
              .entries
              .map(
                (entry) => ActionChip(
                  label: Text('Attachment ${entry.key + 1}'),
                  onPressed: () => launchUrl(Uri.parse(entry.value), mode: LaunchMode.externalApplication),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _EventsList extends StatelessWidget {
  const _EventsList({required this.events});

  final List<AfterSalesEventModel> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Text('No logged events yet.', style: TextStyle(color: AppColors.textSecondary));
    }
    return Column(
      children: events
          .map(
            (event) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(event.action.replaceAll('_', ' ')),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${event.actorRole} · ${event.createdAt.toLocal()}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (event.note?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(event.note!),
                    ),
                  if (event.attachments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _AttachmentRow(urls: event.attachments),
                    ),
                ],
              ),
            ),
          )
          .toList(),
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

/// 状态标签 chip
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: chipColor),
      ),
    );
  }
}
