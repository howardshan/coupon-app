import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../orders/domain/providers/coupons_provider.dart';
import '../../../orders/domain/providers/orders_provider.dart';
import '../../../deals/domain/providers/recommendation_provider.dart';

class OrderSuccessScreen extends ConsumerWidget {
  final String orderId;

  const OrderSuccessScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/home'),
        ),
        title: const Text('Order Confirmed'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: orderAsync.when(
            data: (order) {
              // 支付成功后刷新券列表和订单列表
              ref.invalidate(userCouponsProvider);
              ref.invalidate(userOrdersProvider);

              // 上报购买行为，用于推荐系统个性化（postFrame 避免 build 内副作用）
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final dealId = order.deal?.id ?? order.items.firstOrNull?.dealId;
                ref.read(recommendationRepositoryProvider).trackEvent(
                  eventType: 'purchase',
                  dealId: dealId,
                  metadata: {'amount': order.totalAmount},
                );
              });

              // V3: 从 items 汇总 deal 信息
              final items = order.items;
              final voucherCount = items.length;
              // 按 deal 分组统计
              final dealGroups = <String, List<String>>{};
              for (final item in items) {
                final title = item.dealTitle.isNotEmpty ? item.dealTitle : 'Deal';
                dealGroups.putIfAbsent(title, () => []).add(item.id);
              }
              // 兼容旧订单
              final dealSummary = dealGroups.isEmpty
                  ? (order.deal?.title ?? 'Deal')
                  : dealGroups.entries.map((e) => '${e.key} × ${e.value.length}').join('\n');

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle,
                    size: 100, color: AppColors.success),
                const SizedBox(height: 24),
                const Text(
                  'Order Confirmed!',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                // 订单详情卡片
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.surfaceVariant),
                  ),
                  child: Column(
                    children: [
                      _DetailRow(
                        'Order Number',
                        (order.orderNumber ?? '').isNotEmpty
                            ? '#${order.orderNumber}'
                            : '#${order.id.substring(0, 8).toUpperCase()}',
                      ),
                      const Divider(height: 16),
                      _DetailRow(
                        'Deal',
                        dealSummary,
                      ),
                      const Divider(height: 16),
                      _DetailRow(
                        'Vouchers',
                        '$voucherCount',
                      ),
                      // 税费拆分展示（tax_amount = 0 的老订单隐藏整行）
                      if (order.taxAmount > 0) ...[
                        const Divider(height: 16),
                        _DetailRow(
                          'Subtotal',
                          '\$${(order.totalAmount - order.taxAmount).toStringAsFixed(2)}',
                        ),
                        const Divider(height: 16),
                        _DetailRow(
                          'Tax',
                          '\$${order.taxAmount.toStringAsFixed(2)}',
                        ),
                      ],
                      const Divider(height: 16),
                      _DetailRow(
                        'Amount Paid',
                        '\$${order.totalAmount.toStringAsFixed(2)}',
                        valueStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  voucherCount > 1
                      ? 'Your $voucherCount vouchers are ready. Show the QR code at the merchant to redeem.'
                      : 'Your voucher is ready. Show the QR code at the merchant to redeem your deal.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, height: 1.6),
                ),
                const SizedBox(height: 32),
                AppButton(
                  label: voucherCount > 1 ? 'View My Vouchers' : 'View My Voucher',
                  // push 保留成功页在栈中，订单页可返回继续看确认信息
                  onPressed: () => context.push('/order/$orderId'),
                  icon: Icons.qr_code_2,
                ),
                const SizedBox(height: 16),
                AppButton(
                  label: 'Continue Browsing',
                  isOutlined: true,
                  onPressed: () => context.go('/home'),
                ),
              ],
            );
            },
            // 加载订单详情时显示简单确认
            loading: () => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle,
                    size: 100, color: AppColors.success),
                const SizedBox(height: 24),
                const Text(
                  'Order Confirmed!',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text(
                  'Loading order details...',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
            // 加载失败时仍显示确认并提供导航
            error: (_, _) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle,
                    size: 100, color: AppColors.success),
                const SizedBox(height: 24),
                const Text(
                  'Order Confirmed!',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your coupon is ready. Show the QR code at the merchant to redeem your deal.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: AppColors.textSecondary, height: 1.6),
                ),
                const SizedBox(height: 40),
                AppButton(
                  label: 'View My Coupon',
                  onPressed: () => context.push('/order/$orderId'),
                  icon: Icons.qr_code_2,
                ),
                const SizedBox(height: 16),
                AppButton(
                  label: 'Continue Browsing',
                  isOutlined: true,
                  onPressed: () => context.go('/home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? valueStyle;

  const _DetailRow(this.label, this.value, {this.valueStyle});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: valueStyle ??
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
      ],
    );
  }
}
