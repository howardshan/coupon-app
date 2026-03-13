// 品牌管理员管理页面
// 从 brand_manage_page.dart 提取，独立路由 /brand-manage/admins

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/store_provider.dart';

class BrandAdminsPage extends ConsumerWidget {
  const BrandAdminsPage({super.key});

  static const _primaryOrange = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(brandDetailsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Brand Admins',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: detailsAsync.when(
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
                      final displayName = fullName.isNotEmpty
                          ? fullName
                          : (email.isNotEmpty ? email : 'Unknown');
                      final isOwner = role == 'owner';

                      return Container(
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
                                isOwner
                                    ? Icons.star
                                    : Icons.admin_panel_settings,
                                color: isOwner
                                    ? _primaryOrange
                                    : const Color(0xFF757575),
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
                                  if (email.isNotEmpty &&
                                      fullName.isNotEmpty) ...[
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
                                      color: isOwner
                                          ? _primaryOrange
                                          : const Color(0xFF757575),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 移除按钮（Owner 不能被移除）
                            if (!isOwner)
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                onPressed: () => _confirmRemoveAdmin(
                                    context, ref, adminId, email),
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
      ),
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

  // 确认移除管理员
  void _confirmRemoveAdmin(
    BuildContext context,
    WidgetRef ref,
    String adminId,
    String email,
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
