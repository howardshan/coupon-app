import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../deals/data/models/deal_model.dart';

/// 代金券区域组件
/// 票据风格卡片，显示代金券价格、折扣、销量
class DealVoucherSection extends StatefulWidget {
  final List<DealModel> vouchers;

  const DealVoucherSection({super.key, required this.vouchers});

  @override
  State<DealVoucherSection> createState() => _DealVoucherSectionState();
}

class _DealVoucherSectionState extends State<DealVoucherSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.vouchers.isEmpty) return const SizedBox.shrink();

    // 默认只显示 1 张，展开时显示全部
    final shown = _expanded ? widget.vouchers : widget.vouchers.take(1).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 代金券卡片列表
        ...shown.map((v) => _VoucherCard(voucher: v)),

        // "View X more vouchers" 展开按钮
        if (!_expanded && widget.vouchers.length > 1)
          GestureDetector(
            onTap: () => setState(() => _expanded = true),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View ${widget.vouchers.length - 1} more vouchers',
                    style: const TextStyle(
                      color: AppColors.secondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down,
                      size: 18, color: AppColors.secondary),
                ],
              ),
            ),
          ),

        const SizedBox(height: 4),
      ],
    );
  }
}

/// 单张代金券卡片
class _VoucherCard extends StatelessWidget {
  final DealModel voucher;

  const _VoucherCard({required this.voucher});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/deals/${voucher.id}'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.secondary.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Text(
              voucher.title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 4),

            // 副标题
            Text(
              'Refund anytime · Auto-refund on expiry',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary.withValues(alpha: 0.8),
              ),
            ),

            const SizedBox(height: 10),

            // 底部行：价格 + 折扣 + 销量 + Buy
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 左侧价格区域（可收缩）
                Flexible(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 现价
                      Text(
                        '\$${voucher.discountPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // 折扣标签
                      Flexible(
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            voucher.effectiveDiscountLabel,
                            style: const TextStyle(
                              color: AppColors.secondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // 销量
                Text(
                  '${voucher.totalSold}+ sold',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                // Buy 按钮
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Buy',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
