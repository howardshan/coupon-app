import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../checkout/data/models/billing_address_model.dart';
import '../../../checkout/data/repositories/billing_address_repository.dart';
import '../../../checkout/domain/providers/billing_address_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 美国 50 州 + DC 缩写列表
const _kUsStates = [
  'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA',
  'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD',
  'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH', 'NJ',
  'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI', 'SC',
  'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY', 'DC',
];

/// 账单地址管理页面（读写 billing_addresses 表）
class BillingAddressScreen extends ConsumerStatefulWidget {
  const BillingAddressScreen({super.key});

  @override
  ConsumerState<BillingAddressScreen> createState() =>
      _BillingAddressScreenState();
}

class _BillingAddressScreenState extends ConsumerState<BillingAddressScreen> {
  /// 是否正在加载地址列表
  bool _isFetching = true;

  /// 已保存的地址列表
  List<BillingAddressModel> _addresses = [];

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  /// 从 billing_addresses 表加载地址（含自动迁移旧 users 表数据）
  Future<void> _loadAddresses() async {
    setState(() => _isFetching = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final repo = ref.read(billingAddressRepositoryProvider);
      // 自动迁移旧 users 表数据到 billing_addresses 表
      await repo.migrateFromUsersTable(userId);
      final list = await repo.fetchAll(userId);
      if (mounted) setState(() => _addresses = list);
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  /// 将某地址设为默认
  Future<void> _setDefault(String addressId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final repo = ref.read(billingAddressRepositoryProvider);
    await repo.setDefault(userId, addressId);
    ref.invalidate(savedBillingAddressesProvider);
    await _loadAddresses();
  }

  /// 删除地址
  Future<void> _delete(String addressId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Address'),
        content: const Text('Are you sure you want to delete this address?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = ref.read(billingAddressRepositoryProvider);
    await repo.delete(addressId);
    ref.invalidate(savedBillingAddressesProvider);
    await _loadAddresses();
  }

  /// 打开新增 / 编辑弹层
  Future<void> _openAddressForm({BillingAddressModel? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddressFormSheet(existing: existing),
    );
    if (saved == true) {
      ref.invalidate(savedBillingAddressesProvider);
      await _loadAddresses();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Billing Address'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isFetching
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                // 已保存地址列表
                ..._addresses.map((addr) => _AddressTile(
                      address: addr,
                      onSetDefault: () => _setDefault(addr.id),
                      onEdit: () => _openAddressForm(existing: addr),
                      onDelete: () => _delete(addr.id),
                    )),

                // 新增地址按钮
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _openAddressForm(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add New Address'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── 地址卡片 ──────────────────────────────────────────────────────

class _AddressTile extends StatelessWidget {
  final BillingAddressModel address;
  final VoidCallback onSetDefault;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AddressTile({
    required this.address,
    required this.onSetDefault,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: address.isDefault ? AppColors.primary : Colors.grey.shade200,
          width: address.isDefault ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 选中圆点
          GestureDetector(
            onTap: address.isDefault ? null : onSetDefault,
            child: Container(
              margin: const EdgeInsets.only(top: 2),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: address.isDefault ? AppColors.primary : Colors.grey,
                  width: 2,
                ),
              ),
              child: address.isDefault
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
          ),
          const SizedBox(width: 12),

          // 地址内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (address.label.isNotEmpty)
                      Text(
                        address.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    if (address.isDefault) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Default',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  address.summary,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          // 操作按钮
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (val) {
              if (val == 'edit') onEdit();
              if (val == 'delete') onDelete();
              if (val == 'default') onSetDefault();
            },
            itemBuilder: (_) => [
              if (!address.isDefault)
                const PopupMenuItem(
                  value: 'default',
                  child: Text('Set as Default'),
                ),
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete',
                    style: TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 新增 / 编辑地址底部表单 ─────────────────────────────────────────

class _AddressFormSheet extends ConsumerStatefulWidget {
  final BillingAddressModel? existing;

  const _AddressFormSheet({this.existing});

  @override
  ConsumerState<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends ConsumerState<_AddressFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _labelCtrl;
  late final TextEditingController _line1Ctrl;
  late final TextEditingController _line2Ctrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _zipCtrl;

  String? _selectedState;
  bool _isDefault = false;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _labelCtrl = TextEditingController(text: e?.label ?? '');
    _line1Ctrl = TextEditingController(text: e?.addressLine1 ?? '');
    _line2Ctrl = TextEditingController(text: e?.addressLine2 ?? '');
    _cityCtrl = TextEditingController(text: e?.city ?? '');
    _zipCtrl = TextEditingController(text: e?.postalCode ?? '');
    _selectedState =
        (e?.state.isNotEmpty == true && _kUsStates.contains(e?.state))
            ? e?.state
            : null;
    _isDefault = e?.isDefault ?? false;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _line1Ctrl.dispose();
    _line2Ctrl.dispose();
    _cityCtrl.dispose();
    _zipCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final repo = ref.read(billingAddressRepositoryProvider);

      if (_isEditing) {
        // 更新现有地址（直接操作数据库）
        final client = Supabase.instance.client;
        if (_isDefault) {
          // 先清除其他默认
          await client
              .from('billing_addresses')
              .update({'is_default': false})
              .eq('user_id', userId)
              .eq('is_default', true);
        }
        await client.from('billing_addresses').update({
          'label': _labelCtrl.text.trim(),
          'address_line1': _line1Ctrl.text.trim(),
          'address_line2': _line2Ctrl.text.trim(),
          'city': _cityCtrl.text.trim(),
          'state': _selectedState ?? '',
          'postal_code': _zipCtrl.text.trim(),
          'country': 'US',
          'is_default': _isDefault,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', widget.existing!.id);
      } else {
        // 新增地址
        await repo.create(
          userId: userId,
          label: _labelCtrl.text.trim().isEmpty ? 'Home' : _labelCtrl.text.trim(),
          addressLine1: _line1Ctrl.text.trim(),
          addressLine2: _line2Ctrl.text.trim(),
          city: _cityCtrl.text.trim(),
          state: _selectedState ?? '',
          postalCode: _zipCtrl.text.trim(),
          country: 'US',
          isDefault: _isDefault,
        );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to save address. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isEditing ? 'Edit Address' : 'Add New Address',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Label（Home / Work 等）
              AppTextField(
                controller: _labelCtrl,
                label: 'Label (e.g. Home, Work)',
                hint: 'Home',
              ),
              const SizedBox(height: 16),

              // Address Line 1（必填）
              AppTextField(
                controller: _line1Ctrl,
                label: 'Address Line 1',
                hint: 'Street address, P.O. box',
                keyboardType: TextInputType.streetAddress,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              // Address Line 2（可选）
              AppTextField(
                controller: _line2Ctrl,
                label: 'Address Line 2',
                hint: 'Apt, suite, unit, building (optional)',
                keyboardType: TextInputType.streetAddress,
              ),
              const SizedBox(height: 16),

              // City（必填）
              AppTextField(
                controller: _cityCtrl,
                label: 'City',
                hint: 'Enter city',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              // State 下拉
              _buildStateDropdown(),
              const SizedBox(height: 16),

              // ZIP Code（必填）
              AppTextField(
                controller: _zipCtrl,
                label: 'ZIP Code',
                hint: 'e.g. 75201',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!RegExp(r'^\d{5}$').hasMatch(v.trim())) {
                    return 'ZIP code must be 5 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // 设为默认
              CheckboxListTile(
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v ?? false),
                title: const Text('Set as default billing address'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 16),

              // 保存按钮
              AppButton(
                label: _isEditing ? 'Update Address' : 'Save Address',
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'State',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _selectedState,
          hint: const Text('Select state'),
          isExpanded: true,
          decoration: const InputDecoration(),
          items: _kUsStates
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: (v) => setState(() => _selectedState = v),
          validator: (v) => v == null ? 'Please select a state' : null,
        ),
      ],
    );
  }
}
