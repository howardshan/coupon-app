import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../deals/data/models/review_model.dart';

/// 单条评价卡片
/// 显示用户信息、5维度星级、hashtag chips、评论内容、照片横滑、商家回复
class ReviewCard extends StatefulWidget {
  final ReviewModel review;

  /// hashtag id → tag 名称映射，由父组件传入
  /// 如果 map 为空或 id 不在 map 中，对应 hashtag 直接跳过显示
  final Map<String, String> hashtagMap;

  const ReviewCard({
    super.key,
    required this.review,
    this.hashtagMap = const {},
  });

  @override
  State<ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<ReviewCard> {
  // 评论是否已展开（超过3行时折叠）
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // 合并 photoUrls（旧版）与 mediaUrls（新版），用 Set 字面量去重
    final allPhotos = <String>{
      ...widget.review.photoUrls,
      ...widget.review.mediaUrls,
    }.toList();

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
          // 第一行：头像 + 用户名 + 日期（+ via deal 标题）
          _buildUserRow(),
          const SizedBox(height: 8),
          // 第二行：overall 星星 + Verified Purchase 标签
          _buildRatingRow(),
          // 第三行：子维度评分（如果有任意一个子维度评分）
          if (_hasSubRatings()) ...[
            const SizedBox(height: 6),
            _buildSubRatings(),
          ],
          // 第四行：hashtag chips（如果有可显示的 hashtag）
          if (_visibleHashtags().isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildHashtagChips(),
          ],
          // 第五行：评论文字（超3行折叠）
          if (widget.review.comment != null &&
              widget.review.comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildCommentSection(),
          ],
          // 第六行：评价照片横滑
          if (allPhotos.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildPhotoRow(allPhotos),
          ],
          // 第七行：商家回复（灰色背景区域）
          if (widget.review.merchantReply != null &&
              widget.review.merchantReply!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildMerchantReply(),
          ],
        ],
      ),
    );
  }

  /// 是否有任意子维度评分
  bool _hasSubRatings() {
    return widget.review.ratingEnvironment != null ||
        widget.review.ratingHygiene != null ||
        widget.review.ratingService != null ||
        widget.review.ratingProduct != null;
  }

  /// 返回在 hashtagMap 中能找到名称的 hashtag id 列表
  List<String> _visibleHashtags() {
    if (widget.hashtagMap.isEmpty) return [];
    return widget.review.hashtagIds
        .where((id) => widget.hashtagMap.containsKey(id))
        .toList();
  }

  /// 第一行：头像 + 用户名 + 右对齐日期（+ via Deal 标题）
  Widget _buildUserRow() {
    final name = widget.review.userName ?? 'User';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    final dateStr = _formatDate(widget.review.createdAt);

    // 日期后面拼接 "· via {dealTitle}"
    final dateLabel = widget.review.dealTitle != null
        ? '$dateStr · via ${widget.review.dealTitle}'
        : dateStr;

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
        // 日期 + 可选 deal 标题（右对齐）
        Flexible(
          child: Text(
            dateLabel,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// 第二行：overall 五颗星 + Verified Purchase 标签
  Widget _buildRatingRow() {
    return Row(
      children: [
        // overall 五颗星，根据 ratingOverall 填充颜色
        ...List.generate(5, (i) {
          final filled = i < widget.review.ratingOverall;
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

  /// 第三行：子维度评分，2列 Wrap 布局，每项用小号星星（12px）
  Widget _buildSubRatings() {
    // 收集有值的子维度
    final dimensions = <_RatingDimension>[
      if (widget.review.ratingEnvironment != null)
        _RatingDimension('Env', widget.review.ratingEnvironment!),
      if (widget.review.ratingHygiene != null)
        _RatingDimension('Hygiene', widget.review.ratingHygiene!),
      if (widget.review.ratingService != null)
        _RatingDimension('Service', widget.review.ratingService!),
      if (widget.review.ratingProduct != null)
        _RatingDimension('Product', widget.review.ratingProduct!),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: dimensions.map(_buildDimensionItem).toList(),
    );
  }

  /// 单个子维度项：缩写标签 + 小号星星
  Widget _buildDimensionItem(_RatingDimension d) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 维度缩写标签
        Text(
          d.label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 3),
        // 5颗小星星（12px）
        ...List.generate(5, (i) {
          final filled = i < d.value;
          return Icon(
            Icons.star,
            size: 12,
            color: filled ? AppColors.featuredBadge : AppColors.surfaceVariant,
          );
        }),
      ],
    );
  }

  /// 第四行：hashtag chips，正面绿色，负面橙色
  Widget _buildHashtagChips() {
    final visibleIds = _visibleHashtags();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: visibleIds.map((id) {
        final tagName = widget.hashtagMap[id]!;
        // 根据常见负面关键词判断颜色
        final isNegative = _isNegativeTag(tagName);
        final chipColor = isNegative ? AppColors.warning : AppColors.success;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: chipColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: chipColor.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            '#$tagName',
            style: TextStyle(
              fontSize: 11,
              color: chipColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 简单判断是否为负面 tag（根据常见负面词）
  bool _isNegativeTag(String name) {
    const negativeKeywords = [
      'slow', 'bad', 'poor', 'dirty', 'rude', 'cold', 'wrong',
      'broken', 'missing', 'late', 'unfriendly', 'expensive',
    ];
    final lower = name.toLowerCase();
    return negativeKeywords.any((kw) => lower.contains(kw));
  }

  /// 第五行：评论文字，超过3行时折叠，点击展开
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
        // 展开/折叠按钮
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

  /// 第六行：评价照片横滑，高 80，宽 80 缩略图
  Widget _buildPhotoRow(List<String> photos) {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: photos[index],
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

  /// 第七行：商家回复区域（灰色背景）
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

/// 子维度评分数据类（文件内部使用）
class _RatingDimension {
  final String label;
  final int value;

  const _RatingDimension(this.label, this.value);
}
