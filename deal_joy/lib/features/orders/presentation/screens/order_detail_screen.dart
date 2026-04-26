// 订单详情页 — 美团风格重写
// 布局从上到下：状态横幅 → Deal摘要卡片 → 券状态展开行 → Order Info → 底部操作栏

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/router/app_route_observer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/back_or_home_app_bar_leading.dart';
import '../../../cart/domain/providers/cart_provider.dart';
import '../../../deals/domain/providers/deals_provider.dart';
import '../../data/models/order_detail_model.dart';
import '../../data/models/order_item_model.dart';
import '../../domain/providers/aggregated_deal_voucher_detail_provider.dart';
import '../../domain/providers/orders_provider.dart';
import '../../domain/providers/coupons_provider.dart';
import '../widgets/customer_redemption_success_dialog.dart';
import '../widgets/gift_bottom_sheet.dart';
import '../widgets/used_refund_entry.dart';
import '../../../after_sales/data/models/after_sales_request_model.dart';
import '../../../after_sales/domain/providers/after_sales_provider.dart';
import '../helpers/after_sales_coupon_map.dart';

// ── 未使用券 QR 码弹窗 ────────────────────────────

/// 出示未使用券 QR；内容订阅 Provider，商家核销后自动刷新；定时 invalidate 兜底 Realtime 断线
void showUnusedQrSheet(
  BuildContext context, {
  required String orderId,
  required String dealId,
  bool aggregateByDeal = false,
  Set<String> aggregatedOrderItemIds = const {},
  int initialPage = 0,
  String? initialUnusedOrderItemId,
}) {
  final hostContext = context;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _UnusedQrSheet(
      hostContext: hostContext,
      orderId: orderId,
      dealId: dealId,
      aggregateByDeal: aggregateByDeal,
      aggregatedOrderItemIds: aggregatedOrderItemIds,
      initialPage: initialPage,
      initialUnusedOrderItemId: initialUnusedOrderItemId,
    ),
  );
}

/// QR 弹层内复制券码：弹层会挡住底层 SnackBar，因此在行内显示「已复制」状态并辅以触觉反馈。
class _VoucherCodeCopyRow extends StatefulWidget {
  const _VoucherCodeCopyRow({
    required this.formattedCode,
    required this.hostContext,
  });

  final String formattedCode;
  final BuildContext hostContext;

  @override
  State<_VoucherCodeCopyRow> createState() => _VoucherCodeCopyRowState();
}

