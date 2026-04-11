import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../deals/domain/providers/deals_provider.dart';
import '../../data/models/review_hashtag_model.dart';
import '../../../orders/domain/providers/coupons_provider.dart';
import '../../../orders/domain/providers/pending_reviews_provider.dart';
import '../../domain/providers/my_reviews_provider.dart';

// 评价页面 — 支持新建和编辑模式
class WriteReviewScreen extends ConsumerStatefulWidget {
  final String dealId;
  final String merchantId;
  final String orderItemId;
  final String? existingReviewId; // 编辑模式时传入

  const WriteReviewScreen({
    super.key,
    required this.dealId,
    required this.merchantId,
    required this.orderItemId,
    this.existingReviewId,
  });

  @override
  ConsumerState<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends ConsumerState<WriteReviewScreen> {
  // 综合评分（必填）
  double _ratingOverall = 0;

  // 子维度评分（选填，0 表示未评）
  double _ratingEnvironment = 0;
  double _ratingHygiene = 0;
  double _ratingService = 0;
  double _ratingProduct = 0;

  // 评论内容
  final _commentCtrl = TextEditingController();

  // Hashtag 列表和选中状态
  List<ReviewHashtagModel> _hashtags = [];
  final Set<String> _selectedHashtagIds = {};

  // UI 状态
  bool _submitting = false;
  bool _loadingHashtags = true;
  bool _loadingExisting = false;
  String? _overallRatingError; // 综合评分未填时的内联错误提示

  bool get _isEditMode => widget.existingReviewId != null;

  @override
  void initState() {
    super.initState();
    _loadHashtags();
    // 编辑模式下加载现有评价数据
    if (_isEditMode) {
      _loadExistingReview();
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  // 从 review_hashtags 表加载激活的 hashtag 列表
  Future<void> _loadHashtags() async {
    try {
      final client = ref.read(supabaseClientProvider);
      final data = await client
          .from('review_hashtags')
          .select()
          .eq('is_active', true)
          .order('sort_order');
      if (mounted) {
        setState(() {
          _hashtags = (data as List)
              .map((e) => ReviewHashtagModel.fromJson(e as Map<String, dynamic>))
              .toList();
          _loadingHashtags = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingHashtags = false);
      }
    }
  }

  // 编辑模式：加载现有评价数据并预填表单
  Future<void> _loadExistingReview() async {
    setState(() => _loadingExisting = true);
    try {
      final client = ref.read(supabaseClientProvider);
      final data = await client
          .from('reviews')
          .select()
          .eq('id', widget.existingReviewId!)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() {
          _ratingOverall = (data['rating_overall'] as num?)?.toDouble() ??
              (data['rating'] as num?)?.toDouble() ??
              0;
          _ratingEnvironment =
              (data['rating_environment'] as num?)?.toDouble() ?? 0;
          _ratingHygiene = (data['rating_hygiene'] as num?)?.toDouble() ?? 0;
          _ratingService = (data['rating_service'] as num?)?.toDouble() ?? 0;
          _ratingProduct = (data['rating_product'] as num?)?.toDouble() ?? 0;
          _commentCtrl.text = data['comment'] as String? ?? '';

          // 预填选中的 hashtag
          final existingIds = data['hashtag_ids'];
          if (existingIds is List) {
            _selectedHashtagIds.addAll(existingIds.map((e) => e.toString()));
          }
        });
      }
    } catch (_) {
      // 静默失败，保持空白表单
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  // 提交或更新评价
  Future<void> _submit() async {
    // 验证综合评分必填
    if (_ratingOverall < 1) {
      setState(() => _overallRatingError = 'Please select an overall rating.');
      return;
    }
    setState(() => _overallRatingError = null);

    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      final client = ref.read(supabaseClientProvider);

      // 写评价资格前置校验：用户必须持有已核销（status=used）的 coupon
      // 编辑模式跳过此校验（既然已经写过，说明当时已经符合资格）
      if (!_isEditMode) {
        final eligibleCoupon = await client
            .from('coupons')
            .select('id')
            .eq('user_id', user.id)
            .eq('deal_id', widget.dealId)
            .eq('status', 'used')
            .limit(1)
            .maybeSingle();

        if (eligibleCoupon == null) {
          if (mounted) {
            setState(() => _submitting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'You can only review a deal after purchasing and redeeming a coupon for it.',
                ),
                backgroundColor: AppColors.error,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      final payload = {
        'deal_id': widget.dealId,
        // 空文字は UUID として無効のため null にする（DB が空文字を拒否するため）
        if (widget.merchantId.isNotEmpty) 'merchant_id': widget.merchantId,
        if (widget.orderItemId.isNotEmpty) 'order_item_id': widget.orderItemId,
        'user_id': user.id,
        'reviewer_user_id': user.id,
        // 兼容旧字段
        'rating': _ratingOverall.toInt(),
        'rating_overall': _ratingOverall.toInt(),
        // 子维度：0 代表未评，存 null 更语义化
        if (_ratingEnvironment > 0)
          'rating_environment': _ratingEnvironment.toInt(),
        if (_ratingHygiene > 0) 'rating_hygiene': _ratingHygiene.toInt(),
        if (_ratingService > 0) 'rating_service': _ratingService.toInt(),
        if (_ratingProduct > 0) 'rating_product': _ratingProduct.toInt(),
        'comment': _commentCtrl.text.trim(),
        'hashtag_ids': _selectedHashtagIds.toList(),
        'is_verified': true,
      };

      if (_isEditMode) {
        // 编辑模式：update
        await client
            .from('reviews')
            .update(payload)
            .eq('id', widget.existingReviewId!);
      } else {
        // 新建模式：insert
        await client.from('reviews').insert(payload);
      }

      if (mounted) {
        // 刷新相关 provider 缓存（含待评价列表）
        ref.invalidate(dealReviewsProvider(widget.dealId));
        ref.invalidate(dealDetailProvider(widget.dealId));
        ref.invalidate(toReviewProvider);
        ref.invalidate(myWrittenReviewsProvider);
        ref.invalidate(userCouponsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditMode
                ? 'Review updated successfully!'
                : 'Review submitted!'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        // 23505 = 唯一键冲突，即已评价过该 deal
        final isDuplicate = e.toString().contains('23505') ||
            e.toString().contains('duplicate key');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isDuplicate
                ? 'You have already reviewed this deal.'
                : 'Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        // 重复提交时也刷新待评价列表，让页面正确移除该条目
        if (isDuplicate) {
          ref.invalidate(toReviewProvider);
          ref.invalidate(myWrittenReviewsProvider);
          ref.invalidate(userCouponsProvider);
        }
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 编辑模式加载中显示全屏 loading
    if (_loadingExisting) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_isEditMode ? 'Edit Review' : 'Write a Review'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Review' : 'Write a Review'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. 综合评分 ──
            _OverallRatingSection(
              rating: _ratingOverall,
              errorText: _overallRatingError,
              onRatingUpdate: (r) {
                setState(() {
                  _ratingOverall = r;
                  // 一旦用户评分，清除错误提示
                  if (r >= 1) _overallRatingError = null;
                });
              },
            ),
            const SizedBox(height: 28),

            // ── 2. 子维度评分（2x2 网格）──
            _SubRatingsSection(
              ratingEnvironment: _ratingEnvironment,
              ratingHygiene: _ratingHygiene,
              ratingService: _ratingService,
              ratingProduct: _ratingProduct,
              onEnvironmentUpdate: (r) =>
                  setState(() => _ratingEnvironment = r),
              onHygieneUpdate: (r) => setState(() => _ratingHygiene = r),
              onServiceUpdate: (r) => setState(() => _ratingService = r),
              onProductUpdate: (r) => setState(() => _ratingProduct = r),
            ),
            const SizedBox(height: 28),

            // ── 3. Hashtag 选择区 ──
            _HashtagsSection(
              hashtags: _hashtags,
              isLoading: _loadingHashtags,
              selectedIds: _selectedHashtagIds,
              onToggle: (id) {
                setState(() {
                  if (_selectedHashtagIds.contains(id)) {
                    _selectedHashtagIds.remove(id);
                  } else {
                    _selectedHashtagIds.add(id);
                  }
                });
              },
            ),
            const SizedBox(height: 28),

            // ── 4. 媒体上传区（占位 UI）──
            const _PhotosSection(),
            const SizedBox(height: 28),

            // ── 5. 文字评论 ──
            const Text(
              'Comments (optional)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('review_comment_field'),
              controller: _commentCtrl,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'Share your experience — food, service, atmosphere...',
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 32),

            // ── 6. 提交按钮 ──
            AppButton(
              label: _isEditMode ? 'Update Review' : 'Submit Review',
              isLoading: _submitting,
              onPressed: _submit,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── 综合评分区域 ──
class _OverallRatingSection extends StatelessWidget {
  final double rating;
  final String? errorText;
  final ValueChanged<double> onRatingUpdate;

  const _OverallRatingSection({
    required this.rating,
    required this.errorText,
    required this.onRatingUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Overall Rating',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            // 必填标识
            const Text(
              '*',
              style: TextStyle(
                color: AppColors.error,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        RatingBar.builder(
          initialRating: rating,
          minRating: 1,
          allowHalfRating: false,
          itemCount: 5,
          itemSize: 40,
          itemPadding: const EdgeInsets.symmetric(horizontal: 2),
          itemBuilder: (context, i) =>
              const Icon(Icons.star, color: AppColors.featuredBadge),
          onRatingUpdate: onRatingUpdate,
        ),
        // 内联错误提示
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: const TextStyle(
              color: AppColors.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

// ── 子维度评分区域（2x2 网格）──
class _SubRatingsSection extends StatelessWidget {
  final double ratingEnvironment;
  final double ratingHygiene;
  final double ratingService;
  final double ratingProduct;
  final ValueChanged<double> onEnvironmentUpdate;
  final ValueChanged<double> onHygieneUpdate;
  final ValueChanged<double> onServiceUpdate;
  final ValueChanged<double> onProductUpdate;

  const _SubRatingsSection({
    required this.ratingEnvironment,
    required this.ratingHygiene,
    required this.ratingService,
    required this.ratingProduct,
    required this.onEnvironmentUpdate,
    required this.onHygieneUpdate,
    required this.onServiceUpdate,
    required this.onProductUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Detailed Ratings',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Optional — tap to rate each dimension',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        // 2x2 网格布局
        Row(
          children: [
            Expanded(
              child: _SubRatingItem(
                label: 'Environment',
                rating: ratingEnvironment,
                onUpdate: onEnvironmentUpdate,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SubRatingItem(
                label: 'Hygiene',
                rating: ratingHygiene,
                onUpdate: onHygieneUpdate,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SubRatingItem(
                label: 'Service',
                rating: ratingService,
                onUpdate: onServiceUpdate,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SubRatingItem(
                label: 'Product',
                rating: ratingProduct,
                onUpdate: onProductUpdate,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// 单个子维度评分卡片
class _SubRatingItem extends StatelessWidget {
  final String label;
  final double rating;
  final ValueChanged<double> onUpdate;

  const _SubRatingItem({
    required this.label,
    required this.rating,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          RatingBar.builder(
            initialRating: rating,
            minRating: 0,
            allowHalfRating: false,
            itemCount: 5,
            itemSize: 24, // 子维度小号星星
            itemPadding: const EdgeInsets.symmetric(horizontal: 1),
            itemBuilder: (context, i) =>
                const Icon(Icons.star, color: AppColors.featuredBadge),
            onRatingUpdate: onUpdate,
          ),
        ],
      ),
    );
  }
}

// ── Hashtag 选择区域 ──
class _HashtagsSection extends StatelessWidget {
  final List<ReviewHashtagModel> hashtags;
  final bool isLoading;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  const _HashtagsSection({
    required this.hashtags,
    required this.isLoading,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hashtags',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Select all that apply',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        if (isLoading)
          const SizedBox(
            height: 40,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (hashtags.isEmpty)
          const Text(
            'No hashtags available.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: hashtags.map((tag) {
              final isSelected = selectedIds.contains(tag.id);
              final isPositive = tag.category == 'positive';

              // 正面 tag 用绿色，负面 tag 用橙色
              final activeColor =
                  isPositive ? AppColors.success : AppColors.secondary;
              final inactiveColor = AppColors.textSecondary;

              return FilterChip(
                label: Text(
                  tag.tag,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : inactiveColor,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                onSelected: (_) => onToggle(tag.id),
                backgroundColor: AppColors.surfaceVariant,
                selectedColor: activeColor,
                checkmarkColor: Colors.white,
                showCheckmark: false,
                side: BorderSide(
                  color: isSelected ? activeColor : Colors.transparent,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              );
            }).toList(),
          ),
      ],
    );
  }
}

// ── 照片上传区（占位 UI）──
class _PhotosSection extends StatelessWidget {
  const _PhotosSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add Photos',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Optional',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // "+" 添加按钮（占位，暂未实现实际上传）
              GestureDetector(
                onTap: () {
                  // TODO: 实现媒体选择上传
                },
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.textHint,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: const Icon(
                    Icons.add_photo_alternate_outlined,
                    color: AppColors.textSecondary,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
