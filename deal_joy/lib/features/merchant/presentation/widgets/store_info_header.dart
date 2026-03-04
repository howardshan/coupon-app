import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// 商家详情页信息头部组件
/// 显示商家名、评分、人均消费、营业状态等核心信息
class StoreInfoHeader extends StatelessWidget {
  final String name;
  final double avgRating;
  final int reviewCount;
  final double? pricePerPerson;
  final bool isOpenNow;
  final String todayHoursText;
  final int? yearsInBusiness;

  const StoreInfoHeader({
    super.key,
    required this.name,
    required this.avgRating,
    required this.reviewCount,
    this.pricePerPerson,
    required this.isOpenNow,
    required this.todayHoursText,
    this.yearsInBusiness,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：商家名称
          Text(
            name,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: 6),

          // 第二行：评分 + 评论数 + 经营年数
          Row(
            children: [
              const Icon(Icons.star_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 3),
              Text(
                avgRating.toStringAsFixed(1),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$reviewCount reviews',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              // 仅在有经营年数时显示
              if (yearsInBusiness != null && yearsInBusiness! > 0) ...[
                const Text(
                  ' · ',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                Text(
                  '${yearsInBusiness}yr',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 6),

          // 第三行：人均消费（仅在有数据时显示）
          if (pricePerPerson != null)
            Text(
              '\$${pricePerPerson!.toStringAsFixed(0)}/person',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),

          const SizedBox(height: 6),

          // 第四行：营业状态 + 今日营业时间
          Row(
            children: [
              // 状态圆点
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOpenNow ? AppColors.success : AppColors.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isOpenNow ? 'Open Now' : 'Closed',
                style: TextStyle(
                  color: isOpenNow ? AppColors.success : AppColors.error,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              // 有营业时间文本时展示
              if (todayHoursText.isNotEmpty) ...[
                const Text(
                  '  ·  ',
                  style: TextStyle(color: AppColors.textHint, fontSize: 13),
                ),
                Expanded(
                  child: Text(
                    todayHoursText,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
