// V2.1 品牌总览 Dashboard 页面
// 品牌管理员可查看所有门店的汇总数据、排行和健康度

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/dashboard_stats.dart';
import '../providers/dashboard_provider.dart';

class BrandOverviewPage extends ConsumerWidget {
  const BrandOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(brandOverviewProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Brand Overview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(brandOverviewProvider.notifier).refresh();
              ref.invalidate(brandRankingsProvider);
              ref.invalidate(brandHealthProvider);
            },
          ),
        ],
      ),
      body: overviewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Failed to load: $err'),
              const SizedBox(height: 12),
              ElevatedButton(
                key: const ValueKey('brand_overview_retry_btn'),
                onPressed: () =>
                    ref.read(brandOverviewProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async {
            await ref.read(brandOverviewProvider.notifier).refresh();
            ref.invalidate(brandRankingsProvider);
            ref.invalidate(brandHealthProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 品牌信息头
              _BrandHeader(brand: data.brand, stats: data.stats),
              const SizedBox(height: 16),
              // 今日汇总数据卡片
              _BrandStatsGrid(stats: data.stats),
              const SizedBox(height: 24),
              // 7天趋势
              _BrandTrendSection(trend: data.weeklyTrend),
              const SizedBox(height: 24),
              // 门店排行
              const _StoreRankingsSection(),
              const SizedBox(height: 24),
              // 门店健康度
              const _StoreHealthSection(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 品牌信息头部
// ============================================================
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.brand, required this.stats});
  final BrandOverviewInfo brand;
  final BrandDailyStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 品牌 Logo
            CircleAvatar(
              radius: 28,
              backgroundImage:
                  brand.logoUrl != null ? NetworkImage(brand.logoUrl!) : null,
              child: brand.logoUrl == null
                  ? Text(brand.name.isNotEmpty ? brand.name[0] : 'B',
                      style: const TextStyle(fontSize: 24))
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    brand.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${stats.totalStores} stores · ${stats.onlineStores} online',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer
                          .withValues(alpha: 0.7),
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

// ============================================================
// 汇总数据卡片 2x3
// ============================================================
class _BrandStatsGrid extends StatelessWidget {
  const _BrandStatsGrid({required this.stats});
  final BrandDailyStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Today's Summary",
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.1,
          children: [
            _StatTile(
              icon: Icons.shopping_bag_outlined,
              label: 'Orders',
              value: '${stats.todayOrders}',
              color: Colors.blue,
            ),
            _StatTile(
              icon: Icons.qr_code_scanner,
              label: 'Redeemed',
              value: '${stats.todayRedemptions}',
              color: Colors.green,
            ),
            _StatTile(
              icon: Icons.attach_money,
              label: 'Revenue',
              value: '\$${stats.todayRevenue.toStringAsFixed(0)}',
              color: Colors.orange,
            ),
            _StatTile(
              icon: Icons.store,
              label: 'Total Stores',
              value: '${stats.totalStores}',
              color: Colors.purple,
            ),
            _StatTile(
              icon: Icons.wifi,
              label: 'Online',
              value: '${stats.onlineStores}',
              color: Colors.teal,
            ),
            _StatTile(
              icon: Icons.confirmation_number_outlined,
              label: 'Pending',
              value: '${stats.pendingCoupons}',
              color: Colors.red,
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(label,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 7天合并趋势
// ============================================================
class _BrandTrendSection extends StatelessWidget {
  const _BrandTrendSection({required this.trend});
  final List<WeeklyTrendEntry> trend;

  @override
  Widget build(BuildContext context) {
    if (trend.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('7-Day Trend',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1.5),
                2: FlexColumnWidth(1.5),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: theme.dividerColor)),
                  ),
                  children: const [
                    Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('Date',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('Orders',
                          style: TextStyle(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.right),
                    ),
                    Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('Revenue',
                          style: TextStyle(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.right),
                    ),
                  ],
                ),
                ...trend.map((e) {
                  final isToday = e.isToday;
                  final style = TextStyle(
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    color: isToday ? theme.colorScheme.primary : null,
                  );
                  return TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          '${e.date.month}/${e.date.day}${isToday ? " (Today)" : ""}',
                          style: style,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text('${e.orders}',
                            style: style, textAlign: TextAlign.right),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          '\$${e.revenue.toStringAsFixed(0)}',
                          style: style,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 门店排行（#96）
// ============================================================
class _StoreRankingsSection extends ConsumerWidget {
  const _StoreRankingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rankingsAsync = ref.watch(brandRankingsProvider);
    final sortBy = ref.watch(rankingSortByProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Store Rankings',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            // 排序切换
            PopupMenuButton<String>(
              initialValue: sortBy,
              onSelected: (v) =>
                  ref.read(rankingSortByProvider.notifier).state = v,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'revenue', child: Text('By Revenue')),
                PopupMenuItem(value: 'orders', child: Text('By Orders')),
                PopupMenuItem(value: 'rating', child: Text('By Rating')),
              ],
              child: Chip(
                label: Text(
                  sortBy == 'revenue'
                      ? 'By Revenue'
                      : sortBy == 'orders'
                          ? 'By Orders'
                          : 'By Rating',
                  style: const TextStyle(fontSize: 12),
                ),
                avatar: const Icon(Icons.sort, size: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        rankingsAsync.when(
          loading: () => const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator())),
          error: (err, _) => Text('Error: $err'),
          data: (rankings) {
            if (rankings.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No store data yet')),
                ),
              );
            }
            return Column(
              children: rankings.asMap().entries.map((entry) {
                final index = entry.key;
                final store = entry.value;
                return _RankingTile(rank: index + 1, store: store);
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _RankingTile extends StatelessWidget {
  const _RankingTile({required this.rank, required this.store});
  final int rank;
  final StoreRanking store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 前三名用奖牌颜色
    final rankColor = rank == 1
        ? Colors.amber
        : rank == 2
            ? Colors.grey.shade400
            : rank == 3
                ? Colors.brown.shade300
                : theme.colorScheme.outline;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 排名
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: rank <= 3
                    ? rankColor.withValues(alpha: 0.2)
                    : Colors.transparent,
              ),
              alignment: Alignment.center,
              child: Text(
                '#$rank',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: rankColor,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 门店信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(store.storeName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (!store.isOnline)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Offline',
                              style:
                                  TextStyle(fontSize: 10, color: Colors.red)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _MiniStat(Icons.shopping_bag_outlined,
                          '${store.totalOrders}'),
                      _MiniStat(
                          Icons.attach_money,
                          '\$${store.totalRevenue.toStringAsFixed(0)}'),
                      _MiniStat(Icons.star, store.avgRating.toStringAsFixed(1)),
                      if (store.refundRate > 10)
                        _MiniStat(Icons.warning_amber,
                            '${store.refundRate.toStringAsFixed(0)}%',
                            color: Colors.red),
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

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.icon, this.value, {this.color});
  final IconData icon;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? Colors.grey),
        const SizedBox(width: 2),
        Text(value,
            style: TextStyle(fontSize: 12, color: color ?? Colors.grey.shade700)),
      ],
    );
  }
}

// ============================================================
// 门店健康度（#98）
// ============================================================
class _StoreHealthSection extends ConsumerWidget {
  const _StoreHealthSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(brandHealthProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Store Health',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        healthAsync.when(
          loading: () => const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator())),
          error: (err, _) => Text('Error: $err'),
          data: (alerts) {
            if (alerts.isEmpty) {
              return Card(
                elevation: 0,
                color: Colors.green.withValues(alpha: 0.05),
                child: const Padding(
                  padding: EdgeInsets.all(24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Text('All stores are healthy!',
                          style: TextStyle(color: Colors.green)),
                    ],
                  ),
                ),
              );
            }
            return Column(
              children: alerts.map((a) => _HealthAlertTile(alert: a)).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _HealthAlertTile extends StatelessWidget {
  const _HealthAlertTile({required this.alert});
  final StoreHealthAlert alert;

  IconData get _icon {
    switch (alert.alertType) {
      case 'high_refund':
        return Icons.money_off;
      case 'low_rating':
        return Icons.star_border;
      case 'no_orders':
        return Icons.remove_shopping_cart;
      case 'offline':
        return Icons.wifi_off;
      default:
        return Icons.warning;
    }
  }

  Color get _color {
    switch (alert.alertType) {
      case 'high_refund':
        return Colors.red;
      case 'low_rating':
        return Colors.orange;
      case 'no_orders':
        return Colors.amber;
      case 'offline':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      color: _color.withValues(alpha: 0.05),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _color.withValues(alpha: 0.15),
          child: Icon(_icon, color: _color, size: 20),
        ),
        title: Text(alert.storeName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(alert.alertMessage),
        dense: true,
      ),
    );
  }
}
