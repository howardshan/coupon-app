// Coupon 选择底部弹窗
// 展示当前用户所有 unused 状态的券，点击后回调 couponPayload 供发送消息

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../orders/data/models/order_item_model.dart';
import '../../../orders/domain/providers/orders_provider.dart';

/// Coupon 选择底部弹窗
/// [onSelect] 用户点击某张券后触发，传入构造好的 couponPayload
class CouponPickerSheet extends ConsumerWidget {
  final void Function(Map<String, dynamic> couponPayload) onSelect;

  const CouponPickerSheet({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(userOrdersProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部拖动条
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 标题行
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text(
                  'Share a Coupon',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 券列表内容
          ordersAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'Failed to load coupons',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
            data: (orders) {
              // 收集所有 unused 状态的 order items
              final unusedItems = <OrderItemModel>[];
              for (final order in orders) {
                for (final item in order.items) {
                  if (item.customerStatus == CustomerItemStatus.unused) {
                    unusedItems.add(item);
                  }
                }
              }

              if (unusedItems.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.confirmation_number_outlined,
                            size: 48, color: AppColors.textHint),
                        SizedBox(height: 12),
                        Text(
                          'No unused coupons',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ConstrainedBox(
                // 最多显示 5 张券的高度，超出可滚动
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: unusedItems.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 80),
                  itemBuilder: (context, index) {
                    final item = unusedItems[index];
                    return _CouponTile(
                      item: item,
                      onTap: () {
                        // 构造 couponPayload，供 sendCouponMessage 使用
                        final payload = <String, dynamic>{
                          'order_item_id': item.id,
                          if (item.couponId != null && item.couponId!.isNotEmpty)
                            'coupon_id': item.couponId,
                          'coupon_code': item.couponCode ?? '',
                          'deal_title': item.dealTitle,
                          'merchant_name': item.merchantName ?? '',
                          'deal_image_url': item.dealImageUrl ?? '',
                          'discount_price': item.unitPrice,
                          'expires_at': item.couponExpiresAt
                                  ?.toIso8601String() ??
                              '',
                          'customer_status': 'unused',
                        };
                        Navigator.of(context).pop();
                        onSelect(payload);
                      },
                    );
                  },
                ),
              );
            },
          ),

          // 底部安全区域
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

// ================================================================
// 单张券列表项
// ================================================================

class _CouponTile extends StatelessWidget {
  final OrderItemModel item;
  final VoidCallback onTap;

  const _CouponTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // 格式化过期时间
    String expText = '';
    if (item.couponExpiresAt != null) {
      expText = 'Exp: ${DateFormat('MMM d, yyyy').format(item.couponExpiresAt!)}';
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Deal 封面图
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: item.dealImageUrl != null && item.dealImageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: item.dealImageUrl!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        width: 56,
                        height: 56,
                        color: AppColors.surfaceVariant,
                      ),
                      errorWidget: (_, _, _) => Container(
                        width: 56,
                        height: 56,
                        color: AppColors.surfaceVariant,
                        child: const Icon(Icons.image,
                            color: AppColors.textHint, size: 24),
                      ),
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.confirmation_number_outlined,
                          color: AppColors.textHint, size: 24),
                    ),
            ),

            const SizedBox(width: 12),

            // 文字信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Deal 标题
                  Text(
                    item.dealTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  // 商家名
                  if (item.merchantName != null &&
                      item.merchantName!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.merchantName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  // 价格 + 过期时间
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Text(
                          '\$${item.unitPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        if (expText.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            expText,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 右侧箭头
            const Icon(Icons.chevron_right,
                color: AppColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }
}
