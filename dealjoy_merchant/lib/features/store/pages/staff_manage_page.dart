// 员工管理页面
// 显示员工列表 + 待处理邀请，支持邀请/改角色/移除

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/staff_member.dart';
import '../providers/store_provider.dart';

// ============================================================
// StaffManagePage — 员工管理（替代原 V2 骨架 StaffAccountsPage）
// ============================================================
class StaffManagePage extends ConsumerWidget {
  const StaffManagePage({super.key});

  static const _primaryColor = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Staff Management'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('staff_invite_btn'),
        onPressed: () => _showInviteDialog(context, ref),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Invite'),
      ),
      body: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text('Failed to load staff', style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.read(staffProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (data) {
          final staff = data.staff;
          final invitations = data.invitations.where((i) => i.status == 'pending').toList();
          final hasContent = staff.isNotEmpty || invitations.isNotEmpty;

          if (!hasContent) {
            return _buildEmptyState();
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(staffProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 待处理邀请
                if (invitations.isNotEmpty) ...[
                  _buildSectionHeader('Pending Invitations'),
                  const SizedBox(height: 8),
                  ...invitations.map((inv) => _buildInvitationTile(inv)),
                  const SizedBox(height: 24),
                ],
                // 员工列表
                if (staff.isNotEmpty) ...[
                  _buildSectionHeader('Staff Members (${staff.length})'),
                  const SizedBox(height: 8),
                  ...staff.map((s) => _buildStaffTile(context, ref, s)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ----------------------------------------------------------
  // 空状态
  // ----------------------------------------------------------
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.group_outlined, size: 40, color: _primaryColor),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Staff Members Yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Invite employees to help manage your store. '
              'Assign roles to control their access level.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // 区块标题
  // ----------------------------------------------------------
  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1A1A1A),
      ),
    );
  }

  // ----------------------------------------------------------
  // 邀请卡片
  // ----------------------------------------------------------
  Widget _buildInvitationTile(StaffInvitation invitation) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withValues(alpha: 0.1),
          child: const Icon(Icons.mail_outline, color: Colors.orange, size: 20),
        ),
        title: Text(invitation.invitedEmail, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          '${invitation.role.displayLabel} · ${invitation.isExpired ? "Expired" : "Pending"}',
          style: TextStyle(
            fontSize: 12,
            color: invitation.isExpired ? Colors.red : Colors.orange,
          ),
        ),
        trailing: invitation.isExpired
            ? const Icon(Icons.schedule, color: Colors.red, size: 18)
            : const Icon(Icons.hourglass_empty, color: Colors.orange, size: 18),
      ),
    );
  }

  // ----------------------------------------------------------
  // 员工卡片
  // ----------------------------------------------------------
  Widget _buildStaffTile(BuildContext context, WidgetRef ref, StaffMember staff) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: staff.isActive
              ? _primaryColor.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
          child: Icon(
            Icons.person,
            color: staff.isActive ? _primaryColor : Colors.grey,
            size: 22,
          ),
        ),
        title: Text(
          staff.displayName,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: staff.isActive ? const Color(0xFF1A1A1A) : Colors.grey,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (staff.email != null)
              Text(staff.email!, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const SizedBox(height: 2),
            Row(
              children: [
                _buildRoleBadge(staff.role),
                if (!staff.isActive) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Disabled',
                      style: TextStyle(fontSize: 10, color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          onSelected: (action) => _handleStaffAction(context, ref, staff, action),
          itemBuilder: (ctx) => [
            const PopupMenuItem(value: 'role', child: Text('Change Role')),
            PopupMenuItem(
              value: staff.isActive ? 'disable' : 'enable',
              child: Text(staff.isActive ? 'Disable' : 'Enable'),
            ),
            const PopupMenuItem(
              value: 'remove',
              child: Text('Remove', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // 角色徽章
  // ----------------------------------------------------------
  Widget _buildRoleBadge(StaffRole role) {
    Color color;
    switch (role) {
      case StaffRole.regional_manager:
        color = Colors.indigo;
      case StaffRole.manager:
        color = Colors.blue;
      case StaffRole.finance:
        color = Colors.teal;
      case StaffRole.service:
        color = Colors.green;
      case StaffRole.cashier:
        color = Colors.purple;
      case StaffRole.trainee:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        role.displayLabel,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  // ----------------------------------------------------------
  // 邀请对话框
  // ----------------------------------------------------------
  Future<void> _showInviteDialog(BuildContext context, WidgetRef ref) async {
    final emailController = TextEditingController();
    StaffRole selectedRole = StaffRole.cashier;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Invite Staff Member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('staff_invite_email_field'),
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  hintText: 'staff@example.com',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<StaffRole>(
                key: const ValueKey('staff_invite_role_dropdown'),
                value: selectedRole,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Role',
                  border: const OutlineInputBorder(),
                  helperText: selectedRole.description,
                  helperStyle: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                // 收起状态：只显示角色名，描述放 helperText
                selectedItemBuilder: (context) {
                  return StaffRole.values.map((role) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(role.displayLabel),
                    );
                  }).toList();
                },
                items: StaffRole.values.map((role) {
                  return DropdownMenuItem(
                    value: role,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(role.displayLabel),
                        Text(
                          role.description,
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => selectedRole = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('staff_invite_submit_btn'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send Invite'),
            ),
          ],
        ),
      ),
    );

    if (result == true && emailController.text.trim().isNotEmpty && context.mounted) {
      try {
        await ref.read(staffProvider.notifier).inviteStaff(
              email: emailController.text.trim(),
              role: selectedRole.value,
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invitation sent')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to invite: $e')),
          );
        }
      }
    }
  }

  // ----------------------------------------------------------
  // 员工操作处理
  // ----------------------------------------------------------
  void _handleStaffAction(
    BuildContext context,
    WidgetRef ref,
    StaffMember staff,
    String action,
  ) {
    switch (action) {
      case 'role':
        _showChangeRoleDialog(context, ref, staff);
      case 'disable':
        ref.read(staffProvider.notifier).updateStaff(
              staffId: staff.id,
              isActive: false,
            );
      case 'enable':
        ref.read(staffProvider.notifier).updateStaff(
              staffId: staff.id,
              isActive: true,
            );
      case 'remove':
        _showRemoveConfirmation(context, ref, staff);
    }
  }

  // ----------------------------------------------------------
  // 修改角色对话框
  // ----------------------------------------------------------
  Future<void> _showChangeRoleDialog(
    BuildContext context,
    WidgetRef ref,
    StaffMember staff,
  ) async {
    StaffRole? newRole = staff.role;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Change Role — ${staff.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: StaffRole.values.map((role) {
              return RadioListTile<StaffRole>(
                value: role,
                groupValue: newRole,
                title: Text(role.displayLabel),
                subtitle: Text(role.description, style: const TextStyle(fontSize: 12)),
                onChanged: (v) => setState(() => newRole = v),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true && newRole != null && newRole != staff.role) {
      await ref.read(staffProvider.notifier).updateStaff(
            staffId: staff.id,
            role: newRole!.value,
          );
    }
  }

  // ----------------------------------------------------------
  // 移除确认对话框
  // ----------------------------------------------------------
  Future<void> _showRemoveConfirmation(
    BuildContext context,
    WidgetRef ref,
    StaffMember staff,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Staff Member'),
        content: Text(
          'Are you sure you want to remove ${staff.displayName}? '
          'They will lose all access to this store.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(staffProvider.notifier).removeStaff(staff.id);
    }
  }
}
