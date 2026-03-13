import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../deals/data/models/deal_model.dart';

/// 商家详情页底部固定操作栏
/// 包含：收藏、联系、Buy Now 按钮
class StoreBottomBar extends ConsumerWidget {
  final String merchantId;
  final String? phone;
  final List<DealModel> deals;
  final bool isSaved;
  final VoidCallback? onToggleSave;

  const StoreBottomBar({
    super.key,
    required this.merchantId,
    this.phone,
    this.deals = const [],
    this.isSaved = false,
    this.onToggleSave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 收藏按钮
          _BarIconButton(
            icon: isSaved ? Icons.favorite : Icons.favorite_border,
            label: 'Save',
            color: isSaved ? AppColors.error : AppColors.textSecondary,
            onTap: onToggleSave,
          ),

          const SizedBox(width: 16),

          // 联系按钮
          _BarIconButton(
            icon: Icons.chat_bubble_outline,
            label: 'Contact',
            color: AppColors.textSecondary,
            onTap: phone != null ? () => _showContactSheet(context) : null,
          ),

          const SizedBox(width: 16),

          // Buy Now 按钮
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton(
                key: const ValueKey('store_buy_now_btn'),
                onPressed: deals.isNotEmpty
                    ? () => _handleBuyNow(context)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Buy Now',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 处理购买逻辑：单 deal 直接跳转，多 deal 弹出选择
  void _handleBuyNow(BuildContext context) {
    if (deals.length == 1) {
      context.push('/deals/${deals.first.id}');
      return;
    }

    // 多 deal：弹出选择列表
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _DealSelectorSheet(deals: deals),
    );
  }

  void _showContactSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.phone),
                title: Text(phone ?? ''),
                subtitle: const Text('Tap to call'),
                onTap: () {
                  Navigator.pop(ctx);
                  // 电话拨打由外层处理
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部栏图标按钮
class _BarIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _BarIconButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Deal 选择弹窗
class _DealSelectorSheet extends StatelessWidget {
  final List<DealModel> deals;

  const _DealSelectorSheet({required this.deals});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Text(
                  'Select a Deal',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Deal 列表
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: deals.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (ctx, i) {
                final deal = deals[i];
                return ListTile(
                  title: Text(
                    deal.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '\$${deal.discountPrice.toStringAsFixed(0)}  ${deal.effectiveDiscountLabel}',
                    style: const TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  trailing: SizedBox(
                    width: 70,
                    height: 32,
                    child: ElevatedButton(
                      key: const ValueKey('store_view_deal_btn'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.push('/deals/${deal.id}');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.secondary,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text('Buy',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/deals/${deal.id}');
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
