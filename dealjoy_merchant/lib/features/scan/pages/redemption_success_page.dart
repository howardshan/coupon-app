// 核销成功页
// 大 checkmark 动画 + 核销时间 + Scan Another 按钮
// P1: 10分钟内显示 Undo Redemption 按钮

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/coupon_info.dart';
import '../providers/scan_provider.dart';
import '../../orders/providers/orders_provider.dart';

class RedemptionSuccessPage extends ConsumerStatefulWidget {
  const RedemptionSuccessPage({
    super.key,
    required this.redeemedAt,
    required this.dealTitle,
    required this.couponId,
  });

  final DateTime redeemedAt;
  final String dealTitle;
  final String couponId;

  @override
  ConsumerState<RedemptionSuccessPage> createState() =>
      _RedemptionSuccessPageState();
}

class _RedemptionSuccessPageState
    extends ConsumerState<RedemptionSuccessPage>
    with SingleTickerProviderStateMixin {
  // 动画控制器 — checkmark 缩放进场
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  bool _isReverting = false;

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

    // 页面进入时播放动画
    _animController.forward();
    // 避免在 initState 里直接触发 provider 依赖，改为首帧后刷新列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(ordersNotifierProvider);
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// 撤销核销（P1）
  Future<void> _undoRedemption() async {
    setState(() => _isReverting = true);
    try {
      await ref
          .read(scanNotifierProvider.notifier)
          .revert(widget.couponId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Redemption reverted successfully.'),
          backgroundColor: Color(0xFF34C759),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // 撤销成功后回到扫码页
      context.go('/scan');
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
          content: const Text('Failed to revert. Please try again.'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isReverting = false);
    }
  }

  /// 是否仍在10分钟内（Undo 按钮可见条件）
  bool get _canUndo {
    return DateTime.now().difference(widget.redeemedAt).inMinutes < 10;
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('MMM d, yyyy h:mm a').format(widget.redeemedAt.toLocal());

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // 大 checkmark 动画
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

              // 成功标题
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

              // Deal 名称
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

              // 核销时间
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

              // Scan Another 按钮
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  key: const ValueKey('redemption_done_btn'),
                  onPressed: () {
                    // 重置 ScanNotifier 状态，回到扫码页
                    ref.read(scanNotifierProvider.notifier).reset();
                    context.go('/scan');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Scan Another',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Undo Redemption 按钮（P1: 10分钟内显示）
              if (_canUndo)
                TextButton(
                  onPressed: _isReverting ? null : _undoRedemption,
                  child: _isReverting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.red.shade400,
                          ),
                        )
                      : Text(
                          'Undo Redemption',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.red.shade400,
                            fontWeight: FontWeight.w500,
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
