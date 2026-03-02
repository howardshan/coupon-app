import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../orders/domain/providers/orders_provider.dart';

class OrderSuccessScreen extends ConsumerWidget {
  final String orderId;

  const OrderSuccessScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: orderAsync.when(
            data: (order) => Column(
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
                        '#${order.id.substring(0, 8).toUpperCase()}',
                      ),
                      const Divider(height: 16),
                      _DetailRow(
                        'Deal',
                        order.deal?.title ?? 'Deal',
                      ),
                      const Divider(height: 16),
                      _DetailRow(
                        'Quantity',
                        '${order.quantity}',
                      ),
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

                const Text(
                  'Your coupon is ready. Show the QR code at the merchant to redeem your deal.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: AppColors.textSecondary, height: 1.6),
                ),
                const SizedBox(height: 32),
                AppButton(
                  label: 'View My Coupon',
                  onPressed: () {
                    if (order.couponId != null) {
                      context.go('/coupon/${order.couponId}');
                    } else {
                      context.go('/orders');
                    }
                  },
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
                  onPressed: () => context.go('/orders'),
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
