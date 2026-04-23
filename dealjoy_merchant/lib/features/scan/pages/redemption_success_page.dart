// 核销成功页
// 大 checkmark 动画 + 核销时间 + Scan Another / 回仪表盘
// 若 Deal 启用小费且当前角色可收小费，显示 Collect tip

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/scan_provider.dart';
import '../../orders/providers/orders_provider.dart';
import '../../store/providers/store_provider.dart';
import '../../tips/models/tip_models.dart';

class RedemptionSuccessPage extends ConsumerStatefulWidget {
  const RedemptionSuccessPage({
    super.key,
    required this.redeemedAt,
    required this.dealTitle,
    required this.couponId,
    this.redeemPayload,
  });

  final DateTime redeemedAt;
  final String dealTitle;
  /// 保留参数供路由/深链兼容
  final String couponId;
  /// 核销接口完整返回（含 deal / tip_base_cents），用于小费入口
  final Map<String, dynamic>? redeemPayload;

  @override
  ConsumerState<RedemptionSuccessPage> createState() =>
      _RedemptionSuccessPageState();
}

class _RedemptionSuccessPageState
    extends ConsumerState<RedemptionSuccessPage>
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

  TipDealConfig? get _tipConfig {
    final p = widget.redeemPayload;
    if (p == null) return null;
    return TipDealConfig.fromRedeemPayload(p);
  }

  Future<void> _openCollectTip() async {
    final cfg = _tipConfig;
    final payload = widget.redeemPayload;
    if (cfg == null || payload == null) return;
    await context.push<bool>(
      '/scan/collect-tip',
      extra: {
        'coupon_id': widget.couponId,
        'deal_title': widget.dealTitle,
        'deal': payload['deal'],
        'tip_base_cents': payload['tip_base_cents'],
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeStr =
        DateFormat('MMM d, yyyy h:mm a').format(widget.redeemedAt.toLocal());
    final store = ref.watch(storeProvider).valueOrNull;
    final tipCfg = _tipConfig;
    final showTip = tipCfg != null &&
        tipCfg.tipsEnabled &&
        (store?.canCollectTips ?? false);

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

              if (showTip) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _openCollectTip,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF6B35),
                      side: const BorderSide(color: Color(0xFFFF6B35)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Collect tip',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  key: const ValueKey('redemption_done_btn'),
                  onPressed: () {
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

              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  key: const ValueKey('redemption_dashboard_btn'),
                  onPressed: () {
                    ref.read(scanNotifierProvider.notifier).reset();
                    context.go('/dashboard');
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1A1A1A),
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Back to Dashboard',
                    style: TextStyle(
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
