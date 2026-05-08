import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/maps_launcher.dart';

/// 商家地址卡片组件
/// 显示地址文本，提供地图导航和电话拨打两个快捷操作按钮
class StoreAddressCard extends StatelessWidget {
  final String address;
  final double? lat;
  final double? lng;
  final String? phone;

  const StoreAddressCard({
    super.key,
    required this.address,
    this.lat,
    this.lng,
    this.phone,
  });

  /// 拨打电话
  Future<void> _callPhone() async {
    if (phone == null || phone!.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceVariant, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧：地址信息区域
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 地址图标 + 文字
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          address,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // 右侧：Drive / Call 快捷按钮
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drive 导航按钮 — 弹出选择器让用户选 Apple Maps 或 Google Maps
                _ActionButton(
                  icon: Icons.directions_car_outlined,
                  label: 'Drive',
                  onTap: () => showMapsChooser(context, address),
                ),
                const SizedBox(height: 8),
                // Call 电话按钮（无电话时置灰）
                _ActionButton(
                  icon: Icons.phone_outlined,
                  label: 'Call',
                  onTap: (phone != null && phone!.isNotEmpty) ? _callPhone : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Drive / Call 图标+文字垂直排列按钮（私有）
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    final color = isDisabled ? AppColors.textHint : AppColors.primary;

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
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
