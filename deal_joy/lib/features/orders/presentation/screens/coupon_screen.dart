// 团购券详情页 — 显示 QR 码、商户信息、操作按钮
// 注：屏幕亮度控制需要 screen_brightness 插件，当前使用注释标注 TODO

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/coupon_model.dart';
import '../../domain/providers/coupons_provider.dart';

String _formatQrCodeForDisplay(String qrCode) {
  final normalized = qrCode.trim().replaceAll('-', '');
  if (RegExp(r'^\d{16}$').hasMatch(normalized)) {
    return '${normalized.substring(0, 4)}-${normalized.substring(4, 8)}-'
        '${normalized.substring(8, 12)}-${normalized.substring(12, 16)}';
  }
  // 兼容旧券：当 qrCode 不是 16 位数字时，直接原样展示
  return qrCode;
}

class CouponScreen extends ConsumerWidget {
  final String couponId;

  const CouponScreen({super.key, required this.couponId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final couponAsync = ref.watch(couponDetailProvider(couponId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: const Text('Your Coupon'),
      ),
      body: couponAsync.when(
        data: (coupon) => _CouponDetailBody(coupon: coupon),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    size: 64, color: AppColors.textHint),
                const SizedBox(height: 16),
                Text(
                  'Failed to load coupon',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  key: const ValueKey('coupon_retry_btn'),
                  onPressed: () =>
                      ref.invalidate(couponDetailProvider(couponId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 主体 Widget（StatefulWidget 以便日后插入亮度控制）
// ──────────────────────────────────────────────
class _CouponDetailBody extends StatefulWidget {
  final CouponModel coupon;

  const _CouponDetailBody({required this.coupon});

  @override
  State<_CouponDetailBody> createState() => _CouponDetailBodyState();
}

class _CouponDetailBodyState extends State<_CouponDetailBody> {
  @override
  void initState() {
    super.initState();
    // TODO: 当 screen_brightness 插件可用时，在此将屏幕亮度设为最大
    // ScreenBrightness().setScreenBrightness(1.0);
  }

  @override
  void dispose() {
    // TODO: 恢复原始亮度
    // ScreenBrightness().resetScreenBrightness();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coupon = widget.coupon;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 状态 Banner ──────────────────────────────
          _StatusBanner(coupon: coupon),

          // ── QR / 已作废 / 已用等 ─────────────────────
          if (coupon.isVoided)
            _UsedStatusSection(coupon: coupon)
          else if (coupon.isUnused)
            _QrSection(coupon: coupon)
          else
            _UsedStatusSection(coupon: coupon),

          const SizedBox(height: 8),
          const Divider(indent: 16, endIndent: 16),
          const SizedBox(height: 8),

          // ── Deal 信息 ─────────────────────────────────
          _DealInfoSection(coupon: coupon),

          const SizedBox(height: 8),
          const Divider(indent: 16, endIndent: 16),
          const SizedBox(height: 8),

          // ── 商户信息 ──────────────────────────────────
          _MerchantInfoSection(coupon: coupon),

          // ── 退款政策 ──────────────────────────────────
          if (coupon.refundPolicy != null) ...[
            const SizedBox(height: 8),
            const Divider(indent: 16, endIndent: 16),
            _RefundPolicySection(policy: coupon.refundPolicy!),
          ],

          // ── 操作按钮组 ─────────────────────────────────
          _ActionButtons(coupon: coupon),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 状态 Banner
// ──────────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  final CouponModel coupon;

  const _StatusBanner({required this.coupon});

  /// 与列表卡片一致：已退款一律按 REFUNDED 展示，未退款但已过期按 EXPIRED，其余按 status
  Color get _color {
    if (coupon.isVoided) return AppColors.textSecondary;
    if (coupon.status == 'refunded') return AppColors.warning;
    if (coupon.isExpired) return AppColors.textSecondary;
    return switch (coupon.status) {
      'unused' => AppColors.primary,
      'used' => AppColors.success,
      'expired' => AppColors.textSecondary,
      'refunded' => AppColors.warning,
      _ => AppColors.textHint,
    };
  }

  String get _label {
    if (coupon.isVoided) return 'CANCELLED';
    if (coupon.status == 'refunded') return 'REFUNDED';
    if (coupon.isExpired) return 'EXPIRED';
    return switch (coupon.status) {
      'unused' => 'READY TO USE',
      'used' => 'USED',
      'expired' => 'EXPIRED',
      'refunded' => 'REFUNDED',
      _ => coupon.status.toUpperCase(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        _label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _color,
          fontWeight: FontWeight.bold,
          fontSize: 16,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// QR 码区域（仅 unused 显示）
// ──────────────────────────────────────────────
class _QrSection extends StatelessWidget {
  final CouponModel coupon;

  const _QrSection({required this.coupon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            // QR 码白色卡片
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(
                data: coupon.qrCode,
                version: QrVersions.auto,
                size: 220,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppColors.textPrimary,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 券码文字
            Text(
              'Coupon Code',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            SelectableText(
              _formatQrCodeForDisplay(coupon.qrCode),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // 使用说明
            const Text(
              'Show this QR code to the merchant to redeem your deal.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Expires: ${DateFormat('MMM d, yyyy').format(coupon.expiresAt.toLocal())}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 已使用 / 过期 / 退款 状态说明
// ──────────────────────────────────────────────
class _UsedStatusSection extends StatelessWidget {
  final CouponModel coupon;

  const _UsedStatusSection({required this.coupon});

  @override
  Widget build(BuildContext context) {
    String message;

    if (coupon.isVoided) {
      message = coupon.voidReason == 'merchant_edit'
          ? 'This offer was updated by the merchant. This voucher is no longer valid. Contact support if you need help.'
          : 'This voucher is no longer valid.';
      if (coupon.voidedAt != null) {
        message +=
            ' (${DateFormat('MMM d, yyyy').format(coupon.voidedAt!.toLocal())})';
      }
    } else if (coupon.isRefunded) {
      message = 'This coupon has been refunded.';
    } else if (coupon.isUsed && coupon.usedAt != null) {
      final formatted = DateFormat('MMM d, yyyy \'at\' h:mm a')
          .format(coupon.usedAt!.toLocal());
      message = 'Used on $formatted';
    } else if (coupon.isExpired) {
      message =
          'This coupon expired on ${DateFormat('MMM d, yyyy').format(coupon.expiresAt.toLocal())}';
    } else {
      message = 'This coupon is no longer active.';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Icon(
            coupon.isVoided
                ? Icons.cancel_outlined
                : coupon.isRefunded
                    ? Icons.currency_exchange
                    : coupon.isUsed
                        ? Icons.check_circle_outline
                        : coupon.isExpired
                            ? Icons.timer_off_outlined
                            : Icons.currency_exchange,
            size: 64,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Deal 信息区域
// ──────────────────────────────────────────────
class _DealInfoSection extends StatelessWidget {
  final CouponModel coupon;

  const _DealInfoSection({required this.coupon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Deal Details',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          if (coupon.dealTitle != null)
            Text(
              coupon.dealTitle!,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ...[
            const SizedBox(height: 4),
            Text(
              'Order #${coupon.orderId.substring(0, 8).toUpperCase()}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
          if (coupon.dealDescription != null) ...[
            const SizedBox(height: 6),
            Text(
              coupon.dealDescription!,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 商户信息区域（支持多门店展示）
// ──────────────────────────────────────────────
class _MerchantInfoSection extends ConsumerWidget {
  final CouponModel coupon;

  const _MerchantInfoSection({required this.coupon});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 优先使用购买时快照，回退到旧的 applicableMerchantIds
    final storeIds = coupon.applicableStoreIds ?? coupon.applicableMerchantIds;
    final isMultiStore = storeIds != null && storeIds.length > 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isMultiStore ? 'Valid Locations' : 'Merchant',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),

          // 多门店：展示所有可用门店的名称和地址
          if (isMultiStore)
            _MultiStoreList(storeIds: storeIds)
          else ...[
            // 单店：保持原有展示
            if (coupon.merchantName != null)
              Row(
                children: [
                  const Icon(Icons.store, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      coupon.merchantName!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            if (coupon.merchantAddress != null) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      coupon.merchantAddress!,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ],
            if (coupon.merchantPhone != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.phone_outlined,
                      size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      coupon.merchantPhone!,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 多门店列表（异步加载门店名称+地址）
// ──────────────────────────────────────────────
class _MultiStoreList extends ConsumerWidget {
  final List<String> storeIds;

  const _MultiStoreList({required this.storeIds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storesAsync = ref.watch(applicableStoresProvider(storeIds));

    return storesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => Text(
        'Valid at ${storeIds.length} locations',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
      ),
      data: (stores) => Column(
        children: stores.map((store) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withAlpha(30)),
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront, size: 18, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store['name'] ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if ((store['address'] ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          store['address']!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        )).toList(),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 退款政策区域
// ──────────────────────────────────────────────
class _RefundPolicySection extends StatelessWidget {
  final String policy;

  const _RefundPolicySection({required this.policy});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Usage Rules & Refund Policy',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.info.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 18, color: AppColors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    policy,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 底部操作按钮组（ConsumerWidget 以便访问 Riverpod）
// ──────────────────────────────────────────────
class _ActionButtons extends ConsumerStatefulWidget {
  final CouponModel coupon;

  const _ActionButtons({required this.coupon});

  @override
  ConsumerState<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends ConsumerState<_ActionButtons> {
  bool _isRefunding = false;
  bool _isGifting = false;

  // 打开地图导航
  Future<void> _navigateToStore() async {
    final address = widget.coupon.merchantAddress;
    if (address == null) return;

    final encoded = Uri.encodeComponent(address);
    final uri = Uri.parse('https://maps.google.com/?q=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open maps.')),
        );
      }
    }
  }

  // 拨打商户电话
  Future<void> _callStore() async {
    final phone = widget.coupon.merchantPhone;
    if (phone == null) return;

    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not make a call.')),
        );
      }
    }
  }

  // 请求退款
  Future<void> _requestRefund() async {
    // 先查询订单的支付信息（payment_intent_id, store_credit_used, total_amount）
    final orderId = widget.coupon.orderId;
    String paymentIntentId = '';
    double storeCreditUsed = 0;

    try {
      final orderData = await Supabase.instance.client
          .from('orders')
          .select('payment_intent_id, store_credit_used')
          .eq('id', orderId)
          .single();
      paymentIntentId = orderData['payment_intent_id'] as String? ?? '';
      storeCreditUsed = (orderData['store_credit_used'] as num?)?.toDouble() ?? 0;
    } catch (_) {
      // 查询失败不阻断，按普通支付处理
    }

    final isFullStoreCredit = paymentIntentId.contains('store_credit');
    final isPartialStoreCredit = !isFullStoreCredit && storeCreditUsed > 0;

    if (!mounted) return;

    // 弹出选择退款方式的 Bottom Sheet
    final refundMethod = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        // 混合支付时展示优先退 store credit 的说明
        String originalPaymentSubtitle = 'Service fee non-refundable · 5-10 business days';
        if (isPartialStoreCredit && storeCreditUsed > 0) {
          final creditFmt = storeCreditUsed.toStringAsFixed(2);
          originalPaymentSubtitle =
              'Store Credit portion (\$$creditFmt) refunds to Store Credit first, '
              'remainder to card\n'
              'Service fee non-refundable · 5-10 business days';
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cancel Voucher',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // 全额 Store Credit 支付：只显示 Store Credit 选项
              if (isFullStoreCredit) ...[
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet, color: AppColors.success),
                  title: const Text('Store Credit', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Full amount incl. service fee · Instant'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Only Option',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.success)),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: AppColors.success.withValues(alpha: 0.3)),
                  ),
                  tileColor: AppColors.success.withValues(alpha: 0.05),
                  onTap: () => Navigator.pop(ctx, 'store_credit'),
                ),
              ] else ...[
                // 非全额 Store Credit：显示两个选项
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet, color: AppColors.success),
                  title: const Text('Store Credit', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Refund including service fee · Instant'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: AppColors.success.withValues(alpha: 0.3)),
                  ),
                  tileColor: AppColors.success.withValues(alpha: 0.05),
                  onTap: () => Navigator.pop(ctx, 'store_credit'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.credit_card, color: AppColors.textSecondary),
                  title: const Text('Original Payment', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(originalPaymentSubtitle),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.surfaceVariant),
                  ),
                  onTap: () => Navigator.pop(ctx, 'original_payment'),
                ),
              ],
              const SizedBox(height: 16),
              // 取消按钮
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Keep Voucher'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (refundMethod == null) return;

    setState(() => _isRefunding = true);

    // 优先用 orderItemId 走 V3 退款流程
    final orderItemId = widget.coupon.orderItemId;
    bool success;
    if (orderItemId != null && orderItemId.isNotEmpty) {
      success = await ref
          .read(refundNotifierProvider.notifier)
          .requestItemRefund(orderItemId, refundMethod: refundMethod);
    } else {
      // 旧版兼容：用 couponId 退款
      success = await ref
          .read(refundNotifierProvider.notifier)
          .requestRefund(widget.coupon.id, refundMethod: refundMethod);
    }

    if (mounted) {
      setState(() => _isRefunding = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(refundMethod == 'store_credit'
                ? 'Refunded to Store Credit instantly'
                : 'Refund processing, 5-10 business days'),
          ),
        );
        context.pop();
      } else {
        final error = ref.read(refundNotifierProvider).error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refund failed: $error')),
        );
      }
    }
  }

  // 转赠给好友
  Future<void> _giftToFriend() async {
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gift to Friend'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: "Friend's Email",
              hintText: 'friend@example.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('coupon_gift_cancel_btn'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const ValueKey('coupon_send_gift_btn'),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Send Gift'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isGifting = true);
    final success = await ref
        .read(giftNotifierProvider.notifier)
        .giftCoupon(widget.coupon.id, emailController.text.trim());
    if (mounted) {
      setState(() => _isGifting = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Coupon gifted successfully!')),
        );
        context.pop();
      } else {
        final error = ref.read(giftNotifierProvider).error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gift failed: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final coupon = widget.coupon;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 导航到商户 — 始终显示（有地址才可点）
          if (coupon.merchantAddress != null)
            OutlinedButton.icon(
              onPressed: _navigateToStore,
              icon: const Icon(Icons.directions_outlined),
              label: const Text('Navigate to Store'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          if (coupon.merchantAddress != null) const SizedBox(height: 10),

          // 拨打电话 — 有电话时显示
          if (coupon.merchantPhone != null)
            OutlinedButton.icon(
              onPressed: _callStore,
              icon: const Icon(Icons.phone_outlined),
              label: const Text('Call Store'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: AppColors.info,
                side: const BorderSide(color: AppColors.info),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          if (coupon.merchantPhone != null) const SizedBox(height: 10),

          // 仅 unused 且未作废：退款 + 转赠
          if (coupon.isUnused && !coupon.isVoided) ...[
            OutlinedButton.icon(
              onPressed: _isGifting ? null : _giftToFriend,
              icon: _isGifting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.card_giftcard_outlined),
              label: const Text('Gift to Friend'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: AppColors.secondary,
                side: const BorderSide(color: AppColors.secondary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _isRefunding ? null : _requestRefund,
              icon: _isRefunding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.undo_outlined),
              label: const Text('Cancel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
