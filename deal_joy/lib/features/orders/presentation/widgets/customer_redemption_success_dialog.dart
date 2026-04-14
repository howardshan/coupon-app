// 用户端：商家核销成功后全屏强提示（风格对齐商家端 RedemptionSuccessPage）

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';

/// 全屏展示核销成功，返回时 Future 完成（用户点击主按钮并关闭对话框后）
Future<void> showCustomerRedemptionSuccessDialog({
  required BuildContext context,
  required String dealTitle,
  required DateTime redeemedAt,
  required String primaryButtonLabel,
}) {
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierColor: Colors.white,
    transitionDuration: const Duration(milliseconds: 280),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _CustomerRedemptionSuccessPage(
        dealTitle: dealTitle,
        redeemedAt: redeemedAt,
        primaryButtonLabel: primaryButtonLabel,
        onPrimary: () => Navigator.of(dialogContext).pop(),
      );
    },
  );
}

class _CustomerRedemptionSuccessPage extends StatefulWidget {
  const _CustomerRedemptionSuccessPage({
    required this.dealTitle,
    required this.redeemedAt,
    required this.primaryButtonLabel,
    required this.onPrimary,
  });

  final String dealTitle;
  final DateTime redeemedAt;
  final String primaryButtonLabel;
  final VoidCallback onPrimary;

  @override
  State<_CustomerRedemptionSuccessPage> createState() =>
      _CustomerRedemptionSuccessPageState();
}

class _CustomerRedemptionSuccessPageState extends State<_CustomerRedemptionSuccessPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeIn),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeStr =
        DateFormat('MMM d, yyyy h:mm a').format(widget.redeemedAt.toLocal());

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F8EE),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF34C759).withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 64,
                    color: Color(0xFF34C759),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              FadeTransition(
                opacity: _fadeAnim,
                child: const Text(
                  'Successfully Redeemed!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              FadeTransition(
                opacity: _fadeAnim,
                child: Text(
                  widget.dealTitle,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              FadeTransition(
                opacity: _fadeAnim,
                child: Text(
                  'Redeemed at $timeStr',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: widget.onPrimary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    widget.primaryButtonLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
