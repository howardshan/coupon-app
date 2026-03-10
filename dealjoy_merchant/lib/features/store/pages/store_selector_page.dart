// 品牌管理员门店选择页
// 登录后显示旗下所有门店，选择后进入该门店的 Dashboard

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/store_summary.dart';
import '../providers/store_provider.dart';

class StoreSelectorPage extends ConsumerWidget {
  const StoreSelectorPage({super.key});

  static const _primaryOrange = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storesAsync = ref.watch(brandStoresProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Select Store',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          // 品牌管理入口
          IconButton(
            icon: const Icon(Icons.business, color: Color(0xFF757575)),
            onPressed: () => context.push('/brand-manage'),
            tooltip: 'Brand Management',
          ),
        ],
      ),
      body: storesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _primaryOrange),
        ),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                'Failed to load stores',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(brandStoresProvider),
                child: const Text('Retry',
                    style: TextStyle(color: _primaryOrange)),
              ),
            ],
          ),
        ),
        data: (stores) {
          if (stores.isEmpty) {
            return const Center(
              child: Text(
                'No stores found under your brand.',
                style: TextStyle(color: Color(0xFF757575)),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: stores.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final store = stores[index];
              return _StoreCard(
                store: store,
                onTap: () async {
                  // 切换到选中的门店
                  final storeNotifier = ref.read(storeProvider.notifier);
                  await storeNotifier.switchStore(store.id);
                  if (context.mounted) {
                    context.go('/dashboard');
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

// 门店卡片
class _StoreCard extends StatelessWidget {
  const _StoreCard({
    required this.store,
    required this.onTap,
  });

  final StoreSummary store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey('store_selector_item_${store.id}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E0E0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 门店图标
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.storefront,
                color: Color(0xFFFF6B35),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            // 门店信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    store.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF212121),
                    ),
                  ),
                  if (store.address != null && store.address!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      store.address!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF757575),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  // 状态标签
                  _StatusBadge(status: store.status ?? 'pending'),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFFBDBDBD),
            ),
          ],
        ),
      ),
    );
  }
}

// 状态标签
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case 'approved':
        bgColor = const Color(0xFFE8F5E9);
        textColor = const Color(0xFF2E7D32);
        label = 'Active';
      case 'pending':
        bgColor = const Color(0xFFFFF8E1);
        textColor = const Color(0xFFF57F17);
        label = 'Pending';
      case 'rejected':
        bgColor = const Color(0xFFFFEBEE);
        textColor = const Color(0xFFC62828);
        label = 'Rejected';
      default:
        bgColor = const Color(0xFFF5F5F5);
        textColor = const Color(0xFF757575);
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
