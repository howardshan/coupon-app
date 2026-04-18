// 团购券详情页 — 显示 QR 码、商户信息、操作按钮
// 注：屏幕亮度控制需要 screen_brightness 插件，当前使用注释标注 TODO

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/back_or_home_app_bar_leading.dart';
import '../../../reviews/domain/providers/my_reviews_provider.dart';
import '../../data/models/coupon_model.dart';
import '../../data/models/coupon_gift_model.dart';
import '../../domain/providers/coupons_provider.dart';
import '../widgets/gift_bottom_sheet.dart';

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
        leading: backOrHomeAppBarLeading(context),
        automaticallyImplyLeading: false,
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
    final myUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final heldByViewer =
        myUserId.isNotEmpty && coupon.isHeldByUser(myUserId);
    final viewerIsPurchaser = myUserId.isNotEmpty && coupon.userId == myUserId;

    // 退款状态使用专属布局（refunded 和 expired refunded 共用）
    if (coupon.isRefunded || coupon.status == 'expired') {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 状态 Banner ──────────────────────────────
            _StatusBanner(coupon: coupon),

            // ── 退款状态说明 + 退款详情卡片 ───────────────
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

            // ── 使用规则（usage_rules 或 usage_notes，与 Deal 详情 Purchase Notes 一致） ──
            if (coupon.usageDisplayLines.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(indent: 16, endIndent: 16),
              const SizedBox(height: 8),
              _UsageRulesSection(rules: coupon.usageDisplayLines),
            ],

            // ── Buy Again 按钮 ───────────────────────────
            _BuyAgainButton(coupon: coupon),
            const SizedBox(height: 32),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 状态 Banner ──────────────────────────────
          _StatusBanner(coupon: coupon),

          // ── QR / 已作废 / 已赠送 / 已用等 ─────────────────────
          // 受赠人：order_items.customer_status 仍为 gifted，但持券人已是自己 → 应显示 QR
          if (coupon.isUnused && !coupon.isVoided && heldByViewer)
            _QrSection(coupon: coupon)
          else if (coupon.isVoided && coupon.voidReason == 'gifted')
            _UsedStatusSection(coupon: coupon)
          else if (coupon.isVoided)
            _UsedStatusSection(coupon: coupon)
          else if (coupon.customerStatus == 'gifted' && !heldByViewer)
            _UsedStatusSection(coupon: coupon)
          else
            _UsedStatusSection(coupon: coupon),

          // ── Gifted 信息（仅赠送人可见：撤回/更换受赠方） ──────────
          if (viewerIsPurchaser &&
              (coupon.customerStatus == 'gifted' ||
                  (coupon.isVoided && coupon.voidReason == 'gifted')) &&
              coupon.orderItemId != null)
            _GiftInfoSection(orderItemId: coupon.orderItemId!, coupon: coupon),

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

          // ── 使用规则（usage_rules 或 usage_notes） ──
          if (coupon.usageDisplayLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(indent: 16, endIndent: 16),
            const SizedBox(height: 8),
            _UsageRulesSection(rules: coupon.usageDisplayLines),
          ],

          // ── 我的评价（仅已核销且未作废）────────────────
          if (coupon.isUsed && !coupon.isVoided) ...[
            const SizedBox(height: 8),
            const Divider(indent: 16, endIndent: 16),
            const SizedBox(height: 8),
            _CouponReviewSection(coupon: coupon),
          ],

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

  /// 与列表卡片一致；赠券受赠人持券可用时按 READY TO USE 展示（不误导为已送出）
  Color _bannerColor(bool heldByViewer) {
    if (heldByViewer &&
        coupon.isUnused &&
        !coupon.isVoided &&
        !coupon.isExpired) {
      return switch (coupon.status) {
        'unused' => AppColors.primary,
        'used' => AppColors.success,
        'expired' => AppColors.textSecondary,
        'refunded' => AppColors.warning,
        _ => AppColors.primary,
      };
    }
    if (coupon.customerStatus == 'gifted' && !heldByViewer) {
      return const Color(0xFF9C27B0);
    }
    if (coupon.isVoided && coupon.voidReason == 'gifted') {
      return const Color(0xFF9C27B0);
    }
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

  String _bannerLabel(bool heldByViewer) {
    if (heldByViewer &&
        coupon.isUnused &&
        !coupon.isVoided &&
        !coupon.isExpired) {
      return switch (coupon.status) {
        'unused' => 'READY TO USE',
        'used' => 'USED',
        'expired' => 'EXPIRED REFUND',
        'refunded' => 'REFUNDED',
        _ => coupon.status.toUpperCase(),
      };
    }
    if (coupon.customerStatus == 'gifted' && !heldByViewer) return 'GIFTED';
    if (coupon.isVoided && coupon.voidReason == 'gifted') return 'GIFTED';
    if (coupon.isVoided) return 'CANCELLED';
    if (coupon.isExpired) return 'EXPIRED REFUND';
    if (coupon.status == 'refunded') return 'REFUNDED';
    return switch (coupon.status) {
      'unused' => 'READY TO USE',
      'used' => 'USED',
      'expired' => 'EXPIRED REFUND',
      'refunded' => 'REFUNDED',
      _ => coupon.status.toUpperCase(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final heldByViewer = uid != null && coupon.isHeldByUser(uid);
    final color = _bannerColor(heldByViewer);
    final label = _bannerLabel(heldByViewer);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
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
              'Expires: ${DateFormat('MMM d, yyyy').format(coupon.expiresAt.toUtc())} (CT)',
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
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final heldByViewer = uid != null && coupon.isHeldByUser(uid);

    // 赠送人已转出、券仍为 unused（in-app 赠礼后 order_item 恒为 gifted）
    if (coupon.customerStatus == 'gifted' &&
        !heldByViewer &&
        coupon.isUnused &&
        !coupon.isVoided) {
      message =
          'You sent this voucher to a friend. They can redeem it from their account.';
    } else if (coupon.isVoided && coupon.voidReason == 'gifted') {
      message = 'This voucher has been gifted to a friend.';
      if (coupon.voidedAt != null) {
        message +=
            ' (${DateFormat('MMM d, yyyy').format(coupon.voidedAt!.toLocal())})';
      }
    } else if (coupon.isVoided) {
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
          'This coupon expired on ${DateFormat('MMM d, yyyy').format(coupon.expiresAt.toUtc())} (CT)';
    } else {
      message = 'This coupon is no longer active.';
    }

    final dateFmt = DateFormat('MMM d, yyyy');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Icon(
            (coupon.customerStatus == 'gifted' &&
                    !heldByViewer &&
                    coupon.isUnused &&
                    !coupon.isVoided) ||
                    (coupon.isVoided && coupon.voidReason == 'gifted')
                ? Icons.card_giftcard_outlined
                : coupon.isVoided
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

          // 退款详情卡片（refunded 或 expired+refunded）
          if (coupon.isRefunded || (coupon.isExpired && coupon.status == 'refunded')) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Refund Details',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 订单编号
                  if (coupon.orderNumber != null && coupon.orderNumber!.isNotEmpty) ...[
                    _DetailRow(
                      icon: Icons.receipt_long_outlined,
                      label: 'Order Number',
                      value: coupon.orderNumber!,
                    ),
                    const SizedBox(height: 8),
                  ],
                  // 购买日期
                  _DetailRow(
                    icon: Icons.shopping_bag_outlined,
                    label: 'Purchased',
                    value: dateFmt.format(coupon.createdAt.toLocal()),
                  ),
                  const SizedBox(height: 8),
                  // 退款日期
                  if (coupon.refundedAt != null)
                    _DetailRow(
                      icon: Icons.event_outlined,
                      label: 'Refunded',
                      value: dateFmt.format(coupon.refundedAt!.toLocal()),
                    )
                  else if (coupon.isExpired)
                    _DetailRow(
                      icon: Icons.event_outlined,
                      label: 'Expired',
                      value: '${dateFmt.format(coupon.expiresAt.toUtc())} (CT)',
                    ),
                  const SizedBox(height: 8),
                  // 退款金额（含税）
                  _DetailRow(
                    icon: Icons.attach_money,
                    label: 'Refund Amount',
                    value: coupon.refundAmount != null
                        ? '\$${coupon.refundAmount!.toStringAsFixed(2)}'
                        : coupon.unitPrice != null
                            ? '\$${(coupon.unitPrice! + coupon.taxAmount).toStringAsFixed(2)}'
                            : 'N/A',
                  ),
                  // 税费单独展示（老订单 tax = 0 时隐藏）
                  if (coupon.taxAmount > 0) ...[
                    const SizedBox(height: 8),
                    _DetailRow(
                      icon: Icons.receipt_long_outlined,
                      label: 'Including Tax',
                      value: '\$${coupon.taxAmount.toStringAsFixed(2)}',
                    ),
                  ],
                  const SizedBox(height: 8),
                  // 退款去向
                  _DetailRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Refunded To',
                    value: switch (coupon.refundMethod) {
                      'store_credit' => 'Store Credit',
                      'original_payment' => 'Original Payment',
                      _ => 'Original Payment',
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 退款详情行
// ──────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
// Deal 信息区域
// ──────────────────────────────────────────────
class _DealInfoSection extends StatelessWidget {
  final CouponModel coupon;

  const _DealInfoSection({required this.coupon});

  // 点击 deal 标题，跳转到 deal 详情页；如果 deal 已下架则提示
  Future<void> _onDealTitleTap(BuildContext context) async {
    try {
      final deal = await Supabase.instance.client
          .from('deals')
          .select('id')
          .eq('id', coupon.dealId)
          .eq('is_active', true)
          .maybeSingle();
      if (!context.mounted) return;
      if (deal != null) {
        context.push('/deals/${coupon.dealId}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deal is not available')),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deal is not available')),
      );
    }
  }

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
            GestureDetector(
              onTap: () => _onDealTitleTap(context),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      coupon.dealTitle!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_ios,
                      size: 14, color: AppColors.primary),
                ],
              ),
            ),
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
// 已用券：我的评价入口（查看/编辑或去写评价）
// ──────────────────────────────────────────────
class _CouponReviewSection extends ConsumerWidget {
  final CouponModel coupon;

  const _CouponReviewSection({required this.coupon});

  void _pushReview(BuildContext context, {String? reviewId}) {
    final params = <String, String>{};
    if (coupon.merchantId.isNotEmpty) {
      params['merchantId'] = coupon.merchantId;
    }
    final oid = coupon.orderItemId;
    if (oid != null && oid.isNotEmpty) {
      params['orderItemId'] = oid;
    }
    if (reviewId != null) {
      params['reviewId'] = reviewId;
    }
    final q = Uri(
      path: '/review/${coupon.dealId}',
      queryParameters: params.isEmpty ? null : params,
    );
    context.push(q.toString());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myWrittenReviewsProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) {
        final matched = matchWrittenReviewForCoupon(coupon, list);
        final starCount = matched != null
            ? (matched.ratingOverall > 0 ? matched.ratingOverall : matched.rating)
            : 0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Review',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              if (matched != null) ...[
                Row(
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < starCount ? Icons.star : Icons.star_border,
                      size: 22,
                      color: AppColors.warning,
                    ),
                  ),
                ),
                if (matched.comment != null &&
                    matched.comment!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    matched.comment!.trim(),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () =>
                        _pushReview(context, reviewId: matched.id),
                    child: const Text('View / Edit Review'),
                  ),
                ),
              ] else ...[
                const Text(
                  'Share feedback about your visit.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _pushReview(context),
                    icon: const Icon(Icons.rate_review_outlined, size: 20),
                    label: const Text('Write a Review'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
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
// 使用规则（deals.usage_rules）
// ──────────────────────────────────────────────
class _UsageRulesSection extends StatelessWidget {
  final List<String> rules;

  const _UsageRulesSection({required this.rules});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Usage Rules',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.info.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.format_list_bulleted,
                        size: 18, color: AppColors.info),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Please follow these rules when redeeming:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...rules.map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '• ',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            line,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
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
            'Refund Policy',
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
// Gifted 信息区（显示受赠方 + 撤回/更换按钮）
// ──────────────────────────────────────────────
class _GiftInfoSection extends ConsumerWidget {
  final String orderItemId;
  final CouponModel coupon;

  const _GiftInfoSection({
    required this.orderItemId,
    required this.coupon,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final giftAsync = ref.watch(activeGiftProvider(orderItemId));

    return giftAsync.when(
      data: (gift) {
        if (gift == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF9C27B0).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF9C27B0).withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                const Row(
                  children: [
                    Icon(Icons.card_giftcard_outlined,
                        size: 18, color: Color(0xFF9C27B0)),
                    SizedBox(width: 8),
                    Text(
                      'Gift Details',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9C27B0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 受赠方
                _GiftDetailRow(
                  label: 'Gifted To',
                  value: gift.recipientDisplay,
                ),
                const SizedBox(height: 8),

                // 状态
                _GiftDetailRow(
                  label: 'Status',
                  value: gift.status.displayLabel,
                  valueColor: switch (gift.status) {
                    GiftStatus.pending => AppColors.warning,
                    GiftStatus.claimed => AppColors.success,
                    GiftStatus.recalled => AppColors.textSecondary,
                    GiftStatus.expired => AppColors.textHint,
                  },
                ),
                const SizedBox(height: 8),

                // 赠送时间
                _GiftDetailRow(
                  label: 'Gifted On',
                  value: DateFormat('MMM d, yyyy')
                      .format(gift.createdAt.toLocal()),
                ),

                // 操作按钮（与 recall-gift 一致：券已核销/作废则不显示撤回）
                if (gift.canEdit || gift.canShowRecallButton(coupon)) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // 更换受赠方
                      if (gift.canEdit)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _editRecipient(context, ref, gift),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Change Recipient'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF9C27B0),
                              side: const BorderSide(
                                  color: Color(0xFF9C27B0)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      if (gift.canEdit && gift.canShowRecallButton(coupon))
                        const SizedBox(width: 10),
                      // 撤回赠送
                      if (gift.canShowRecallButton(coupon))
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _recallGift(context, ref, gift),
                            icon: const Icon(Icons.undo_rounded, size: 16),
                            label: const Text('Recall Gift'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.error),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  // 更换受赠方：打开 Gift Bottom Sheet，用户确认发送后才撤回旧 gift
  Future<void> _editRecipient(
      BuildContext context, WidgetRef ref, CouponGiftModel gift) async {
    if (!context.mounted) return;

    // 弹出 Gift Bottom Sheet（预填之前的收件人，传入旧 gift id）
    // 撤回逻辑在 bottom sheet 内部发送时才执行，取消不会影响旧 gift
    GiftBottomSheet.show(
      context,
      dealTitle: coupon.dealTitle ?? '',
      orderItemId: orderItemId,
      merchantName: coupon.merchantName,
      expiresAt: coupon.expiresAt,
      prefillEmail: gift.recipientEmail,
      prefillPhone: gift.recipientPhone,
      existingGiftId: gift.id,
      dealImageUrl: coupon.dealImageUrl,
      onGiftSent: () {
        ref.invalidate(activeGiftProvider(orderItemId));
        ref.invalidate(couponDetailProvider(coupon.id));
      },
    );
  }

  // 撤回赠送
  Future<void> _recallGift(
      BuildContext context, WidgetRef ref, CouponGiftModel gift) async {
    // 好友赠送的确认文案不同
    final isInApp = gift.isInApp;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recall Gift'),
        content: Text(
          isInApp
              ? 'Are you sure you want to recall this gift? '
                'The coupon will be removed from your friend\'s account.'
              : 'Are you sure you want to recall this gift? '
                'The recipient will no longer be able to claim it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Recall'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // 好友赠送：使用 recallFriendGift（会同时发 chat 消息）
    final bool ok;
    if (isInApp && gift.recipientUserId != null) {
      ok = await ref.read(giftNotifierProvider.notifier).recallFriendGift(
            giftId: gift.id,
            recipientUserId: gift.recipientUserId!,
            dealTitle: coupon.dealTitle ?? '',
          );
    } else {
      ok = await ref.read(giftNotifierProvider.notifier).recallGift(gift.id);
    }

    if (context.mounted) {
      var failMsg = 'Failed to recall gift';
      if (!ok) {
        final e = ref.read(giftNotifierProvider).error;
        if (e != null) {
          failMsg = e is AppException ? e.message : e.toString();
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Gift recalled successfully' : failMsg),
          backgroundColor: ok ? AppColors.success : AppColors.error,
        ),
      );
    }
    if (ok) {
      ref.invalidate(activeGiftProvider(orderItemId));
      ref.invalidate(couponDetailProvider(coupon.id));
      invalidateUserCouponsEverywhere(ref.invalidate);
    }
  }
}

// 礼物详情行
class _GiftDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _GiftDetailRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
              fontSize: 13, color: AppColors.textSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
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
    final coupon = widget.coupon;
    final orderId = coupon.orderId;
    final dealId = coupon.dealId;

    // 查询同一订单里同一 deal 的所有 unused 券（用于数量选择）
    List<Map<String, dynamic>> siblingCoupons = [];
    try {
      final data = await Supabase.instance.client
          .from('coupons')
          .select('id, order_item_id')
          .eq('order_id', orderId)
          .eq('deal_id', dealId)
          .eq('status', 'unused')
          .order('created_at');
      siblingCoupons = List<Map<String, dynamic>>.from(data);
    } catch (_) {
      // 查询失败则只退当前这一张
      siblingCoupons = [{'id': coupon.id, 'order_item_id': coupon.orderItemId}];
    }

    // 确保当前券在列表中且排在第一位
    final currentIdx = siblingCoupons.indexWhere((c) => c['id'] == coupon.id);
    if (currentIdx < 0) {
      siblingCoupons.insert(0, {'id': coupon.id, 'order_item_id': coupon.orderItemId});
    } else if (currentIdx > 0) {
      final current = siblingCoupons.removeAt(currentIdx);
      siblingCoupons.insert(0, current);
    }

    final totalAvailable = siblingCoupons.length;
    int cancelCount = 1;

    if (!mounted) return;

    // 如果有多张可退，先弹出数量选择
    if (totalAvailable > 1) {
      final selectedCount = await showModalBottomSheet<int>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => _CancelQuantitySheet(
          totalAvailable: totalAvailable,
          dealTitle: coupon.dealTitle ?? 'this deal',
        ),
      );
      if (selectedCount == null) return;
      cancelCount = selectedCount;
    }

    if (!mounted) return;

    // 查询订单的支付信息
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
    } catch (_) {}

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
              Text(
                cancelCount > 1
                    ? 'Cancel $cancelCount Vouchers'
                    : 'Cancel Voucher',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

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

    // 依次退款选中数量的券（当前券优先）
    int successCount = 0;
    for (int i = 0; i < cancelCount && i < siblingCoupons.length; i++) {
      final c = siblingCoupons[i];
      final itemId = c['order_item_id'] as String?;
      final cId = c['id'] as String;
      bool ok;
      if (itemId != null && itemId.isNotEmpty) {
        ok = await ref
            .read(refundNotifierProvider.notifier)
            .requestItemRefund(itemId, refundMethod: refundMethod);
      } else {
        ok = await ref
            .read(refundNotifierProvider.notifier)
            .requestRefund(cId, refundMethod: refundMethod);
      }
      if (ok) successCount++;
    }

    if (mounted) {
      setState(() => _isRefunding = false);
      if (successCount > 0) {
        final msg = refundMethod == 'store_credit'
            ? '$successCount voucher${successCount > 1 ? 's' : ''} refunded to Store Credit'
            : '$successCount voucher${successCount > 1 ? 's' : ''} refund processing';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
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

          // 仅购买人且仍持券：退款 + 转赠（已赠出给好友后不可操作）
          if (coupon.isUnused &&
              !coupon.isVoided &&
              coupon.viewerCanManagePurchaseActions(
                Supabase.instance.client.auth.currentUser?.id,
              )) ...[
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

// ──────────────────────────────────────────────
// Buy Again 按钮（仅 refunded 状态，deal 仍上架时显示）
// ──────────────────────────────────────────────
class _BuyAgainButton extends StatefulWidget {
  final CouponModel coupon;

  const _BuyAgainButton({required this.coupon});

  @override
  State<_BuyAgainButton> createState() => _BuyAgainButtonState();
}

class _BuyAgainButtonState extends State<_BuyAgainButton> {
  bool _loading = true;
  bool _dealAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkDealAvailability();
  }

  Future<void> _checkDealAvailability() async {
    try {
      final deal = await Supabase.instance.client
          .from('deals')
          .select('id')
          .eq('id', widget.coupon.dealId)
          .eq('is_active', true)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _dealAvailable = deal != null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_dealAvailable) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: ElevatedButton.icon(
        onPressed: () => context.push('/deals/${widget.coupon.dealId}'),
        icon: const Icon(Icons.shopping_bag_outlined),
        label: const Text('Buy Again'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 退款数量选择 Bottom Sheet
// ──────────────────────────────────────────────
class _CancelQuantitySheet extends StatefulWidget {
  final int totalAvailable;
  final String dealTitle;

  const _CancelQuantitySheet({
    required this.totalAvailable,
    required this.dealTitle,
  });

  @override
  State<_CancelQuantitySheet> createState() => _CancelQuantitySheetState();
}

class _CancelQuantitySheetState extends State<_CancelQuantitySheet> {
  int _count = 1;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cancel Vouchers',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'You have ${widget.totalAvailable} unused voucher${widget.totalAvailable > 1 ? 's' : ''} for this deal.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 20),
          // 数量选择器
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _count > 1
                    ? () => setState(() => _count--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                iconSize: 32,
                color: AppColors.primary,
              ),
              const SizedBox(width: 16),
              Text(
                '$_count',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: _count < widget.totalAvailable
                    ? () => setState(() => _count++)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
                iconSize: 32,
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _count),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Cancel $_count Voucher${_count > 1 ? 's' : ''}'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
          ),
        ],
      ),
    );
  }
}
