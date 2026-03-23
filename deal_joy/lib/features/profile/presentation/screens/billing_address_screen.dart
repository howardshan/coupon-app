import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';

/// 美国 50 州 + DC 缩写列表
const _kUsStates = [
  'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA',
  'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD',
  'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH', 'NJ',
  'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI', 'SC',
  'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY', 'DC',
];

/// 账单地址编辑页面
class BillingAddressScreen extends ConsumerStatefulWidget {
  const BillingAddressScreen({super.key});

  @override
  ConsumerState<BillingAddressScreen> createState() =>
      _BillingAddressScreenState();
}

class _BillingAddressScreenState extends ConsumerState<BillingAddressScreen> {
  final _formKey = GlobalKey<FormState>();

  // 表单字段控制器
  final _line1Ctrl = TextEditingController();
  final _line2Ctrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _countryCtrl = TextEditingController(text: 'US');

  // 当前选中的州缩写
  String? _selectedState;

  /// 是否正在加载现有数据
  bool _isFetching = true;

  /// 是否正在保存
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // 页面初始化后立即从数据库读取现有账单地址
    _fetchExistingAddress();
  }

  @override
  void dispose() {
    _line1Ctrl.dispose();
    _line2Ctrl.dispose();
    _cityCtrl.dispose();
    _zipCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  /// 从 users 表读取现有账单地址并填入表单
  Future<void> _fetchExistingAddress() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final data = await client.from('users').select(
        'billing_address_line1, billing_address_line2, billing_city, '
        'billing_state, billing_postal_code, billing_country',
      ).eq('id', userId).single();

      if (!mounted) return;
      setState(() {
        _line1Ctrl.text = (data['billing_address_line1'] as String?) ?? '';
        _line2Ctrl.text = (data['billing_address_line2'] as String?) ?? '';
        _cityCtrl.text = (data['billing_city'] as String?) ?? '';
        _zipCtrl.text = (data['billing_postal_code'] as String?) ?? '';

        // 如果数据库已有州值且在列表中，则设置选中
        final savedState = data['billing_state'] as String?;
        if (savedState != null && _kUsStates.contains(savedState)) {
          _selectedState = savedState;
        }

        // country 默认 US，若数据库有值则使用数据库值
        final savedCountry = data['billing_country'] as String?;
        if (savedCountry != null && savedCountry.isNotEmpty) {
          _countryCtrl.text = savedCountry;
        }

        _isFetching = false;
      });
    } catch (_) {
      // 读取失败时也继续展示空表单
      if (mounted) setState(() => _isFetching = false);
    }
  }

  /// 保存账单地址到 users 表
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) {
        _showError('Unable to identify current user. Please log in again.');
        return;
      }

      await client.from('users').update({
        'billing_address_line1': _line1Ctrl.text.trim(),
        'billing_address_line2': _line2Ctrl.text.trim(),
        'billing_city': _cityCtrl.text.trim(),
        'billing_state': _selectedState,
        'billing_postal_code': _zipCtrl.text.trim(),
        'billing_country': 'US',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Billing address updated'),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to save billing address. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 显示错误 SnackBar
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Billing Address'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          // AppBar 右上角 Save 按钮，与 EditProfileScreen 保持一致
          TextButton(
            onPressed: (_isSaving || _isFetching) ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
          ),
        ],
      ),
      body: _isFetching
          // 读取现有数据时显示加载指示器
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Address Line 1（必填）
                    AppTextField(
                      controller: _line1Ctrl,
                      label: 'Address Line 1',
                      hint: 'Street address, P.O. box',
                      keyboardType: TextInputType.streetAddress,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Address line 1 is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Address Line 2（可选）
                    AppTextField(
                      controller: _line2Ctrl,
                      label: 'Address Line 2',
                      hint: 'Apt, suite, unit, building (optional)',
                      keyboardType: TextInputType.streetAddress,
                    ),
                    const SizedBox(height: 20),

                    // City（必填）
                    AppTextField(
                      controller: _cityCtrl,
                      label: 'City',
                      hint: 'Enter city',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'City is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // State 下拉选择（必填，列出美国 50 州 + DC）
                    _buildStateDropdown(),
                    const SizedBox(height: 20),

                    // ZIP Code（必填，5位数字验证）
                    AppTextField(
                      controller: _zipCtrl,
                      label: 'ZIP Code',
                      hint: 'e.g. 75201',
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'ZIP code is required';
                        }
                        if (!RegExp(r'^\d{5}$').hasMatch(value.trim())) {
                          return 'ZIP code must be 5 digits';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Country（只读，默认 US）
                    AppTextField(
                      controller: _countryCtrl,
                      label: 'Country',
                      readOnly: true,
                    ),
                    const SizedBox(height: 36),

                    // 底部 Save 按钮
                    AppButton(
                      label: 'Save Address',
                      isLoading: _isSaving,
                      onPressed: _isSaving ? null : _save,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// 构建 State 下拉选择框，样式与 AppTextField 保持一致
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
          initialValue: _selectedState,
          hint: const Text('Select state'),
          isExpanded: true,
          // 使用 Theme 的 InputDecoration 风格，与 AppTextField 内的 TextFormField 保持一致
          decoration: const InputDecoration(),
          items: _kUsStates.map((state) {
            return DropdownMenuItem<String>(
              value: state,
              child: Text(state),
            );
          }).toList(),
          onChanged: (value) => setState(() => _selectedState = value),
          validator: (value) {
            if (value == null) return 'Please select a state';
            return null;
          },
        ),
      ],
    );
  }
}
