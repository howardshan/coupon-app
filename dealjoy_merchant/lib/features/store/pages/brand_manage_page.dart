// 品牌管理页面
// 品牌管理员可以：编辑品牌信息、查看旗下门店列表、管理品牌管理员
// Phase 4: 功能点 #28-#33

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/store_provider.dart';
import '../models/brand_info.dart';

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
    _tabController = TabController(length: 3, vsync: this);
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
      key: const ValueKey('brand_manage_page'),
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          key: const ValueKey('brand_manage_back_btn'),
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
            Tab(key: ValueKey('brand_tab_info'), text: 'Brand Info'),
            Tab(key: ValueKey('brand_tab_stores'), text: 'Stores'),
            Tab(key: ValueKey('brand_tab_admins'), text: 'Admins'),
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
              _BrandInfoTab(brand: brand),
              _StoresTab(),
              _AdminsTab(brandId: brand.id),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// 品牌信息 Tab（可编辑）— 功能点 #30
// ============================================================
class _BrandInfoTab extends ConsumerStatefulWidget {
  const _BrandInfoTab({required this.brand});
  final BrandInfo brand;

  @override
  ConsumerState<_BrandInfoTab> createState() => _BrandInfoTabState();
}

class _BrandInfoTabState extends ConsumerState<_BrandInfoTab> {
  bool _isEditing = false;
  bool _isSaving = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;