class _VoucherCodeCopyRowState extends State<_VoucherCodeCopyRow> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _onTap() async {
    await Clipboard.setData(ClipboardData(text: widget.formattedCode));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });

    const bar = SnackBar(
      content: Text('Coupon code copied'),
      duration: Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    );
    final host = widget.hostContext;
    if (host.mounted) {
      ScaffoldMessenger.maybeOf(host)?.showSnackBar(bar);
    }
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(bar);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.formattedCode,
              style: const TextStyle(
                fontSize: 16,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              _copied ? Icons.check_circle_rounded : Icons.copy_rounded,
              size: 18,
              color: _copied
                  ? const Color(0xFF2E7D32)
                  : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _UnusedQrSheet extends ConsumerStatefulWidget {
  /// 打开 QR 弹层的页面 context，用于关闭弹层后展示全屏成功与再次打开弹层
  final BuildContext hostContext;
  final String orderId;
  final String dealId;
  final bool aggregateByDeal;
  final Set<String> aggregatedOrderItemIds;
  final int initialPage;
  final String? initialUnusedOrderItemId;

  const _UnusedQrSheet({
    required this.hostContext,
    required this.orderId,
    required this.dealId,
    this.aggregateByDeal = false,
    this.aggregatedOrderItemIds = const {},
    this.initialPage = 0,
    this.initialUnusedOrderItemId,
  });

  @override
  ConsumerState<_UnusedQrSheet> createState() => _UnusedQrSheetState();
}

class _UnusedQrSheetState extends ConsumerState<_UnusedQrSheet> {
  late final PageController _pageController;
  int _currentPage = 0;
  Set<String>? _prevUnusedItemIds;
  bool _didAutoPopForEmptyOpen = false;
  bool _redemptionSuccessFlowScheduled = false;
  Timer? _pollTimer;
  /// 已将 [initialUnusedOrderItemId] 同步到 PageView 当前页
  bool _appliedInitialUnusedPage = false;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage);
    // 定期拉取，避免 Realtime 1002 等导致长时间停在旧 QR
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      invalidateUserCouponsEverywhere(ref.invalidate);
      if (widget.aggregateByDeal && widget.aggregatedOrderItemIds.isNotEmpty) {
        final key = aggregatedDealVoucherCacheKey(
            widget.dealId, widget.aggregatedOrderItemIds);
        ref.invalidate(aggregatedDealVoucherDetailProvider(key));
      } else {
        ref.invalidate(userOrderDetailProvider(widget.orderId));
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  /// 与 QR 内容区一致的外壳，避免 isScrollControlled 下 Center 撑满整屏
  Widget _buildSheetChrome({
    required Widget child,
    String? title,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          if (title != null) ...[
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
          ],
          child,
        ],
      ),
    );
  }

  /// 根据未使用 order_item id 集合变化检测核销：全屏成功 → 多张时关闭后再打开 QR
  void _onDealItemsUpdated({
    required List<OrderItemModel> dealItems,
    required List<OrderItemModel> unusedItems,
    required BuildContext sheetContext,
  }) {
    final currentIds = unusedItems.map((e) => e.id).toSet();
    final prevIds = _prevUnusedItemIds;

    if (prevIds == null) {
      _prevUnusedItemIds = currentIds;
      if (unusedItems.isEmpty && !_didAutoPopForEmptyOpen) {
        _didAutoPopForEmptyOpen = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.maybeOf(sheetContext)?.showSnackBar(
            const SnackBar(
              content: Text('This voucher has already been redeemed.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          if (Navigator.canPop(sheetContext)) Navigator.pop(sheetContext);
        });
      }
      return;
    }

    if (currentIds.length >= prevIds.length) {
      _prevUnusedItemIds = currentIds;
      return;
    }

    if (_redemptionSuccessFlowScheduled) return;
    _redemptionSuccessFlowScheduled = true;
    _prevUnusedItemIds = currentIds;

    final redeemedIdList = prevIds.difference(currentIds).toList();
    OrderItemModel? redeemedItem;
    for (final rid in redeemedIdList) {
      for (final i in dealItems) {
        if (i.id == rid) {
          redeemedItem = i;
          break;
        }
      }
      if (redeemedItem != null) break;
    }

    final dealTitle = redeemedItem?.dealTitle ?? 'Deal';
    final redeemedAt = redeemedItem?.redeemedAt ?? DateTime.now();
    final hasMoreUnused = unusedItems.isNotEmpty;
    final host = widget.hostContext;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!sheetContext.mounted) return;
      Navigator.of(sheetContext).pop();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!host.mounted) return;
      await showCustomerRedemptionSuccessDialog(
        context: host,
        dealTitle: dealTitle,
        redeemedAt: redeemedAt,
        primaryButtonLabel: hasMoreUnused ? 'Continue' : 'Done',
      );
      if (!host.mounted) return;
      if (hasMoreUnused) {
        showUnusedQrSheet(
          host,
          orderId: widget.orderId,
          dealId: widget.dealId,
          aggregateByDeal: widget.aggregateByDeal,
          aggregatedOrderItemIds: widget.aggregatedOrderItemIds,
        );
      }
    });
  }

  Widget _buildQrBody(BuildContext context, List<OrderItemModel> items) {
    final hasMultiple = items.length > 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasMultiple
                ? 'Voucher ${_currentPage + 1} of ${items.length}'
                : 'Scan to Redeem',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 340,
            child: PageView.builder(
              controller: _pageController,
              itemCount: items.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) {
                final item = items[i];
                final qrData = item.couponQrCode ?? item.couponCode ?? '';
                final formattedCode = item.formattedCouponCode;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: qrData.isNotEmpty
                          ? QrImageView(
                              data: qrData,
                              version: QrVersions.auto,
                              size: 200,
                              backgroundColor: Colors.white,
                            )
                          : const SizedBox(
                              width: 200,
                              height: 200,
                              child: Center(child: Text('QR code unavailable')),
                            ),
                    ),
                    const SizedBox(height: 16),
                    if (formattedCode != null)
                      _VoucherCodeCopyRow(
                        formattedCode: formattedCode,
                        hostContext: widget.hostContext,
                      ),
                  ],
                );
              },
            ),
          ),
          if (hasMultiple) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                  items.length,
                  (i) => Container(
                        width: i == _currentPage ? 20 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i == _currentPage
                              ? AppColors.primary
                              : AppColors.textHint.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aggKey = widget.aggregateByDeal &&
            widget.aggregatedOrderItemIds.isNotEmpty
        ? aggregatedDealVoucherCacheKey(
            widget.dealId, widget.aggregatedOrderItemIds)
        : null;

    final detailAsync = aggKey != null
        ? ref.watch(aggregatedDealVoucherDetailProvider(aggKey))
        : ref.watch(userOrderDetailProvider(widget.orderId));

    return detailAsync.when(
      skipLoadingOnReload: true,
      data: (detail) {
        final dealItems =
            detail.items.where((i) => i.dealId == widget.dealId).toList();
        final unusedItems = dealItems
            .where((i) => i.customerStatus == CustomerItemStatus.unused)
            .toList();

        _onDealItemsUpdated(
          dealItems: dealItems,
          unusedItems: unusedItems,
          sheetContext: context,
        );

        if (unusedItems.isNotEmpty && _currentPage >= unusedItems.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_pageController.hasClients) return;
            final target = unusedItems.length - 1;
            _pageController.jumpToPage(target);
            setState(() => _currentPage = target);
          });
        }

        // 从订单详情「点某张未用券」打开时，定位到对应 PageView 页
        if (!_appliedInitialUnusedPage &&
            widget.initialUnusedOrderItemId != null &&
            unusedItems.isNotEmpty) {
          final idx = unusedItems
              .indexWhere((e) => e.id == widget.initialUnusedOrderItemId);
          _appliedInitialUnusedPage = true;
          if (idx > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_pageController.hasClients) return;
              _pageController.jumpToPage(idx);
              setState(() => _currentPage = idx);
            });
          } else if (idx == 0) {
            setState(() => _currentPage = 0);
          }
        }

        if (unusedItems.isEmpty) {
          if (_redemptionSuccessFlowScheduled) {
            return _buildSheetChrome(
              title: 'Scan to Redeem',
              child: const SizedBox(
                height: 200,
                child: Center(
                  child: SizedBox(
                    height: 48,
                    width: 48,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            );
          }
          return _buildSheetChrome(
            title: 'Scan to Redeem',
            child: const SizedBox(
              height: 200,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Updating…',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return _buildQrBody(context, unusedItems);
      },
      loading: () => _buildSheetChrome(
        title: 'Scan to Redeem',
        child: const SizedBox(
          height: 320,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => _buildSheetChrome(
        title: 'Scan to Redeem',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Failed to load voucher',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                e.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  invalidateUserCouponsEverywhere(ref.invalidate);
                  if (aggKey != null) {
                    ref.invalidate(aggregatedDealVoucherDetailProvider(aggKey));
                  } else {
                    ref.invalidate(userOrderDetailProvider(widget.orderId));
                  }
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



// ── 主屏幕 ────────────────────────────────────────

class OrderDetailScreen extends ConsumerWidget {
  final String orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(userOrderDetailProvider(orderId));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: detailAsync.when(
        data: (detail) => _MeituanOrderBody(
          detail: detail,
          orderId: orderId,
        ),
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(
            title: const Text('Order Detail'),
            leading: backOrHomeAppBarLeading(context),
            automaticallyImplyLeading: false,
          ),
          body: _ErrorBody(
            onRetry: () {
              ref.invalidate(userOrderDetailProvider(orderId));
              ref.invalidate(afterSalesListProvider(orderId));
              ref.invalidate(afterSalesListProvider(null));
            },
            error: e,
          ),
        ),
      ),
    );
  }
}

// ── 错误占位 ──────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final VoidCallback onRetry;
  final Object error;

  const _ErrorBody({required this.onRetry, required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(
              'Failed to load order',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 美团风格主体（带 ConsumerStatefulWidget 控制展开状态） ──

class _MeituanOrderBody extends ConsumerStatefulWidget {
  final OrderDetailModel detail;
  final String orderId;

  const _MeituanOrderBody({required this.detail, required this.orderId});

  @override
  ConsumerState<_MeituanOrderBody> createState() => _MeituanOrderBodyState();
}

class _MeituanOrderBodyState extends ConsumerState<_MeituanOrderBody> with RouteAware {
  // 每个 deal 下 Unused / Used / Gifted 区块各自展开
  final Map<String, bool> _expandedUnusedByDeal = {};
  final Map<String, bool> _expandedUsedByDeal = {};
  final Map<String, bool> _expandedGiftedByDeal = {};

  OrderDetailModel get detail => widget.detail;

  /// 从售后子页返回或后台裁决后：强制失效售后缓存，避免长期显示旧状态
  void _invalidateAfterSalesForThisOrder() {
    final oid = widget.orderId;
    ref.invalidate(afterSalesListProvider(oid));
    ref.invalidate(afterSalesListProvider(null));
    ref.invalidate(afterSalesRequestProvider(oid));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _invalidateAfterSalesForThisOrder();
  }

  @override
  Widget build(BuildContext context) {
    // 按 deal_id 分组所有 items
    final groupMap = <String, List<OrderItemModel>>{};
    for (final item in detail.items) {
      groupMap.putIfAbsent(item.dealId, () => []).add(item);
    }

    return Stack(
      children: [
        // 主滚动区域
        CustomScrollView(
          slivers: [
            // 顶部 AppBar（显式返回：go 进页时栈上无上一屏也能回首页）
            SliverAppBar(
              pinned: true,
              leading: backOrHomeAppBarLeading(context),
              automaticallyImplyLeading: false,
              title: const Text(
                'Order Detail',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textPrimary,
              elevation: 0.5,
            ),

            // 每个 deal 分组：摘要卡片 + 券状态行
            ...groupMap.entries.map((entry) {
              final dealId = entry.key;
              final items = entry.value;
              final unusedExpanded = _expandedUnusedByDeal[dealId] ?? false;
              final usedExpanded = _expandedUsedByDeal[dealId] ?? false;
              final giftedExpanded = _expandedGiftedByDeal[dealId] ?? false;

              return SliverToBoxAdapter(
                child: _DealSummaryCard(
                  dealItems: items,
                  isUnusedExpanded: unusedExpanded,
                  onToggleUnusedExpand: () {
                    setState(() {
                      _expandedUnusedByDeal[dealId] = !unusedExpanded;
                    });
                  },
                  isUsedExpanded: usedExpanded,
                  onToggleUsedExpand: () {
                    setState(() {
                      _expandedUsedByDeal[dealId] = !usedExpanded;
                    });
                  },
                  isGiftedExpanded: giftedExpanded,
                  onToggleGiftedExpand: () {
                    setState(() {
                      _expandedGiftedByDeal[dealId] = !giftedExpanded;
                    });
                  },
                  orderId: widget.orderId,
                  paymentIntentId: detail.paymentIntentIdMasked,
                  storeCreditUsed: detail.storeCreditUsed,
                  orderTotalAmount: detail.totalAmount,
                  onRefreshOrder: () {
                    ref.invalidate(userOrderDetailProvider(widget.orderId));
                    ref.invalidate(afterSalesListProvider(widget.orderId));
                    ref.invalidate(afterSalesListProvider(null));
                  },
                ),
              );
            }),

            // Order Info 区块
            SliverToBoxAdapter(
              child: _OrderInfoSection(detail: detail),
            ),

            // 底部留白（为固定底部按钮留空间）
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),

        // 固定底部操作栏
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BottomActionBar(
            detail: detail,
            orderId: widget.orderId,
          ),
        ),
      ],
    );
  }
}

// ── Deal 摘要卡片（含券状态展开行） ───────────────

class _DealSummaryCard extends ConsumerWidget {
  final List<OrderItemModel> dealItems;
  final bool isUnusedExpanded;
  final VoidCallback onToggleUnusedExpand;
  final bool isUsedExpanded;
  final VoidCallback onToggleUsedExpand;
  final bool isGiftedExpanded;
  final VoidCallback onToggleGiftedExpand;
  final VoidCallback onRefreshOrder;
  final String? paymentIntentId;
  final String orderId;
  /// 本单使用的 Store Credit 金额
  final double storeCreditUsed;
  /// 订单原始总金额（未扣 Store Credit）
  final double orderTotalAmount;

  const _DealSummaryCard({
    required this.dealItems,
    required this.isUnusedExpanded,
    required this.onToggleUnusedExpand,
    required this.isUsedExpanded,
    required this.onToggleUsedExpand,
    required this.isGiftedExpanded,
    required this.onToggleGiftedExpand,
    required this.onRefreshOrder,
    required this.orderId,
    this.paymentIntentId,
    this.storeCreditUsed = 0.0,
    this.orderTotalAmount = 0.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = dealItems.first;
    final count = dealItems.length;
    final amountFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    final afterSalesAsync = ref.watch(afterSalesListProvider(orderId));
    final afterSalesByCoupon = afterSalesAsync.maybeWhen(
      data: latestAfterSalesByCouponId,
      orElse: () => <String, AfterSalesRequestModel>{},
    );

    // 计算已付总价（不含 service fee）
    final totalPaid = dealItems.fold<double>(0, (s, i) => s + i.unitPrice);
    final merchantName = first.merchantName ?? first.purchasedMerchantName;

    // 按状态分组（用于显示 "Unused (2)" 等）
    final unusedItems =
        dealItems.where((i) => i.customerStatus == CustomerItemStatus.unused).toList();
    final usedItems =
        dealItems.where((i) => i.customerStatus == CustomerItemStatus.used).toList();
    final giftedItems =
        dealItems.where((i) => i.customerStatus == CustomerItemStatus.gifted).toList();
    final refundedItems = dealItems
        .where((i) =>
            i.customerStatus == CustomerItemStatus.refundSuccess ||
            i.customerStatus == CustomerItemStatus.refundPending ||
            i.customerStatus == CustomerItemStatus.refundProcessing ||
            i.customerStatus == CustomerItemStatus.refundReview)
        .toList();
    final otherItems = dealItems
        .where((i) =>
            i.customerStatus != CustomerItemStatus.unused &&
            i.customerStatus != CustomerItemStatus.used &&
            i.customerStatus != CustomerItemStatus.gifted &&
            i.customerStatus != CustomerItemStatus.refundSuccess &&
            i.customerStatus != CustomerItemStatus.refundPending &&
            i.customerStatus != CustomerItemStatus.refundProcessing &&
            i.customerStatus != CustomerItemStatus.refundReview)
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Deal 摘要行：图片 + 标题 + 商家 + 有效期 + 价格
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Deal 封面图
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: first.dealImageUrl != null
                      ? Image.network(
                          first.dealImageUrl!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, _) => _PlaceholderImage(),
                        )
                      : _PlaceholderImage(),
                ),
                const SizedBox(width: 12),
                // 文字信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        first.dealTitle,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (merchantName != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          merchantName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      if (first.couponExpiresAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Valid until ${DateFormat('MMM d, yyyy').format(first.couponExpiresAt!.toUtc())} (CT)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // 价格行
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${amountFmt.format(first.unitPrice)} × $count',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            'Paid ${amountFmt.format(totalPaid)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Builder(
                        builder: (context) {
                          final n = dealItems
                              .where(
                                (i) =>
                                    i.couponId != null &&
                                    i.couponId!.isNotEmpty &&
                                    afterSalesByCoupon.containsKey(i.couponId!),
                              )
                              .length;
                          if (n == 0) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.support_agent_outlined,
                                    size: 16,
                                    color: AppColors.warning,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    n == 1
                                        ? 'After-sales in progress for 1 voucher below.'
                                        : 'After-sales in progress for $n vouchers below.',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 券状态汇总行（美团风格）
          if (unusedItems.isNotEmpty)
            _CouponStatusRow(
              label: 'Unused',
              count: unusedItems.length,
              color: const Color(0xFF00C853),
              items: unusedItems,
              isExpanded: isUnusedExpanded,
              onToggle: onToggleUnusedExpand,
              onRefreshOrder: onRefreshOrder,
              orderId: orderId,
              paymentIntentId: paymentIntentId,
              storeCreditUsed: storeCreditUsed,
              orderTotalAmount: orderTotalAmount,
              afterSalesByCoupon: afterSalesByCoupon,
            ),
          if (usedItems.isNotEmpty)
            _CouponStatusRow(
              label: 'Used',
              count: usedItems.length,
              color: const Color(0xFF2979FF),
              items: usedItems,
              isExpanded: isUsedExpanded,
              onToggle: onToggleUsedExpand,
              onRefreshOrder: onRefreshOrder,
              orderId: orderId,
              paymentIntentId: paymentIntentId,
              storeCreditUsed: storeCreditUsed,
              orderTotalAmount: orderTotalAmount,
              afterSalesByCoupon: afterSalesByCoupon,
            ),
          if (giftedItems.isNotEmpty)
            _CouponStatusRow(
              label: 'Gifted',
              count: giftedItems.length,
              color: AppColors.secondary,
              items: giftedItems,
              isExpanded: isGiftedExpanded,
              onToggle: onToggleGiftedExpand,
              onRefreshOrder: onRefreshOrder,
              orderId: orderId,
              paymentIntentId: paymentIntentId,
              storeCreditUsed: storeCreditUsed,
              orderTotalAmount: orderTotalAmount,
              afterSalesByCoupon: afterSalesByCoupon,
            ),
          if (refundedItems.isNotEmpty)
            _CouponStatusRow(
              label: (refundedItems.first.customerStatus == CustomerItemStatus.refundPending ||
                      refundedItems.first.customerStatus == CustomerItemStatus.refundProcessing ||
                      refundedItems.first.customerStatus == CustomerItemStatus.refundReview)
                  ? 'Refund Processing'
                  : 'Refunded',
              count: refundedItems.length,
              color: const Color(0xFF9E9E9E),
              items: refundedItems,
              isExpanded: false,
              onToggle: null,
              onRefreshOrder: onRefreshOrder,
              orderId: orderId,
              paymentIntentId: paymentIntentId,
              storeCreditUsed: storeCreditUsed,
              orderTotalAmount: orderTotalAmount,
              afterSalesByCoupon: afterSalesByCoupon,
            ),
          if (otherItems.isNotEmpty)
            _CouponStatusRow(
              label: otherItems.first.customerStatus.displayLabel,
              count: otherItems.length,
              color: AppColors.textHint,
              items: otherItems,
              isExpanded: false,
              onToggle: null,
              onRefreshOrder: onRefreshOrder,
              orderId: orderId,
              paymentIntentId: paymentIntentId,
              storeCreditUsed: storeCreditUsed,
              orderTotalAmount: orderTotalAmount,
              afterSalesByCoupon: afterSalesByCoupon,
            ),
        ],
      ),
    );
  }
}

// ── 券状态行（可展开） ────────────────────────────

class _CouponStatusRow extends ConsumerWidget {
  final String label;
  final int count;
  final Color color;
  final List<OrderItemModel> items;
  final bool isExpanded;
  final VoidCallback? onToggle;
  final VoidCallback onRefreshOrder;
  final String orderId;
  final String? paymentIntentId;
  /// 本单使用的 Store Credit 金额
  final double storeCreditUsed;
  /// 订单原始总金额（未扣 Store Credit）
  final double orderTotalAmount;
  /// couponId → 最新售后（订单详情逐券标识）
  final Map<String, AfterSalesRequestModel> afterSalesByCoupon;

  const _CouponStatusRow({
    required this.label,
    required this.count,
    required this.color,
    required this.items,
    required this.isExpanded,
    required this.onToggle,
    required this.onRefreshOrder,
    required this.orderId,
    this.paymentIntentId,
    this.storeCreditUsed = 0.0,
    this.orderTotalAmount = 0.0,
    this.afterSalesByCoupon = const <String, AfterSalesRequestModel>{},
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final afterSalesInSection = items
        .where(
          (i) =>
              i.couponId != null &&
              i.couponId!.isNotEmpty &&
              afterSalesByCoupon.containsKey(i.couponId!),
        )
        .length;

    return Column(
      children: [
        // 状态行标题
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$label ($count)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (afterSalesInSection > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      afterSalesInSection == 1
                          ? 'After-sales ×1'
                          : 'After-sales ×$afterSalesInSection',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (onToggle != null) ...[
                  Text(
                    'View Details',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ],
            ),
          ),
        ),

        // 展开后：每张券的详情
        if (isExpanded && onToggle != null) ...[
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          ...items.map((item) => _CouponDetailRow(
                item: item,
                allItems: items,
                orderId: orderId,
                paymentIntentId: paymentIntentId,
                onRefreshOrder: onRefreshOrder,
                storeCreditUsed: storeCreditUsed,
                orderTotalAmount: orderTotalAmount,
                afterSalesByCoupon: afterSalesByCoupon,
              )),
        ],

        const Divider(height: 1, color: Color(0xFFF0F0F0)),
      ],
    );
  }
}

// ── 单张券详情行 ──────────────────────────────────

class _CouponDetailRow extends ConsumerWidget {
  final OrderItemModel item;
  final List<OrderItemModel> allItems;
  final String orderId;
  final String? paymentIntentId;
  final VoidCallback onRefreshOrder;
  /// 本单使用的 Store Credit 金额
  final double storeCreditUsed;
  /// 订单原始总金额（未扣 Store Credit）
  final double orderTotalAmount;
  final Map<String, AfterSalesRequestModel> afterSalesByCoupon;

  const _CouponDetailRow({
    required this.item,
    required this.allItems,
    required this.orderId,
    this.paymentIntentId,
    required this.onRefreshOrder,
    this.storeCreditUsed = 0.0,
    this.orderTotalAmount = 0.0,
    this.afterSalesByCoupon = const <String, AfterSalesRequestModel>{},
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formattedCode = item.formattedCouponCode;

    return GestureDetector(
      onTap: () {
        // 赠送出去的券跳转到 coupon 详情页（显示 gift 信息）
        if (item.customerStatus == CustomerItemStatus.gifted && item.couponId != null) {
          context.push('/coupon/${item.couponId}');
        } else if (item.customerStatus == CustomerItemStatus.unused) {
          // 未使用：先列表展开后，点行再出示 QR（与 Used 展开体验一致）
          showUnusedQrSheet(
            context,
            orderId: orderId,
            dealId: item.dealId,
            initialUnusedOrderItemId: item.id,
          );
        } else {
          // 其他状态跳转到 voucher detail 页面
          context.push('/voucher/$orderId?dealId=${item.dealId}');
        }
      },
      child: Container(
        color: const Color(0xFFFAFAFA),
        padding: const EdgeInsets.fromLTRB(24, 12, 16, 12),
        child: Row(
          children: [
            // 券码（可点击跳转 voucher detail）
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (formattedCode != null)
                        Text(
                          formattedCode,
                          style: const TextStyle(
                            fontSize: 14,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: AppColors.primary,
                          ),
                        )
                      else
                        const Text(
                          'No code',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textHint),
                        ),
                      const SizedBox(width: 4),
                      Icon(
                        item.customerStatus == CustomerItemStatus.unused
                            ? Icons.qr_code_2_rounded
                            : Icons.arrow_forward_ios,
                        size: item.customerStatus == CustomerItemStatus.unused
                            ? 18
                            : 12,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                  if (item.customerStatus == CustomerItemStatus.unused) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Tap to show QR',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                  if (item.redeemedAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Used ${DateFormat('MMM d, yyyy').format(item.redeemedAt!.toLocal())}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textHint),
                    ),
                  ],
                  if (item.tipAmountUsd != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.tipPaidAt != null
                          ? 'Tip \$${item.tipAmountUsd!.toStringAsFixed(2)} · paid ${DateFormat('MMM d, yyyy').format(item.tipPaidAt!.toLocal())}'
                          : 'Tip \$${item.tipAmountUsd!.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                  if (item.couponId != null && item.couponId!.isNotEmpty) ...[
                    Builder(
                      builder: (context) {
                        final req = afterSalesByCoupon[item.couponId!];
                        if (req == null) return const SizedBox.shrink();
                        final bucket = AfterSalesOrderCardBucket.fromStatus(req.status);
                        final accent = switch (bucket) {
                          AfterSalesOrderCardBucket.pending => AppColors.warning,
                          AfterSalesOrderCardBucket.rejected => AppColors.textSecondary,
                          AfterSalesOrderCardBucket.approved => AppColors.success,
                        };
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: GestureDetector(
                            onTap: () => context.push('/after-sales/$orderId'),
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.support_agent_outlined, size: 15, color: accent),
                                const SizedBox(width: 4),
                                Text(
                                  'After-sales · ${bucket.shortLabel}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(Icons.chevron_right, size: 14, color: AppColors.textHint),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  // 赠送信息（gifted 状态时显示受赠方）
                  if (item.customerStatus == CustomerItemStatus.gifted &&
                      item.activeGift != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Gifted to ${item.activeGift!.recipientDisplay}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 操作按钮
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.showCancel)
                  _SmallButton(
                    label: 'Cancel',
                    color: AppColors.error,
                    onTap: () => _showCancelSheet(context, ref, item),
                  ),
                if (showRefundButtonConsideringAfterSales(item, afterSalesByCoupon))
                  _SmallButton(
                    label: 'Refund',
                    color: AppColors.warning,
                    onTap: () => showUsedRefundEntry(context, ref, item),
                  ),
                if (item.showWriteReview)
                  _SmallButton(
                    label: 'Review',
                    color: AppColors.accent,
                    onTap: () {
                      // 评价关联到实际核销门店（连锁店场景下可能与购买门店不同）
                      final merchantId = item.redeemedMerchantId ?? item.purchasedMerchantId ?? '';
                      context.push('/review/${item.dealId}?merchantId=$merchantId&orderItemId=${item.id}');
                    },
                  ),
                // 赠送按钮（未使用且未赠出）
                if (item.showGift)
                  _SmallButton(
                    label: 'Gift',
                    color: AppColors.secondary,
                    onTap: () => GiftBottomSheet.show(
                      context,
                      dealTitle: item.dealTitle,
                      merchantName: item.merchantName,
                      expiresAt: item.couponExpiresAt,
                      orderItemId: item.id,
                      onGiftSent: onRefreshOrder,
                    ),
                  ),
                // 撤回赠送按钮（已赠出 + pending）
                if (item.showRecallGift)
                  _SmallButton(
                    label: 'Recall',
                    color: AppColors.warning,
                    onTap: () => _showRecallConfirm(context, ref, item),
                  ),
                // 修改受赠方按钮（已赠出 + pending）
                if (item.showEditRecipient)
                  _SmallButton(
                    label: 'Edit',
                    color: AppColors.info,
                    onTap: () => GiftBottomSheet.show(
                      context,
                      dealTitle: item.dealTitle,
                      merchantName: item.merchantName,
                      expiresAt: item.couponExpiresAt,
                      orderItemId: item.id,
                      prefillEmail: item.activeGift?.recipientEmail,
                      prefillPhone: item.activeGift?.recipientPhone,
                      onGiftSent: onRefreshOrder,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 撤回赠送确认弹窗
  void _showRecallConfirm(
      BuildContext context, WidgetRef ref, OrderItemModel item) {
    final gift = item.activeGift;
    if (gift == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recall this gift?'),
        content: Text(
          'The coupon will be returned to your account.\n'
          '${gift.recipientDisplay} will no longer be able to use it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final success = await ref
                  .read(giftNotifierProvider.notifier)
                  .recallGift(gift.id);
              if (context.mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Gift recalled successfully')),
                  );
                  onRefreshOrder();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to recall gift'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Confirm Recall'),
          ),
        ],
      ),
    );
  }

  // 展示取消/退款 Bottom Sheet
  void _showCancelSheet(
      BuildContext context, WidgetRef ref, OrderItemModel item) {
    // 找同 deal 的所有 unused items（同 order 同 deal 可选数量退）
    final sameDealUnused = allItems
        .where((i) => i.dealId == item.dealId && i.customerStatus == CustomerItemStatus.unused)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CancelSheet(
        item: item,
        totalUnusedCount: sameDealUnused.length,
        allUnusedItems: sameDealUnused,
        paymentIntentId: paymentIntentId,
        storeCreditUsed: storeCreditUsed,
        orderTotalAmount: orderTotalAmount,
        onConfirm: (refundMethod, {int cancelCount = 1, List<String>? selectedItemIds}) async {
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final List<OrderItemModel> itemsToCancel;
          if (selectedItemIds != null && selectedItemIds.isNotEmpty) {
            final idSet = selectedItemIds.toSet();
            itemsToCancel = sameDealUnused.where((i) => idSet.contains(i.id)).toList();
          } else {
            itemsToCancel = sameDealUnused.take(cancelCount).toList();
          }
          int successCount = 0;
          for (final cancelItem in itemsToCancel) {
            final ok = await ref
                .read(refundNotifierProvider.notifier)
                .requestItemRefund(
                  cancelItem.id,
                  refundMethod: refundMethod,
                );
            if (ok) successCount++;
          }
          navigator.pop();
          if (successCount > 0) {
            final String msg =
                '$successCount voucher${successCount > 1 ? 's' : ''} cancelled successfully';
            messenger.showSnackBar(
              SnackBar(
                content: Text(msg),
                behavior: SnackBarBehavior.floating,
              ),
            );
            onRefreshOrder();
          } else {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Failed to cancel voucher'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
      ),
    );
  }
}

// ── 小尺寸操作按钮 ────────────────────────────────

class _SmallButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SmallButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}


// ── Order Info 区块 ───────────────────────────────

class _OrderInfoSection extends StatelessWidget {
  final OrderDetailModel detail;

  const _OrderInfoSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    final amountFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    // 计算 service fee 总额
    final totalServiceFee =
        detail.items.fold<double>(0, (s, i) => s + i.serviceFee);

    // Tax 显示值：优先用 order.taxAmount，其次 items 合计，否则从 total_amount 反推
    // 反推是为了兼容老订单（tax_amount 没保存但 total_amount 已包含税）
    final itemsTaxSum = detail.items.fold<double>(0, (s, i) => s + i.taxAmount);
    final subtotalSum = detail.items.fold<double>(0, (s, i) => s + i.unitPrice);
    final savedTax = detail.taxAmount > 0 ? detail.taxAmount : itemsTaxSum;
    // 反推的税：total - subtotal - service_fee（负数视为 0）
    final impliedTax = (detail.totalAmount - subtotalSum - totalServiceFee)
        .clamp(0.0, double.infinity);
    // 取较大者：优先显示 DB 保存值，若保存值为 0 而存在反推值则用反推值（老订单兜底）
    final displayTax = savedTax > 0 ? savedTax : impliedTax;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Info',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // 订单号（可复制）
          _InfoRowCopy(
            label: 'Order Number',
            value: detail.orderNumber,
            canCopy: true,
          ),

          // 下单时间
          _InfoRowCopy(
            label: 'Ordered',
            value: DateFormat('MMM d, yyyy · h:mm a')
                .format(detail.createdAt.toLocal()),
            canCopy: false,
          ),

          // 支付方式
          _InfoRowCopy(
            label: 'Payment',
            value: _resolvePaymentMethod(detail),
            canCopy: false,
          ),

          const Divider(height: 20, color: Color(0xFFF0F0F0)),

          // ── 费用明细 ──────────────────────────────────────
          const Text('Price Breakdown',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 8),

          // 每个 deal 的价格
          ...detail.items.fold<Map<String, _DealPriceSummary>>({}, (map, item) {
            final title = item.dealTitle.isNotEmpty ? item.dealTitle : 'Deal';
            map.putIfAbsent(title, () => _DealPriceSummary(title: title, unitPrice: item.unitPrice));
            map[title]!.count++;
            return map;
          }).values.map((d) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(
                  '${d.title} × ${d.count}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                )),
                Text(amountFmt.format(d.unitPrice * d.count),
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          )),

          // Service Fee
          if (totalServiceFee > 0)
            _SimpleRow('Service Fee (\$0.99 × ${detail.items.length})',
                amountFmt.format(totalServiceFee)),

          // Tax（优先用 DB 保存值；老订单 tax_amount 未保存时从 total 反推显示）
          if (displayTax > 0) _SimpleRow('Tax', amountFmt.format(displayTax)),

          const Divider(height: 16, color: Color(0xFFF0F0F0)),

          // Total
          _SimpleRow('Total', amountFmt.format(detail.totalAmount),
              isBold: true, valueColor: AppColors.textPrimary),

          const SizedBox(height: 8),

          // ── 支付方式明细 ────────────────────────────────────
          const Text('Payment',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 8),

          // Store Credit 支付
          if (detail.storeCreditUsed > 0)
            _SimpleRow('Store Credit', amountFmt.format(detail.storeCreditUsed),
                valueColor: AppColors.success),

          // Card / Google Pay 支付（总额减去 Store Credit）
          if (detail.totalAmount - detail.storeCreditUsed > 0)
            _SimpleRow(
              _resolvePaymentMethod(detail),
              amountFmt.format(detail.totalAmount - detail.storeCreditUsed),
            ),

          // 全额 Store Credit 时
          if (detail.totalAmount - detail.storeCreditUsed <= 0 && detail.storeCreditUsed > 0)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('Fully paid by Store Credit',
                  style: TextStyle(fontSize: 12, color: AppColors.success, fontStyle: FontStyle.italic)),
            ),

          // ── 退款信息 ──────────────────────────────────────
          ...(() {
            final refundedItems = detail.items
                .where((i) => i.customerStatus == CustomerItemStatus.refundSuccess ||
                    i.customerStatus == CustomerItemStatus.refundPending ||
                    i.customerStatus == CustomerItemStatus.refundProcessing)
                .toList();
            if (refundedItems.isEmpty) return <Widget>[];

            final totalRefund = refundedItems.fold<double>(0, (s, i) => s + (i.refundAmount ?? i.unitPrice));
            // 退款分项（与后端 create-refund 的逻辑对齐）：
            //   store_credit 路径：退 unit_price + full tax + service_fee（平台补偿用户）
            //   original_payment 路径：退 unit_price + tax_on_deal，不退 service_fee 和它对应的税
            // UI 按每个 item 的实际 refundAmount 判断是哪种情况，显示真实分项
            double dealPriceRefund = 0;
            double taxRefund = 0;              // 已退的税（deal 对应部分，有时含 fee 部分）
            double serviceFeeRefund = 0;        // 已退的 service fee（store_credit 路径）
            double nonRefundedServiceFee = 0;   // 未退的 service fee（original_payment 路径）
            double nonRefundableTaxSum = 0;     // 未退的 service fee 对应税

            for (final i in refundedItems) {
              // tax_amount 优先用 DB 保存值，兜底从 refundAmount - unitPrice 反推
              var itemTax = i.taxAmount;
              if (itemTax <= 0 && i.refundAmount != null && i.refundAmount! > i.unitPrice) {
                itemTax = i.refundAmount! - i.unitPrice;
              }
              // 把 tax 按 unit_price / service_fee 比例拆分
              final base = i.unitPrice + i.serviceFee;
              final taxOnDeal = (base > 0)
                  ? (itemTax * (i.unitPrice / base) * 100).round() / 100
                  : itemTax;
              final taxOnFee = (itemTax - taxOnDeal).clamp(0.0, double.infinity);

              dealPriceRefund += i.unitPrice;

              // 判断这个 item 是否属于全额退（store_credit 路径）：
              // refundAmount 接近 unit_price + itemTax + service_fee → 全退
              final fullAllowance = i.unitPrice + itemTax + i.serviceFee;
              final actual = i.refundAmount ?? i.unitPrice;
              final isFullRefund = actual >= fullAllowance - 0.01;

              if (isFullRefund) {
                taxRefund += itemTax;
                serviceFeeRefund += i.serviceFee;
              } else {
                taxRefund += taxOnDeal;
                nonRefundedServiceFee += i.serviceFee;
                nonRefundableTaxSum += taxOnFee;
              }
            }

            final storeCreditRefunds = refundedItems
                .where((i) =>
                    i.refundMethod == 'store_credit' &&
                    i.customerStatus == CustomerItemStatus.refundSuccess)
                .toList();
            final originalRefunds = refundedItems
                .where((i) =>
                    i.refundMethod == 'original_payment' &&
                    i.customerStatus == CustomerItemStatus.refundSuccess)
                .toList();
            final pendingRefunds = refundedItems
                .where((i) =>
                    i.customerStatus == CustomerItemStatus.refundPending ||
                    i.customerStatus == CustomerItemStatus.refundProcessing)
                .toList();

            return <Widget>[
              const Divider(height: 20, color: Color(0xFFF0F0F0)),
              const Text('Refunds',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 8),

              // 分项明细（始终显示，让用户清楚退了什么）
              _SimpleRow(
                'Deal Price Refunded (${refundedItems.length} voucher${refundedItems.length > 1 ? "s" : ""})',
                amountFmt.format(dealPriceRefund),
              ),
              if (taxRefund > 0)
                _SimpleRow('Tax Refunded', amountFmt.format(taxRefund)),
              if (serviceFeeRefund > 0)
                _SimpleRow(
                  'Service Fee Refunded',
                  amountFmt.format(serviceFeeRefund),
                ),
              if (nonRefundedServiceFee > 0)
                _SimpleRow(
                  'Service Fee (non-refundable)',
                  '−${amountFmt.format(nonRefundedServiceFee)}',
                  valueColor: AppColors.textSecondary,
                ),
              if (nonRefundableTaxSum > 0)
                _SimpleRow(
                  'Tax on Service Fee (non-refundable)',
                  '−${amountFmt.format(nonRefundableTaxSum)}',
                  valueColor: AppColors.textSecondary,
                ),

              const Divider(height: 16, color: Color(0xFFF0F0F0)),

              // 按退款去向分组
              if (storeCreditRefunds.isNotEmpty)
                _SimpleRow(
                  'To Store Credit (${storeCreditRefunds.length} voucher${storeCreditRefunds.length > 1 ? "s" : ""})',
                  amountFmt.format(storeCreditRefunds.fold<double>(0, (s, i) => s + (i.refundAmount ?? i.unitPrice))),
                  valueColor: AppColors.success,
                ),

              if (originalRefunds.isNotEmpty)
                _SimpleRow(
                  'To Original Payment (${originalRefunds.length})',
                  amountFmt.format(originalRefunds.fold<double>(0, (s, i) => s + (i.refundAmount ?? i.unitPrice))),
                ),

              if (pendingRefunds.isNotEmpty)
                _SimpleRow(
                  'Refund Processing (${pendingRefunds.length})',
                  amountFmt.format(pendingRefunds.fold<double>(0, (s, i) => s + (i.refundAmount ?? i.unitPrice))),
                  valueColor: AppColors.warning,
                ),

              _SimpleRow('Total Refunded', amountFmt.format(totalRefund),
                  isBold: true, valueColor: AppColors.error),

              // 额外说明：service fee 及其税不退原因
              if (nonRefundedServiceFee > 0)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Service fee and the tax on the service fee are non-refundable '
                    'when refunding to the original payment method.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ];
          })(),
        ],
      ),
    );
  }

  bool _isPaidByStoreCredit(OrderDetailModel detail) {
    // 全额 Store Credit：store_credit_used >= total_amount
    return detail.storeCreditUsed > 0 &&
        detail.storeCreditUsed >= detail.totalAmount;
  }

  String _resolvePaymentMethod(OrderDetailModel detail) {
    if (_isPaidByStoreCredit(detail)) return 'Store Credit';
    final status = detail.paymentStatus ?? '';
    return switch (status.toLowerCase()) {
      'succeeded' => 'Credit Card',
      'paid' => 'Credit Card',
      _ => status.isNotEmpty
          ? status[0].toUpperCase() + status.substring(1)
          : 'Credit Card',
    };
  }
}

// ── 信息行（带可选复制） ──────────────────────────

class _InfoRowCopy extends StatelessWidget {
  final String label;
  final String value;
  final bool canCopy;
  final TextStyle? valueStyle;

  const _InfoRowCopy({
    required this.label,
    required this.value,
    required this.canCopy,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: valueStyle ?? const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (canCopy)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied to clipboard'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.copy_rounded,
                  size: 15,
                  color: AppColors.textHint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 价格行 ────────────────────────────────────────

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;

  const _PriceRow({
    required this.label,
    required this.value,
    required this.isTotal,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 14 : 13,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w400,
              color: isTotal ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 16 : 13,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
              color: isTotal ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 底部固定操作栏 ────────────────────────────────

class _BottomActionBar extends ConsumerWidget {
  final OrderDetailModel detail;
  final String orderId;

  const _BottomActionBar({required this.detail, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 找到所有可取消的 item
    final cancelableItems =
        detail.items.where((i) => i.showCancel).toList();
    final hasUnused = cancelableItems.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          // Cancel 按钮（有 unused 才显示）
          if (hasUnused) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: () => _showBatchCancelSheet(
                    context, ref, cancelableItems.first),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error),
                  foregroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Buy Again 按钮
          Expanded(
            flex: hasUnused ? 1 : 2,
            child: ElevatedButton(
              onPressed: () => _handleBuyAgain(context, ref),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Buy Again',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Buy Again：将订单券重新加入购物车并跳转结账 ─────────────
  Future<void> _handleBuyAgain(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    // 显示加载指示器
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    try {
      final dealsRepo = ref.read(dealsRepositoryProvider);
      final cartNotifier = ref.read(cartProvider.notifier);

      // 按 dealId 分组订单项
      final itemsByDeal = <String, List<OrderItemModel>>{};
      for (final item in detail.items) {
        itemsByDeal.putIfAbsent(item.dealId, () => []).add(item);
      }

      final unavailableDeals = <String>[]; // 不可购买的 deal 标题
      final itemsToAdd = <OrderItemBuyAgainData>[]; // 要加入购物车的数据

      for (final entry in itemsByDeal.entries) {
        final dealId = entry.key;
        final orderItems = entry.value;

        try {
          final deal = await dealsRepo.fetchDealById(dealId);

          // 检查是否已过期
          if (deal.isExpired) {
            unavailableDeals.add(deal.title);
            continue;
          }

          // 检查限购：查询用户已购买该 deal 的数量（未退款的）
          int allowCount = orderItems.length;
          if (deal.maxPerAccount > 0) {
            final userId = Supabase.instance.client.auth.currentUser?.id;
            if (userId != null) {
              final res = await Supabase.instance.client
                  .from('order_items')
                  .select('id, orders!inner(user_id)')
                  .eq('deal_id', dealId)
                  .eq('orders.user_id', userId)
                  .neq('customer_status', 'refund_success');
              final purchasedCount = (res as List).length;

              // 也算上购物车中已有的
              final cartItems = ref.read(cartProvider).valueOrNull ?? [];
              final cartCount =
                  cartItems.where((c) => c.dealId == dealId).length;

              final remaining =
                  deal.maxPerAccount - purchasedCount - cartCount;
              if (remaining <= 0) {
                unavailableDeals.add(
                    '${deal.title} (purchase limit reached)');
                continue;
              }
              allowCount = remaining < orderItems.length
                  ? remaining
                  : orderItems.length;
            }
          }

          // 收集要加入购物车的数据
          for (var i = 0; i < allowCount; i++) {
            final oi = orderItems[i];
            itemsToAdd.add(OrderItemBuyAgainData(
              dealId: oi.dealId,
              unitPrice: oi.unitPrice,
              purchasedMerchantId: oi.purchasedMerchantId,
              applicableStoreIds: oi.applicableStoreIds,
              selectedOptions: oi.selectedOptions,
            ));
          }

          // 如果因限购只能加入部分
          if (allowCount < orderItems.length) {
            final skipped = orderItems.length - allowCount;
            unavailableDeals.add(
                '${deal.title} ($skipped coupon(s) skipped due to purchase limit)');
          }
        } catch (_) {
          // deal 不存在或查询失败
          unavailableDeals.add(orderItems.first.dealTitle);
        }
      }

      // 关闭 loading
      navigator.pop();

      // 没有可加入的券
      if (itemsToAdd.isEmpty) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
              'None of the deals in this order are available for purchase.'),
        ));
        return;
      }

      // 批量加入购物车
      final addedItems = await cartNotifier.addBulkFromOrderItems(itemsToAdd);

      // 显示不可购买的提示
      if (unavailableDeals.isNotEmpty) {
        messenger.showSnackBar(SnackBar(
          content: Text(
            'Some items are unavailable: ${unavailableDeals.join("; ")}',
          ),
          duration: const Duration(seconds: 4),
        ));
      }

      // 跳转到结账页，传入刚添加的购物车项
      if (addedItems.isNotEmpty) {
        router.push('/checkout-cart', extra: addedItems);
      }
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text('Failed to re-order: $e'),
      ));
    }
  }

  // 显示取消 Bottom Sheet（第一张 unused 券）
  void _showBatchCancelSheet(
      BuildContext context, WidgetRef ref, OrderItemModel item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        // 所有 unused 的券
        final allUnused = detail.items
            .where((i) => i.showCancel)
            .toList();
        return _CancelSheet(
          item: item,
          totalUnusedCount: allUnused.length,
          allUnusedItems: allUnused,
          paymentIntentId: detail.paymentIntentIdMasked,
          storeCreditUsed: detail.storeCreditUsed,
          orderTotalAmount: detail.totalAmount,
          onConfirm: (refundMethod, {int cancelCount = 1, List<String>? selectedItemIds}) async {
            final navigator = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            // 优先用用户选中的券 id，否则降级为取前 N 张
            final List<OrderItemModel> itemsToCancel;
            if (selectedItemIds != null && selectedItemIds.isNotEmpty) {
              final idSet = selectedItemIds.toSet();
              itemsToCancel = allUnused.where((i) => idSet.contains(i.id)).toList();
            } else {
              itemsToCancel = allUnused.take(cancelCount).toList();
            }
            int successCount = 0;
            for (final cancelItem in itemsToCancel) {
              final ok = await ref
                  .read(refundNotifierProvider.notifier)
                  .requestItemRefund(cancelItem.id, refundMethod: refundMethod);
              if (ok) successCount++;
            }
            navigator.pop();
            if (successCount > 0) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text('$successCount voucher${successCount > 1 ? 's' : ''} cancelled'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              ref.invalidate(userOrderDetailProvider(orderId));
            } else {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Failed to cancel'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.error,
                ),
              );
            }
          },
        );
      },
    );
  }
}

// ── Deal 图片占位符 ───────────────────────────────

class _PlaceholderImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      color: AppColors.surfaceVariant,
      child: const Icon(
        Icons.local_offer_outlined,
        color: AppColors.textHint,
        size: 32,
      ),
    );
  }
}

// ── Cancel / Refund Bottom Sheet ──────────────────

class _CancelSheet extends ConsumerStatefulWidget {
  final OrderItemModel item;
  final int totalUnusedCount;
  final List<OrderItemModel> allUnusedItems;
  final String? paymentIntentId; // 用于判断是否全额 Store Credit 支付
  final double storeCreditUsed;  // 本单使用的 Store Credit 金额
  final double orderTotalAmount; // 订单原始总金额（未扣 Store Credit）
  /// selectedItemIds: 用户选中的具体券 id 列表（多券选择模式）
  final Future<void> Function(String refundMethod, {int cancelCount, List<String>? selectedItemIds}) onConfirm;

  const _CancelSheet({
    required this.item,
    this.totalUnusedCount = 1,
    this.allUnusedItems = const [],
    this.paymentIntentId,
    this.storeCreditUsed = 0.0,
    this.orderTotalAmount = 0.0,
    required this.onConfirm,
  });

  @override
  ConsumerState<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends ConsumerState<_CancelSheet> {
  String _selectedMethod = 'store_credit';
  bool _isSubmitting = false;
  late int _cancelCount;
  // 券选择：记录被选中的 item id
  late Set<String> _selectedIds;

  // 是否全额 Store Credit 支付
  bool get _isPaidByStoreCredit {
    // 优先用 storeCreditUsed 判断（piId 可能被 mask 后丢失 store_credit 前缀）
    if (widget.storeCreditUsed > 0 && widget.orderTotalAmount > 0 &&
        widget.storeCreditUsed >= widget.orderTotalAmount) {
      return true;
    }
    final piId = widget.paymentIntentId ?? '';
    return piId.contains('store_credit');
  }

  // 是否混合支付（部分 Store Credit + 部分刷卡）
  bool get _isPartialStoreCredit =>
      !_isPaidByStoreCredit && widget.storeCreditUsed > 0;

  @override
  void initState() {
    super.initState();
    _cancelCount = 1;
    // 初始化：默认全选所有 unused 券
    _selectedIds = widget.allUnusedItems.map((i) => i.id).toSet();
    // 全额 Store Credit 支付时锁定退款方式
    if (_isPaidByStoreCredit) {
      _selectedMethod = 'store_credit';
    }
  }

  /// 根据支付方式构建退款选项列表（本 Sheet 仅用于未使用券取消）
  List<Widget> _buildRefundOptions() {
    if (_isPaidByStoreCredit) {
      // 全额 Store Credit 支付：只能退回 Store Credit
      return [
        _RefundMethodOption(
          selected: true,
          title: 'Store Credit',
          subtitle: 'Full amount incl. service fee · Instant',
          badge: 'Only Option',
          badgeColor: AppColors.success,
          onTap: () {},
        ),
      ];
    }

    // 混合支付时的 Original Payment 说明文案
    String originalPaymentSubtitle;
    if (_isPartialStoreCredit) {
      final creditUsedFmt = widget.storeCreditUsed.toStringAsFixed(2);
      originalPaymentSubtitle =
          'Store Credit portion (\$$creditUsedFmt) refunds to Store Credit first, '
          'remainder to card\n'
          'Service fee non-refundable · 5-10 business days';
    } else {
      originalPaymentSubtitle = 'Excluding service fee · 5-10 business days';
    }

    return [
      _RefundMethodOption(
        selected: _selectedMethod == 'store_credit',
        title: 'Store Credit',
        subtitle: 'Full amount incl. service fee · Instant',
        badge: 'Recommended',
        badgeColor: AppColors.success,
        onTap: () => setState(() => _selectedMethod = 'store_credit'),
      ),
      const SizedBox(height: 12),
      _RefundMethodOption(
        selected: _selectedMethod == 'original_payment',
        title: 'Original Payment',
        subtitle: originalPaymentSubtitle,
        onTap: () => setState(() => _selectedMethod = 'original_payment'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final totalUnused = widget.totalUnusedCount;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 拖拽指示条
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 标题
          const Text(
            'Cancel Voucher',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose how you would like to receive your refund.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          // 多张券时显示券选择列表（复选框）
          if (totalUnused > 1) ...[
            const SizedBox(height: 16),
            // 全选/取消全选
            GestureDetector(
              onTap: () {
                setState(() {
                  if (_selectedIds.length == widget.allUnusedItems.length) {
                    // 至少保留一张
                    _selectedIds = {widget.allUnusedItems.first.id};
                  } else {
                    _selectedIds = widget.allUnusedItems.map((i) => i.id).toSet();
                  }
                  _cancelCount = _selectedIds.length;
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(
                      'Select vouchers to cancel',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Text(
                      _selectedIds.length == widget.allUnusedItems.length
                          ? 'Deselect All'
                          : 'Select All',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 券列表
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: widget.allUnusedItems.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 48),
                itemBuilder: (_, index) {
                  final coupon = widget.allUnusedItems[index];
                  final isSelected = _selectedIds.contains(coupon.id);
                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (isSelected && _selectedIds.length > 1) {
                          _selectedIds.remove(coupon.id);
                        } else if (!isSelected) {
                          _selectedIds.add(coupon.id);
                        }
                        _cancelCount = _selectedIds.length;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: isSelected ? AppColors.primary : AppColors.textHint,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          // Deal 图片
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: coupon.dealImageUrl != null && coupon.dealImageUrl!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: coupon.dealImageUrl!,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      width: 40,
                                      height: 40,
                                      color: Colors.grey.shade200,
                                      child: Icon(Icons.local_offer_outlined,
                                          size: 18, color: Colors.grey.shade400),
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      width: 40,
                                      height: 40,
                                      color: Colors.grey.shade200,
                                      child: Icon(Icons.local_offer_outlined,
                                          size: 18, color: Colors.grey.shade400),
                                    ),
                                  )
                                : Container(
                                    width: 40,
                                    height: 40,
                                    color: Colors.grey.shade200,
                                    child: Icon(Icons.local_offer_outlined,
                                        size: 18, color: Colors.grey.shade400),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  coupon.dealTitle.isNotEmpty
                                      ? coupon.dealTitle
                                      : 'Voucher ${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  coupon.formattedCouponCode ?? '',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '\$${coupon.unitPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // 已选数量提示
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_selectedIds.length} of $totalUnused selected',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
          const SizedBox(height: 20),

          // 判断是否全额 Store Credit 支付（payment_intent_id 含 store_credit）
          ..._buildRefundOptions(),
          const SizedBox(height: 24),

          // 确认按钮（全额 Store Credit 时自动锁定为 store_credit）
          ElevatedButton(
            onPressed: _isSubmitting
                ? null
                : () async {
                    setState(() => _isSubmitting = true);
                    await widget.onConfirm(
                      _selectedMethod,
                      cancelCount: _cancelCount,
                      selectedItemIds: _selectedIds.toList(),
                    );
                    if (mounted) {
                      setState(() => _isSubmitting = false);
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Confirm',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── 退款方式选项卡 ────────────────────────────────

class _RefundMethodOption extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _RefundMethodOption({
    required this.selected,
    required this.title,
    required this.subtitle,
    this.badge,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.textHint.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // 单选圆圈
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.textHint,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            // 文案
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (badgeColor ?? AppColors.success)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: badgeColor ?? AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
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
}

// ── Deal 价格汇总辅助类 ────────────────────────────────────
class _DealPriceSummary {
  final String title;
  final double unitPrice;
  int count = 0;

  _DealPriceSummary({required this.title, required this.unitPrice});
}

// ── 简单行（label + value）────────────────────────────────────
class _SimpleRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const _SimpleRow(this.label, this.value, {this.isBold = false, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
              style: TextStyle(
                fontSize: isBold ? 14 : 13,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.normal,
                color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ),
          Text(value,
            style: TextStyle(
              fontSize: isBold ? 15 : 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
