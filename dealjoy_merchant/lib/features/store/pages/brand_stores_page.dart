// 品牌旗下门店管理页面
// 从 brand_manage_page.dart 提取，独立路由 /brand-manage/stores

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/store_provider.dart';

class BrandStoresPage extends ConsumerWidget {
  const BrandStoresPage({super.key});

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
          'Stores',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: storesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _primaryOrange),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (stores) {
          return Column(
            children: [
              // 添加门店按钮
              Padding(
                padding: const EdgeInsets.all(16).copyWith(bottom: 0),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddStoreDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Store'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryOrange,
                      side: const BorderSide(color: _primaryOrange),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              if (stores.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      'No stores found.',
                      style: TextStyle(color: Color(0xFF757575)),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: stores.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final store = stores[index];
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE0E0E0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.storefront, color: _primaryOrange),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    store.name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF212121),
                                    ),
                                  ),
                                  if (store.address != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      store.address!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF757575),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // 状态标签
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: store.status == 'approved'
                                    ? const Color(0xFFE8F5E9)
                                    : const Color(0xFFFFF8E1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                store.status == 'approved'
                                    ? 'Active'
                                    : (store.status ?? 'Pending'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: store.status == 'approved'
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFFF57F17),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 移除按钮
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.red,
                                size: 20,
                              ),
                              onPressed: () => _confirmRemoveStore(
                                  context, ref, store.id, store.name),
                              tooltip: 'Remove from brand',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // 添加门店对话框
  void _showAddStoreDialog(BuildContext context, WidgetRef ref) {
    final emailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Store'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Invite an existing store to join your brand by entering the store owner\'s email.',
              style: TextStyle(fontSize: 13, color: Color(0xFF757575)),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('brand_store_add_email_field'),
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Store Owner Email',
                hintText: 'owner@example.com',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const ValueKey('brand_store_add_submit_btn'),
            onPressed: () async {
              final email = emailCtrl.text.trim();
              if (email.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final service = ref.read(storeServiceProvider);
                await service.addStoreToBrand(email: email);
                ref.invalidate(brandStoresProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Store invitation sent'),
                      backgroundColor: Color(0xFF2E7D32),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Failed: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Invitation'),
          ),
        ],
      ),
    );
  }

  // 确认移除门店
  void _confirmRemoveStore(
    BuildContext context,
    WidgetRef ref,
    String merchantId,
    String storeName,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Store'),
        content: Text(
          'Remove "$storeName" from your brand?\n\n'
          'The store will become independent. Multi-store deals will no longer apply.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final service = ref.read(storeServiceProvider);
                await service.removeStoreFromBrand(merchantId);
                ref.invalidate(brandStoresProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('"$storeName" removed from brand'),
                      backgroundColor: const Color(0xFF2E7D32),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Failed: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
