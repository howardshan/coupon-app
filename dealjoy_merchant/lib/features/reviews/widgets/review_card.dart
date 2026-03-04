// 单条评价卡片组件
// 展示: 用户名 / 星级 / 评价内容 / 图片缩略图 / 时间
// 若有商家回复: 显示缩进回复区块（橙色背景）
// 若无回复: 显示 Reply 按钮（触发 ReplyBottomSheet）

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/merchant_review.dart';
import '../providers/reviews_provider.dart';
import 'reply_bottom_sheet.dart';

class ReviewCard extends ConsumerWidget {
  const ReviewCard({
    super.key,
    required this.review,
  });

  final MerchantReview review;

  static const Color _primaryColor  = Color(0xFFFF6B35);
  static const Color _replyBg       = Color(0xFFFFF3EE);
  static const Color _textPrimary   = Color(0xFF1A1A1A);
  static const Color _textSecondary = Color(0xFF888888);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 头部：用户名 + 星级 + 时间 ---
            _buildHeader(),

            // --- 评价内容 ---
            if (review.content != null && review.content!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                review.content!,
                style: const TextStyle(
                  fontSize: 14,
                  color:    _textPrimary,
                  height:   1.5,
                ),
              ),
            ],

            // --- 图片缩略图（若有）---
            if (review.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildImageRow(),
            ],

            // --- 商家回复区块 或 Reply 按钮 ---
            const SizedBox(height: 12),
            review.hasReply
                ? _buildReplyBlock()
                : _buildReplyButton(context, ref),
          ],
        ),
      ),
    );
  }

  // =============================================================
  // _buildHeader — 用户名 + 星级 + 时间
  // =============================================================
  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 用户头像（首字母占位）
        CircleAvatar(
          radius:          18,
          backgroundColor: _primaryColor.withValues(alpha: 0.15),
          backgroundImage: review.avatarUrl != null
              ? NetworkImage(review.avatarUrl!)
              : null,
          child: review.avatarUrl == null
              ? Text(
                  review.userName.isNotEmpty
                      ? review.userName[0].toUpperCase()
                      : 'U',
                  style: const TextStyle(
                    fontSize:   14,
                    fontWeight: FontWeight.bold,
                    color:      _primaryColor,
                  ),
                )
              : null,
        ),

        const SizedBox(width: 10),

        // 用户名 + 星级
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                review.userName,
                style: const TextStyle(
                  fontSize:   14,
                  fontWeight: FontWeight.w600,
                  color:      _textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              _StarRow(rating: review.rating),
            ],
          ),
        ),

        // 评价时间
        Text(
          _formatDate(review.createdAt),
          style: const TextStyle(
            fontSize: 12,
            color:    _textSecondary,
          ),
        ),
      ],
    );
  }

  // =============================================================
  // _buildImageRow — 图片缩略图水平列表
  // =============================================================
  Widget _buildImageRow() {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount:       review.imageUrls.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              review.imageUrls[index],
              width:  72,
              height: 72,
              fit:    BoxFit.cover,
              errorBuilder: (ctx, err, stack) => Container(
                width:  72,
                height: 72,
                color:  const Color(0xFFF0F0F0),
                child:  const Icon(Icons.broken_image_outlined,
                    color: Color(0xFFCCCCCC)),
              ),
            ),
          );
        },
      ),
    );
  }

  // =============================================================
  // _buildReplyBlock — 商家回复展示区块
  // =============================================================
  Widget _buildReplyBlock() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        _replyBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _primaryColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              const Icon(Icons.store_rounded, size: 14, color: _primaryColor),
              const SizedBox(width: 4),
              const Text(
                'Owner Reply',
                style: TextStyle(
                  fontSize:   12,
                  fontWeight: FontWeight.w600,
                  color:      _primaryColor,
                ),
              ),
              const Spacer(),
              if (review.repliedAt != null)
                Text(
                  _formatDate(review.repliedAt!),
                  style: const TextStyle(fontSize: 11, color: _textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // 回复内容
          Text(
            review.merchantReply!,
            style: const TextStyle(
              fontSize: 13,
              color:    _textPrimary,
              height:   1.5,
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // _buildReplyButton — 未回复时显示的 Reply 按钮
  // =============================================================
  Widget _buildReplyButton(BuildContext context, WidgetRef ref) {
    final replyState = ref.watch(replyStateProvider);
    final isReplying = replyState.isReplying(review.id);

    return Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        onPressed: isReplying
            ? null
            : () => _showReplySheet(context, ref),
        style: OutlinedButton.styleFrom(
          foregroundColor: _primaryColor,
          side:            const BorderSide(color: _primaryColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: isReplying
            ? const SizedBox(
                width:  14,
                height: 14,
                child:  CircularProgressIndicator(
                    strokeWidth: 2, color: _primaryColor),
              )
            : const Icon(Icons.reply_rounded, size: 16),
        label: Text(
          isReplying ? 'Submitting...' : 'Reply',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  // =============================================================
  // _showReplySheet — 弹出回复输入 BottomSheet
  // =============================================================
  void _showReplySheet(BuildContext context, WidgetRef ref) {
    ReplyBottomSheet.show(
      context,
      onSubmit: (reply) async {
        // 标记为提交中
        ref.read(replyStateProvider.notifier).update(
          (state) => {...state, review.id: true},
        );
        try {
          await ref.read(reviewsProvider.notifier).replyToReview(
            review.id,
            reply,
          );
          // 统计数据不变，不需要 invalidate stats
        } finally {
          // 清除提交中状态
          ref.read(replyStateProvider.notifier).update(
            (state) => {...state}..remove(review.id),
          );
        }
      },
    );
  }

  // =============================================================
  // 工具方法: 格式化日期显示
  // =============================================================
  String _formatDate(DateTime date) {
    final now   = DateTime.now();
    final diff  = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    // 超过7天显示日期
    return '${date.month}/${date.day}/${date.year}';
  }
}

// =============================================================
// _StarRow — 星级展示行（内部组件）
// =============================================================
class _StarRow extends StatelessWidget {
  const _StarRow({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < rating ? Icons.star_rounded : Icons.star_outline_rounded,
          size:  14,
          color: index < rating
              ? const Color(0xFFFF6B35)
              : const Color(0xFFE0E0E0),
        );
      }),
    );
  }
}