  static const _primaryOrange = Color(0xFFFF6B35);

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.brand.name);
    _descCtrl = TextEditingController(text: widget.brand.description ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

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
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: widget.brand.logoUrl != null &&
                          widget.brand.logoUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            widget.brand.logoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.business,
                              color: _primaryOrange,
                              size: 32,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.business,
                          color: _primaryOrange,
                          size: 32,
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.brand.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF212121),
                        ),
                      ),
                      if (widget.brand.description != null &&
                          widget.brand.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.brand.description!,
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
                IconButton(
                  key: const ValueKey('brand_edit_btn'),
                  icon: Icon(
                    _isEditing ? Icons.close : Icons.edit,
                    color: const Color(0xFF757575),
                  ),
                  onPressed: () => setState(() {
                    _isEditing = !_isEditing;
                    if (!_isEditing) {
                      _nameCtrl.text = widget.brand.name;
                      _descCtrl.text = widget.brand.description ?? '';
                    }
                  }),
                ),
              ],
            ),
          ),

          // 编辑表单
          if (_isEditing) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Edit Brand Info',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF212121),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('brand_name_field'),
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Brand Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('brand_desc_field'),
                    controller: _descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      key: const ValueKey('brand_save_btn'),
                      onPressed: _isSaving ? null : _saveBrandInfo,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryOrange,
                        foregroundColor: Colors.white,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save Changes'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // 品牌详情（只读）
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Column(
              children: [
                _InfoRow(label: 'Brand ID', value: widget.brand.id),
                if (widget.brand.storeCount != null)
                  _InfoRow(
                    label: 'Locations',
                    value: '${widget.brand.storeCount} stores',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 保存品牌信息到后端
  Future<void> _saveBrandInfo() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brand name is required')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final service = ref.read(storeServiceProvider);
      await service.updateBrand(
        name: name,
        description: _descCtrl.text.trim(),
      );
      // 刷新门店信息（含品牌信息）
      ref.invalidate(storeProvider);
      if (mounted) {
        setState(() {
          _isEditing = false;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Brand info updated'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// ============================================================
// 旗下门店 Tab — 功能点 #31, #33
// ============================================================
class _StoresTab extends ConsumerWidget {
  const _StoresTab();

  static const _primaryOrange = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storesAsync = ref.watch(brandStoresProvider);

    return storesAsync.when(
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
                  key: const ValueKey('brand_manage_add_store_btn'),
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
                      key: ValueKey('brand_store_${store.id}'),
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
                            key: ValueKey('brand_manage_remove_store_${store.id}'),
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.red,
                              size: 20,
                            ),
                            onPressed: () =>
                                _confirmRemoveStore(context, ref, store.id, store.name),
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
              key: const ValueKey('brand_add_store_email_field'),
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
            key: const ValueKey('brand_add_store_submit_btn'),
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
                    SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
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
    BuildContext context, WidgetRef ref, String merchantId, String storeName,
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
                    SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
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

// ============================================================
// 品牌管理员 Tab — 功能点 #32
// ============================================================
class _AdminsTab extends ConsumerWidget {
  const _AdminsTab({required this.brandId});
  final String brandId;

  static const _primaryOrange = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(brandDetailsProvider);

    return detailsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: _primaryOrange),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (details) {
        final admins = (details['admins'] as List<dynamic>? ?? [])
            .map((e) => e as Map<String, dynamic>)
            .toList();

        return Column(
          children: [
            // 邀请管理员按钮
            Padding(
              padding: const EdgeInsets.all(16).copyWith(bottom: 0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('brand_invite_admin_btn'),
                  onPressed: () => _showInviteAdminDialog(context, ref),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Invite Admin'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryOrange,
                    side: const BorderSide(color: _primaryOrange),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            if (admins.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No admins yet. Invite someone to help manage your brand.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF757575)),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: admins.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final admin = admins[index];
                    final adminId = admin['id'] as String? ?? '';
                    final role = admin['role'] as String? ?? 'admin';
                    final email = admin['email'] as String? ?? '';
                    final fullName = admin['full_name'] as String? ?? '';
                    final displayName = fullName.isNotEmpty ? fullName : (email.isNotEmpty ? email : 'Unknown');
                    final isOwner = role == 'owner';

                    return Container(
                      key: ValueKey('brand_admin_$adminId'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: isOwner
                                ? const Color(0xFFFFF3E0)
                                : const Color(0xFFF5F5F5),
                            child: Icon(
                              isOwner ? Icons.star : Icons.admin_panel_settings,
                              color: isOwner ? _primaryOrange : const Color(0xFF757575),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF212121),
                                  ),
                                ),
                                if (email.isNotEmpty && fullName.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    email,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF9E9E9E),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Text(
                                  isOwner ? 'Brand Owner' : 'Admin',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isOwner ? _primaryOrange : const Color(0xFF757575),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 移除按钮（Owner 不能被移除）
                          if (!isOwner)
                            IconButton(
                              key: ValueKey('brand_remove_admin_$adminId'),
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.red,
                                size: 20,
                              ),
                              onPressed: () =>
                                  _confirmRemoveAdmin(context, ref, adminId, email),
                              tooltip: 'Remove admin',
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
    );
  }

  // 邀请管理员对话框
  void _showInviteAdminDialog(BuildContext context, WidgetRef ref) {
    final emailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite Brand Admin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the email of the person you want to invite as a brand admin.',
              style: TextStyle(fontSize: 13, color: Color(0xFF757575)),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('brand_admin_email_field'),
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email Address',
                hintText: 'admin@example.com',
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
            key: const ValueKey('brand_admin_invite_submit_btn'),
            onPressed: () async {
              final email = emailCtrl.text.trim();
              if (email.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final service = ref.read(storeServiceProvider);
                await service.inviteBrandAdmin(email);
                ref.invalidate(brandDetailsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Admin invitation sent'),
                      backgroundColor: Color(0xFF2E7D32),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
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

  // 确认移除管理员
  void _confirmRemoveAdmin(
    BuildContext context, WidgetRef ref, String adminId, String email,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Admin'),
        content: Text(
          'Remove "$email" as a brand admin?\n\n'
          'They will lose access to all stores under this brand.',
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
                await service.removeBrandAdmin(adminId);
                ref.invalidate(brandDetailsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('"$email" removed'),
                      backgroundColor: const Color(0xFF2E7D32),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
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
