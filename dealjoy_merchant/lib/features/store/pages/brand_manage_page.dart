// 品牌管理页面
// 品牌管理员可以：编辑品牌信息、查看旗下门店列表、管理品牌管理员

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/store_provider.dart';

class BrandManagePage extends ConsumerStatefulWidget {
  const BrandManagePage({super.key});

  @override
  ConsumerState<BrandManagePage> createState() => _BrandManagePageState();
}

class _BrandManagePageState extends ConsumerState<BrandManagePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _primaryOrange = Color(0xFFFF6B35);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(storeProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF212121)),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: const Text(
          'Brand Management',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: _primaryOrange,
          unselectedLabelColor: const Color(0xFF757575),
          indicatorColor: _primaryOrange,
          tabs: const [
            Tab(text: 'Brand Info'),
            Tab(text: 'Stores'),
          ],
        ),
      ),
      body: storeAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _primaryOrange),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (storeInfo) {
          final brand = storeInfo.brand;
          if (brand == null) {
            return const Center(
              child: Text(
                'No brand associated with this store.',
                style: TextStyle(color: Color(0xFF757575)),
              ),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: 品牌信息
              _BrandInfoTab(brand: brand),
              // Tab 2: 旗下门店
              _StoresTab(ref: ref),
            ],
          );
        },
      ),
    );
  }
}

// 品牌信息 Tab
class _BrandInfoTab extends StatelessWidget {
  const _BrandInfoTab({required this.brand});

  final dynamic brand; // BrandInfo

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 品牌 Logo + 名称
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Row(
              children: [
                // Logo 占位
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: brand.logoUrl != null && (brand.logoUrl as String).isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            brand.logoUrl as String,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.business,
                              color: Color(0xFFFF6B35),
                              size: 32,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.business,
                          color: Color(0xFFFF6B35),
                          size: 32,
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        brand.name as String? ?? 'Unknown Brand',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF212121),
                        ),
                      ),
                      if (brand.description != null &&
                          (brand.description as String).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          brand.description as String,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF757575),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 品牌详情
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Column(
              children: [
                _InfoRow(label: 'Brand ID', value: brand.id as String? ?? ''),
                if (brand.storeCount != null)
                  _InfoRow(
                    label: 'Locations',
                    value: '${brand.storeCount} stores',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 旗下门店 Tab
class _StoresTab extends StatelessWidget {
  const _StoresTab({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final storesAsync = ref.watch(brandStoresProvider);

    return storesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (stores) {
        if (stores.isEmpty) {
          return const Center(
            child: Text(
              'No stores found.',
              style: TextStyle(color: Color(0xFF757575)),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: stores.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
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
                  const Icon(Icons.storefront, color: Color(0xFFFF6B35)),
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
                  // 状态
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
                      store.status == 'approved' ? 'Active' : (store.status ?? 'Pending'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: store.status == 'approved'
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFF57F17),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// 信息行
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF9E9E9E),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF212121),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
