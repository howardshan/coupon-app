import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../deals/data/models/review_model.dart';

/// 单条评价卡片
/// 显示用户信息、星级、评论内容、照片横滑、商家回复
class ReviewCard extends StatefulWidget {
  final ReviewModel review;

  const ReviewCard({super.key, required this.review});

  @override
  State<ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<ReviewCard> {
  // 评论是否已展开（超过3行时折叠）
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：头像 + 用户名 + 日期
          _buildUserRow(),
          const SizedBox(height: 8),
          // 第二行：星星 + Verified Purchase 标签
          _buildRatingRow(),
          const SizedBox(height: 8),
          // 第三行：评论文字（超3行折叠）
          if (widget.review.comment != null &&
              widget.review.comment!.isNotEmpty)
            _buildCommentSection(),
          // 第四行：评价照片横滑
          if (widget.review.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildPhotoRow(),
          ],
          // 第五行：商家回复（灰色背景区域）
          if (widget.review.merchantReply != null &&
              widget.review.merchantReply!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildMerchantReply(),
          ],
        ],
      ),
    );
  }

  /// 第一行：头像 + 用户名 + 右对齐日期
  Widget _buildUserRow() {
    final name = widget.review.userName ?? 'User';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    final dateStr = _formatDate(widget.review.createdAt);

    return Row(
      children: [
        // 头像
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          backgroundImage: widget.review.userAvatarUrl != null
              ? NetworkImage(widget.review.userAvatarUrl!)
              : null,
          child: widget.review.userAvatarUrl == null
              ? Text(
                  initial,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 10),
        // 用户名
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // 日期（右对齐）
        Text(
          dateStr,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  /// 第二行：五颗星 + Verified Purchase 标签
  Widget _buildRatingRow() {
    return Row(
      children: [
        // 五颗星，根据 rating 填充颜色
        ...List.generate(5, (i) {
          final filled = i < widget.review.rating;
          return Icon(
            Icons.star,
            size: 16,
            color: filled ? AppColors.featuredBadge : AppColors.surfaceVariant,
          );
        }),
        const SizedBox(width: 8),
        // Verified Purchase 标签（仅 isVerified 时显示）
        if (widget.review.isVerified)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Verified Purchase',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  /// 第三行：评论文字，超过3行时折叠，点击展开
  Widget _buildCommentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.review.comment!,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
          maxLines: _expanded ? null : 3,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        ),
        // 展开/折叠按钮（利用 LayoutBuilder 判断是否溢出）
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _expanded ? 'Show less' : 'Show more',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 第四行：评价照片横滑，高 80，宽 80 缩略图
  Widget _buildPhotoRow() {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.review.photoUrls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: widget.review.photoUrls[index],
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              // Shimmer 加载占位
              placeholder: (context, url) => Shimmer.fromColors(
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: Container(
                  width: 80,
                  height: 80,
                  color: Colors.white,
                ),
              ),
              // 加载失败占位
              errorWidget: (context, url, error) => Container(
                width: 80,
                height: 80,
                color: AppColors.surfaceVariant,
                child: const Icon(
                  Icons.broken_image,
                  size: 24,
                  color: AppColors.textHint,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 第五行：商家回复区域（灰色背景）
  Widget _buildMerchantReply() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Store Reply" 标签
          const Text(
            'Store Reply',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          // 回复内容
          Text(
            widget.review.merchantReply!,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// 格式化日期为 "MMM DD, YYYY" 样式
  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
