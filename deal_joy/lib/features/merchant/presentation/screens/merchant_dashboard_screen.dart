import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';

class MerchantDashboardScreen extends StatelessWidget {
  const MerchantDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Merchant Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats cards
            Row(
              children: [
                _StatCard(
                    label: 'Today\'s Redemptions',
                    value: '12',
                    icon: Icons.qr_code_scanner,
                    color: AppColors.primary),
                const SizedBox(width: 12),
                _StatCard(
                    label: 'Total Revenue',
                    value: '\$1,240',
                    icon: Icons.attach_money,
                    color: AppColors.success),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatCard(
                    label: 'Active Deals',
                    value: '3',
                    icon: Icons.local_offer,
                    color: AppColors.secondary),
                const SizedBox(width: 12),
                _StatCard(
                    label: 'Total Reviews',
                    value: '48',
                    icon: Icons.star_outline,
                    color: AppColors.warning),
              ],
            ),
            const SizedBox(height: 32),

            const Text('Actions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            AppButton(
              label: 'Scan QR Code',
              icon: Icons.qr_code_scanner,
              onPressed: () => context.push('/merchant/scan'),
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Create New Deal',
              isOutlined: true,
              icon: Icons.add_circle_outline,
              onPressed: () {
                // TODO: navigate to create deal form
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 8),
              Text(value,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color)),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
