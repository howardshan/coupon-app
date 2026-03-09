import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/deal_model.dart';
import '../../data/models/review_model.dart';
import '../../domain/providers/deals_provider.dart';
import '../../domain/providers/history_provider.dart';

class DealDetailScreen extends ConsumerWidget {
  final String dealId;

  const DealDetailScreen({super.key, required this.dealId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealAsync = ref.watch(dealDetailProvider(dealId));

    // deal 数据可用时记录浏览历史（postFrame 避免在 build 内产生副作用）
    dealAsync.whenData((deal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(historyRepositoryProvider).addToHistory(deal.id);
      });
    });

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

// ── Main body ────────────────────────────────────────────────
class _DealDetailBody extends ConsumerWidget {
  final DealModel deal;

  const _DealDetailBody({required this.deal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Image gallery
              SliverToBoxAdapter(child: _ImageGallery(imageUrls: deal.imageUrls)),

              // Price section
              SliverToBoxAdapter(child: _PriceSection(deal: deal)),

              // Info section (title, sold, availability, refund)
              SliverToBoxAdapter(child: _InfoSection(deal: deal)),

              // Gray divider
              const SliverToBoxAdapter(child: _SectionDivider()),

              // Deal details (dishes + note)
              SliverToBoxAdapter(child: _DishesSection(deal: deal)),

              // Gray divider
              const SliverToBoxAdapter(child: _SectionDivider()),

              // Purchase notes
              SliverToBoxAdapter(child: _PurchaseNotes(deal: deal)),

              // Gray divider
              const SliverToBoxAdapter(child: _SectionDivider()),

              // Restaurant info
              SliverToBoxAdapter(child: _RestaurantInfo(deal: deal)),

              // Gray divider
              const SliverToBoxAdapter(child: _SectionDivider()),

              // Applicable stores
              SliverToBoxAdapter(child: _ApplicableStores(deal: deal)),

              // Gray divider
              const SliverToBoxAdapter(child: _SectionDivider()),

              // More from this store
              SliverToBoxAdapter(
                child: _MerchantDeals(
                  merchantId: deal.merchantId,
                  currentDealId: deal.id,
                ),
              ),

              // Gray divider
              const SliverToBoxAdapter(child: _SectionDivider()),

              // Reviews
              SliverToBoxAdapter(
                child: _ReviewsSection(
                  dealId: deal.id,
                  dealRating: deal.rating,
                  dealReviewCount: deal.reviewCount,
                ),
              ),

              // Bottom padding for the fixed bottom bar
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),

          // Floating back / heart / share buttons
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _CircleButton(
                  icon: Icons.arrow_back,
                  onTap: () => context.pop(),
                ),
                Row(
                  children: [
                    _SaveButton(dealId: deal.id),
                    const SizedBox(width: 8),
                    _CircleButton(
                      icon: Icons.share_outlined,
                      onTap: () => Share.share(
                        '${deal.title} - \$${deal.discountPrice.toStringAsFixed(2)} '
                        '(${deal.effectiveDiscountLabel}) on DealJoy!',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(deal: deal),
    );
  }
}

// ── Floating circle button ───────────────────────────────────
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: AppColors.textPrimary),
      ),
    );
  }
}

// ── 收藏心形按钮（已收藏红心 / 未收藏空心）────────────────────
class _SaveButton extends ConsumerWidget {
  final String dealId;

