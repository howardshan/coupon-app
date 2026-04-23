// 核销确认页
// 展示券完整信息供商家确认，防止误操作
// 只有 status==active 的券才允许点击 Confirm Redemption

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../router/app_router.dart';
import '../models/coupon_info.dart';
import '../providers/scan_provider.dart';

class CouponVerifyPage extends ConsumerStatefulWidget {
  const CouponVerifyPage({super.key, required this.couponInfo});

  /// 从 ScanPage 传入已验证的券信息
  final CouponInfo couponInfo;

  @override
  ConsumerState<CouponVerifyPage> createState() => _CouponVerifyPageState();
}

class _CouponVerifyPageState extends ConsumerState<CouponVerifyPage> {
  bool _isRedeeming = false;

  Future<void> _confirmRedemption() async {
    setState(() => _isRedeeming = true);
    try {
      final redeemResult = await ref
          .read(scanNotifierProvider.notifier)
          .redeem(widget.couponInfo.id);

      if (!mounted) return;

      // 核销成功，跳转到成功页
      context.pushReplacement(
        '/scan/success',
        extra: {
          'redeemed_at': redeemResult.redeemedAt.toIso8601String(),
          'deal_title': widget.couponInfo.dealTitle,
          'coupon_id': widget.couponInfo.id,
          'tip_base_cents': redeemResult.tip.tipBaseCents,
          'deal': {
            'tips_enabled': redeemResult.tip.tipsEnabled,
            'tips_mode': redeemResult.tip.tipsMode,
            'tips_preset_1': redeemResult.tip.preset1,
            'tips_preset_2': redeemResult.tip.preset2,
            'tips_preset_3': redeemResult.tip.preset3,
          },
        },
      );
    } on ScanException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Redemption failed. Please try again.'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRedeeming = false);
    }
  }

  bool get _isTrainee => MerchantStatusCache.roleType == 'staff_trainee';

  @override
  Widget build(BuildContext context) {
    final coupon = widget.couponInfo;
    final dateStr = DateFormat('MMM d, yyyy').format(coupon.validUntil.toLocal());

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Verify Voucher',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 状态 Badge
                    _StatusBadge(status: coupon.status),
                    const SizedBox(height: 16),

                    // 券信息卡片
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: _statusBorderColor(coupon.status),
                          width: 1.5,
                        ),
                      ),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            _InfoRow(
                              icon: Icons.local_offer_outlined,
                              label: 'Deal',
                              value: coupon.dealTitle,
                              valueStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Divider(height: 24),
                            _InfoRow(
                              icon: Icons.person_outline_rounded,
                              label: 'Customer',
                              value: coupon.userName,
                            ),
                            const Divider(height: 24),
                            _InfoRow(
                              icon: Icons.qr_code_2_rounded,
                              label: 'Voucher Code',
                              value: coupon.code,
                              valueStyle: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Divider(height: 24),
                            _InfoRow(
                              icon: Icons.calendar_today_outlined,
                              label: 'Valid Until',
                              value: dateStr,
                              valueColor: coupon.validUntil.isBefore(DateTime.now())
                                  ? Colors.red.shade600
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 非 active 状态时显示错误说明
                    if (!coupon.isRedeemable) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(status: coupon.status, coupon: coupon),
                    ],
                  ],
                ),
              ),
            ),

            // 底部按钮区域
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Confirm Redemption 按钮（仅 active 状态启用）
                  if (_isTrainee) ...[
                    Text(
                      'Trainee accounts cannot redeem vouchers.',
                      style: TextStyle(fontSize: 13, color: Colors.orange.shade800),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: coupon.isRedeemable &&
                              !_isRedeeming &&
                              !_isTrainee
                          ? _confirmRedemption
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B35),
                        disabledBackgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.grey.shade400,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isRedeeming
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Confirm Redemption',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Cancel 按钮
                  TextButton(
                    onPressed: _isRedeeming ? null : () => context.pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusBorderColor(CouponStatus status) {
    switch (status) {
      case CouponStatus.active:
        return const Color(0xFF34C759); // 绿色
      case CouponStatus.used:
        return Colors.orange.shade300;
      case CouponStatus.expired:
        return Colors.red.shade300;
      case CouponStatus.refunded:
        return Colors.blue.shade300;
    }
  }
}

// =============================================================
// 状态 Badge 组件
// =============================================================
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final CouponStatus status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;

    switch (status) {
      case CouponStatus.active:
        bg = const Color(0xFFE8F8EE);
        fg = const Color(0xFF34C759);
        icon = Icons.check_circle_rounded;
      case CouponStatus.used:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade700;
        icon = Icons.check_circle_outline_rounded;
      case CouponStatus.expired:
        bg = Colors.red.shade50;
        fg = Colors.red.shade600;
        icon = Icons.cancel_rounded;
      case CouponStatus.refunded:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade600;
        icon = Icons.currency_exchange_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 6),
          Text(
            status.displayLabel,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// 信息行组件（Icon + Label + Value）
// =============================================================
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueStyle,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final TextStyle? valueStyle;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade400),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: (valueStyle ?? const TextStyle(fontSize: 14)).copyWith(
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================
// 错误说明 Banner（非 active 状态时显示）
// =============================================================
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.status, required this.coupon});
  final CouponStatus status;
  final CouponInfo coupon;

  @override
  Widget build(BuildContext context) {
    String message;
    Color bgColor;
    Color fgColor;

    switch (status) {
      case CouponStatus.used:
        final date = coupon.redeemedAt != null
            ? DateFormat('MMM d, yyyy').format(coupon.redeemedAt!.toLocal())
            : 'a previous date';
        message = 'This voucher has already been redeemed on $date.';
        bgColor = Colors.orange.shade50;
        fgColor = Colors.orange.shade800;
      case CouponStatus.expired:
        final date = DateFormat('MMM d, yyyy').format(coupon.validUntil.toLocal());
        message = 'This voucher expired on $date.';
        bgColor = Colors.red.shade50;
        fgColor = Colors.red.shade800;
      case CouponStatus.refunded:
        message = 'This voucher has been refunded and is no longer valid.';
        bgColor = Colors.blue.shade50;
        fgColor = Colors.blue.shade800;
      case CouponStatus.active:
        return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: fgColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: fgColor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
