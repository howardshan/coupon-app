import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../data/models/deal_model.dart';
import '../../domain/providers/deals_provider.dart';

class DealDetailScreen extends ConsumerWidget {
  final String dealId;

  const DealDetailScreen({super.key, required this.dealId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealAsync = ref.watch(dealDetailProvider(dealId));

    return dealAsync.when(
      data: (deal) => _DealDetailBody(deal: deal),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _DealDetailBody extends ConsumerStatefulWidget {
  final DealModel deal;

  const _DealDetailBody({required this.deal});

  @override
  ConsumerState<_DealDetailBody> createState() => _DealDetailBodyState();
}

class _DealDetailBodyState extends ConsumerState<_DealDetailBody> {
  late Duration _timeLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timeLeft = widget.deal.timeLeft;
    if (!widget.deal.isExpired) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          if (_timeLeft.inSeconds > 0) {
            _timeLeft -= const Duration(seconds: 1);
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final deal = widget.deal;
    final h = _timeLeft.inHours;
    final m = _timeLeft.inMinutes % 60;
    final s = _timeLeft.inSeconds % 60;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── App bar with image ──────────────────────────
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            leading: GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              ),
            ),
            actions: [
              GestureDetector(
                onTap: () => Share.share(
                  '${deal.title} - \$${deal.discountPrice.toStringAsFixed(2)} '
                  '(${deal.effectiveDiscountLabel}) on DealJoy!',
                ),
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.share_outlined,
                      color: AppColors.textPrimary),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: deal.imageUrls.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: deal.imageUrls.first,
                      fit: BoxFit.cover,
                    )
                  : Container(color: AppColors.surfaceVariant),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Merchant + title
                  if (deal.merchant != null)
                    Text(
                      'at ${deal.merchant!.name}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    deal.title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Price row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '\$${deal.originalPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: AppColors.textHint,
                              decoration: TextDecoration.lineThrough,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '\$${deal.discountPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Risk-Free badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline,
                            color: AppColors.success, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Risk-Free Refund',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Countdown timer ─────────────────────
                  if (!deal.isExpired) ...[
                    const Text(
                      'Ends in:',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _TimeBox(value: _pad(h), label: 'Hours'),
                        const SizedBox(width: 12),
                        _TimeBox(value: _pad(m), label: 'Minutes'),
                        const SizedBox(width: 12),
                        _TimeBox(value: _pad(s), label: 'Seconds'),
                      ],
                    ),
                    const SizedBox(height: 28),
                  ],

                  // ── Included dishes ─────────────────────
                  if (deal.dishes.isNotEmpty) ...[
                    const Text(
                      'Included Dishes',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.surfaceVariant),
                      ),
                      child: Column(
                        children: deal.dishes
                            .asMap()
                            .entries
                            .map((e) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    border: e.key < deal.dishes.length - 1
                                        ? const Border(
                                            bottom: BorderSide(
                                                color: AppColors
                                                    .surfaceVariant))
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppColors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        e.value,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],

                  // ── About the restaurant ────────────────
                  const Text(
                    'About the Restaurant',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (deal.address != null || deal.merchant?.address != null)
                    _InfoRow(
                      icon: Icons.location_on_outlined,
                      title: deal.address ??
                          deal.merchant?.address ?? '',
                      subtitle: 'Dallas, TX',
                    ),
                  if (deal.merchantHours != null ||
                      deal.merchant?.hours != null) ...[
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.schedule_outlined,
                      title: 'Opening Hours',
                      subtitle: deal.merchantHours ??
                          deal.merchant?.hours ?? '',
                    ),
                  ],
                  const SizedBox(height: 12),

                  // 地图占位 — 点击打开导航
                  GestureDetector(
                    onTap: () {
                      final addr = deal.address ?? deal.merchant?.address;
                      if (addr != null && addr.isNotEmpty) {
                        final query = Uri.encodeComponent(addr);
                        launchUrl(
                          Uri.parse('https://maps.google.com/?q=$query'),
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Stack(
                          children: [
                            // 使用 deal 坐标或灰色背景
                            if (deal.lat != null && deal.lng != null)
                              CachedNetworkImage(
                                imageUrl:
                                    'https://maps.googleapis.com/maps/api/staticmap'
                                    '?center=${deal.lat},${deal.lng}'
                                    '&zoom=15&size=800x240&scale=2'
                                    '&markers=color:red|${deal.lat},${deal.lng}',
                                height: 120,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) =>
                                    _mapFallback(),
                              )
                            else
                              _mapFallback(),
                            // 导航提示
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.directions,
                                        size: 14, color: AppColors.primary),
                                    SizedBox(width: 4),
                                    Text(
                                      'Get Directions',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Reviews ────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Guest Reviews',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.star,
                              size: 16, color: AppColors.featuredBadge),
                          const SizedBox(width: 4),
                          Text(
                            deal.rating.toStringAsFixed(1),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary),
                          ),
                          Text(
                            ' (${deal.reviewCount})',
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Rating bar summary
                  RatingBarIndicator(
                    rating: deal.rating,
                    itemBuilder: (_, _) => const Icon(Icons.star,
                        color: AppColors.featuredBadge),
                    itemSize: 20,
                  ),
                  const SizedBox(height: 16),

                  // Sample review card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.surfaceVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Sarah Jenkins',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Row(
                              children: List.generate(
                                5,
                                (_) => const Icon(Icons.star,
                                    size: 14,
                                    color: AppColors.featuredBadge),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '"The meal was absolutely divine. Every dish was a work of art. Incredible value for the price!"',
                          style: TextStyle(
                              color: AppColors.textSecondary, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 110),
                ],
              ),
            ),
          ),
        ],
      ),

      // ── 底部操作栏：收藏 + 购买 ──────────────────────
      bottomNavigationBar: deal.isExpired
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    // 收藏按钮
                    GestureDetector(
                      onTap: () => ref
                          .read(savedDealsNotifierProvider.notifier)
                          .toggle(deal.id),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.surfaceVariant),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          (ref.watch(savedDealIdsProvider).valueOrNull ?? {})
                                  .contains(deal.id)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color:
                              (ref.watch(savedDealIdsProvider).valueOrNull ?? {})
                                      .contains(deal.id)
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Buy Now 按钮
                    Expanded(
                      child: AppButton(
                        label:
                            'Buy Now — \$${deal.discountPrice.toStringAsFixed(2)}',
                        onPressed: () =>
                            context.push('/checkout/${deal.id}'),
                        icon: Icons.shopping_cart_outlined,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ── 地图占位回退 ──────────────────────────────────────────────
Widget _mapFallback() => Container(
      height: 120,
      width: double.infinity,
      color: AppColors.surfaceVariant,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, size: 32, color: AppColors.textHint),
          SizedBox(height: 4),
          Text('Tap to open in Maps',
              style: TextStyle(color: AppColors.textHint, fontSize: 12)),
        ],
      ),
    );

// ── Time box widget ───────────────────────────────────────────
class _TimeBox extends StatelessWidget {
  final String value;
  final String label;

  const _TimeBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Center(
              child: Text(
                value,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info row ─────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.textSecondary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(subtitle,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}