  const _SaveButton({required this.dealId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedIds = ref.watch(savedDealIdsProvider).valueOrNull ?? {};
    final isSaved = savedIds.contains(dealId);

    return GestureDetector(
      onTap: () =>
          ref.read(savedDealsNotifierProvider.notifier).toggle(dealId),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(
          isSaved ? Icons.favorite : Icons.favorite_border,
          size: 20,
          color: isSaved ? Colors.red : AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ── Section divider (8px gray) ───────────────────────────────
class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 8, color: AppColors.background);
  }
}

// ── Image gallery with page indicator ────────────────────────
class _ImageGallery extends StatefulWidget {
  final List<String> imageUrls;

  const _ImageGallery({required this.imageUrls});

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;
    if (urls.isEmpty) {
      return Container(
        height: 280,
        color: AppColors.surfaceVariant,
        child: const Center(
          child: Icon(Icons.restaurant, size: 64, color: AppColors.textHint),
        ),
      );
    }

    return SizedBox(
      height: 280,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (_, i) => CachedNetworkImage(
              imageUrl: urls[i],
              width: double.infinity,
              height: 280,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => Container(
                color: AppColors.surfaceVariant,
                child: const Center(
                  child:
                      Icon(Icons.restaurant, size: 48, color: AppColors.textHint),
                ),
              ),
            ),
          ),
          if (urls.length > 1)
            Positioned(
              bottom: 12,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentPage + 1}/${urls.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Price section ────────────────────────────────────────────
class _PriceSection extends StatelessWidget {
  final DealModel deal;

  const _PriceSection({required this.deal});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          // Dollar sign
          const Text(
            '\$',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Discount price
          Text(
            deal.discountPrice.toStringAsFixed(2),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 36,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
          const SizedBox(width: 10),
          // Discount label tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              deal.effectiveDiscountLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // = original - savings
          Text(
            '= ',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          Text(
            '\$${deal.originalPrice.toStringAsFixed(0)}',
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 13,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          Text(
            ' - ',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          Text(
            '\$${deal.savingsAmount.toStringAsFixed(0)}',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info section (title, sold, availability, refund) ─────────
class _InfoSection extends StatelessWidget {
  final DealModel deal;

  const _InfoSection({required this.deal});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            deal.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),

          // Sold count
          Row(
            children: [
              const Icon(Icons.local_fire_department,
                  size: 15, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(
                '${deal.totalSold} sold',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Availability row
          Row(
            children: [
              const Icon(Icons.access_time_outlined,
                  size: 16, color: AppColors.success),
              const SizedBox(width: 6),
              Text(
                'Available Today',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (deal.merchantHours != null) ...[
                Text(
                  '  ·  ${deal.merchantHours}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Refund badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline,
                    color: AppColors.success, size: 15),
                const SizedBox(width: 6),
                const Text(
                  'Risk-Free Refund',
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    size: 14, color: AppColors.success),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dishes section + Note ────────────────────────────────────
class _DishesSection extends StatelessWidget {
  final DealModel deal;

  const _DishesSection({required this.deal});

  @override
  Widget build(BuildContext context) {
    if (deal.dishes.isEmpty) return const SizedBox.shrink();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Deal Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Dishes list
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceVariant),
            ),
            child: Column(
              children: deal.dishes.asMap().entries.map((entry) {
                final isLast = entry.key == deal.dishes.length - 1;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : const Border(
                            bottom:
                                BorderSide(color: AppColors.surfaceVariant)),
                  ),
                  child: Builder(builder: (_) {
                    // 解析 "name::qty::subtotal" 格式
                    final parts = entry.value.split('::');
                    final name = parts[0];
                    final qty = parts.length > 1 ? parts[1] : '1';
                    final subtotal = parts.length > 2 ? parts[2] : '';
                    // 构造右侧文字：×2 $30 或 ×1
                    final suffix = subtotal.isNotEmpty ? '×$qty \$$subtotal' : '×$qty';
                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          suffix,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    );
                  }),
                );
              }).toList(),
            ),
          ),

          // Note
          if (deal.description.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Note: ${deal.description}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Purchase notes ───────────────────────────────────────────
class _PurchaseNotes extends StatelessWidget {
  final DealModel deal;

  const _PurchaseNotes({required this.deal});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Purchase Notes',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          _NoteRow(
            icon: Icons.event_available,
            label: 'Validity',
            value: 'Valid until ${dateFormat.format(deal.expiresAt)}',
          ),
          if (deal.merchantHours != null) ...[
            const SizedBox(height: 12),
            _NoteRow(
              icon: Icons.schedule_outlined,
              label: 'Hours',
              value: deal.merchantHours!,
            ),
          ],
          const SizedBox(height: 12),
          _NoteRow(
            icon: Icons.shield_outlined,
            label: 'Refund',
            value: deal.refundPolicy,
          ),
          const SizedBox(height: 12),
          const _NoteRow(
            icon: Icons.rule,
            label: 'Rules',
            value: '1 deal per table per visit',
          ),
          const SizedBox(height: 12),
          const _NoteRow(
            icon: Icons.block,
            label: 'Note',
            value: 'Cannot be combined with other offers',
          ),
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _NoteRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

// ── Restaurant info ──────────────────────────────────────────
class _RestaurantInfo extends StatelessWidget {
  final DealModel deal;

  const _RestaurantInfo({required this.deal});

  @override
  Widget build(BuildContext context) {
    final merchant = deal.merchant;
    if (merchant == null) return const SizedBox.shrink();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Restaurant Info',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Logo
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: merchant.logoUrl != null && merchant.logoUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: merchant.logoUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 48,
                        height: 48,
                        color: AppColors.surfaceVariant,
                        child: Center(
                          child: Text(
                            merchant.name.isNotEmpty
                                ? merchant.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchant.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 3),
                        Text(
                          deal.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(${deal.reviewCount} reviews)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Phone button
              if (merchant.phone != null && merchant.phone!.isNotEmpty)
                _ActionCircle(
                  icon: Icons.phone_outlined,
                  onTap: () => launchUrl(
                    Uri.parse('tel:${merchant.phone}'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              const SizedBox(width: 8),
              // Directions button
              _ActionCircle(
                icon: Icons.directions_outlined,
                onTap: () {
                  final addr = deal.address ?? merchant.address;
                  if (addr != null && addr.isNotEmpty) {
                    launchUrl(
                      Uri.parse(
                          'https://maps.google.com/?q=${Uri.encodeComponent(addr)}'),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
              ),
            ],
          ),
          // Address
          if (deal.address != null || merchant.address != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    deal.address ?? merchant.address ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionCircle extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ActionCircle({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: AppColors.textSecondary),
      ),
    );
  }
}

// ── Applicable stores ────────────────────────────────────────
class _ApplicableStores extends StatelessWidget {
  final DealModel deal;

  const _ApplicableStores({required this.deal});

  @override
  Widget build(BuildContext context) {
    final merchant = deal.merchant;
    if (merchant == null) return const SizedBox.shrink();

    // 计算适用门店数量
    final storeIds = deal.applicableMerchantIds;
    final storeCount = (storeIds != null && storeIds.isNotEmpty)
        ? storeIds.length
        : 1;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Applicable Stores',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                '$storeCount ${storeCount == 1 ? 'Store' : 'Stores'}',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 创建门店卡片（主门店始终显示）
          _buildStoreCard(context, merchant),

          // 多店时加载并显示其他门店
          if (storeIds != null && storeIds.length > 1)
            _MultiStoreList(
              storeIds: storeIds.where((id) => id != merchant.id).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildStoreCard(BuildContext context, MerchantSummary merchant) {
    return GestureDetector(
      onTap: () => context.push('/merchant/${merchant.id}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Row(
          children: [
            // Logo
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child:
                  merchant.logoUrl != null && merchant.logoUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: merchant.logoUrl!,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 52,
                          height: 52,
                          color: AppColors.surfaceVariant,
                          child: const Icon(Icons.restaurant,
                              color: AppColors.textHint),
                        ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    merchant.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  if (merchant.address != null &&
                      merchant.address!.isNotEmpty)
                    Text(
                      merchant.address!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Phone
            if (merchant.phone != null && merchant.phone!.isNotEmpty)
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse('tel:${merchant.phone}'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.phone,
                      size: 18, color: AppColors.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// 多店列表：异步加载其他适用门店的基本信息
class _MultiStoreList extends StatelessWidget {
  final List<String> storeIds;

  const _MultiStoreList({required this.storeIds});

  @override
  Widget build(BuildContext context) {
    if (storeIds.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('merchants')
          .select('id, name, address, logo_url, phone')
          .inFilter('id', storeIds),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final stores = snapshot.data!;
        return Column(
          children: stores.map((store) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                onTap: () => context.push('/merchant/${store['id']}'),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.surfaceVariant),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: store['logo_url'] != null &&
                                (store['logo_url'] as String).isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: store['logo_url'] as String,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 44,
                                height: 44,
                                color: AppColors.surfaceVariant,
                                child: const Icon(Icons.storefront,
                                    size: 20, color: AppColors.textHint),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              store['name'] as String? ?? '',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (store['address'] != null &&
                                (store['address'] as String).isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                store['address'] as String,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 20, color: AppColors.textHint),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ── More from this store ─────────────────────────────────────
class _MerchantDeals extends ConsumerWidget {
  final String merchantId;
  final String currentDealId;

  const _MerchantDeals({
    required this.merchantId,
    required this.currentDealId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealsAsync = ref.watch(merchantDealsProvider(
      (merchantId: merchantId, excludeDealId: currentDealId),
    ));

    return dealsAsync.when(
      data: (deals) {
        if (deals.isEmpty) return const SizedBox.shrink();
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'More from this Store',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/merchant/$merchantId'),
                    child: Row(
                      children: [
                        Text(
                          'See All',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            size: 16, color: AppColors.primary),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Horizontal list
              SizedBox(
                height: 200,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: deals.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) =>
                      _MerchantDealCard(deal: deals[i]),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _MerchantDealCard extends StatelessWidget {
  final DealModel deal;

  const _MerchantDealCard({required this.deal});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/deals/${deal.id}'),
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: deal.imageUrls.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: deal.imageUrls.first,
                      width: 150,
                      height: 100,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 150,
                      height: 100,
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.restaurant,
                          color: AppColors.textHint),
                    ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deal.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '\$${deal.discountPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '\$${deal.originalPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
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

// ── Reviews section ──────────────────────────────────────────
class _ReviewsSection extends ConsumerWidget {
  final String dealId;
  final double dealRating;
  final int dealReviewCount;

  const _ReviewsSection({
    required this.dealId,
    required this.dealRating,
    required this.dealReviewCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(dealReviewsProvider(dealId));

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Reviews',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  const Icon(Icons.star, size: 16, color: Colors.amber),
                  const SizedBox(width: 3),
                  Text(
                    dealRating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    ' ($dealReviewCount)',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Rating stars summary
          Row(
            children: List.generate(
              5,
              (i) => Icon(
                i < dealRating.round() ? Icons.star : Icons.star_border,
                size: 18,
                color: Colors.amber,
              ),
            ),
          ),
          Text(
            '$dealReviewCount reviews',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),

          // Reviews list
          reviewsAsync.when(
            data: (reviews) {
              if (reviews.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  alignment: Alignment.center,
                  child: const Text(
                    'Be the first to review!',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                );
              }
              final shown = reviews.length > 5 ? reviews.sublist(0, 5) : reviews;
              return Column(
                children: [
                  ...shown.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ReviewCard(review: r),
                      )),
                  if (reviews.length > 5)
                    GestureDetector(
                      onTap: () {
                        // TODO: navigate to full reviews page
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        child: Text(
                          'See All $dealReviewCount Reviews',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),

          // Write a review button
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => context.push('/review/$dealId'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary),
              ),
              child: const Center(
                child: Text(
                  'Write a Review',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Single review card ───────────────────────────────────────
class _ReviewCard extends StatelessWidget {
  final ReviewModel review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM dd, yyyy').format(review.createdAt);
    final userName = review.userName ?? 'User';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info row
          Row(
            children: [
              // Avatar
              ClipOval(
                child: review.userAvatarUrl != null &&
                        review.userAvatarUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: review.userAvatarUrl!,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 32,
                        height: 32,
                        color: AppColors.primary.withValues(alpha: 0.1),
                        child: Center(
                          child: Text(
                            userName[0].toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              // Name + date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              // Stars
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < review.rating ? Icons.star : Icons.star_border,
                    size: 14,
                    color: Colors.amber,
                  ),
                ),
              ),
            ],
          ),
          // Verified badge
          if (review.isVerified) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Verified Purchase',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          // Comment
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Bottom bar (Store + Save + Buy Now) ──────────────────────
class _BottomBar extends ConsumerWidget {
  final DealModel deal;

  const _BottomBar({required this.deal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (deal.isExpired) {
      return SafeArea(
        child: Center(
          child: Container(
            color: AppColors.surfaceVariant,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Deal Expired',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back, size: 20),
                  label: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isSaved =
        (ref.watch(savedDealIdsProvider).valueOrNull ?? {}).contains(deal.id);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: AppColors.surfaceVariant),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Store button
            GestureDetector(
              onTap: () => context.push('/merchant/${deal.merchantId}'),
              child: const SizedBox(
                width: 56,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.store_outlined,
                        size: 22, color: AppColors.textSecondary),
                    SizedBox(height: 2),
                    Text(
                      'Store',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Save button
            GestureDetector(
              onTap: () => ref
                  .read(savedDealsNotifierProvider.notifier)
                  .toggle(deal.id),
              child: SizedBox(
                width: 56,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSaved ? Icons.favorite : Icons.favorite_border,
                      size: 22,
                      color: isSaved ? AppColors.primary : AppColors.textSecondary,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 10,
                        color: isSaved
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Buy Now button
            Expanded(
              child: GestureDetector(
                onTap: () => context.push('/checkout/${deal.id}'),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: AppColors.primaryGradient,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Buy Now',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '\$${deal.discountPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
