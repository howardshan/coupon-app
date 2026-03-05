// 商家注册多步骤向导页
// 5个步骤: 账号注册 → 公司信息 → 类别选择 → 证件上传 → 地址与提交

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/merchant_application.dart';
import '../providers/merchant_auth_provider.dart';
import '../widgets/category_selector.dart';
import '../widgets/document_upload_tile.dart';

// ============================================================
// MerchantRegisterPage — 多步骤注册向导（ConsumerWidget）
// ============================================================
class MerchantRegisterPage extends ConsumerStatefulWidget {
  const MerchantRegisterPage({super.key, this.isResubmit = false});

  /// 重新提交模式（审核被拒后编辑重提，跳过第1步账号注册）
  final bool isResubmit;

  @override
  ConsumerState<MerchantRegisterPage> createState() =>
      _MerchantRegisterPageState();
}

class _MerchantRegisterPageState extends ConsumerState<MerchantRegisterPage> {
  // 当前步骤索引（0-based）
  late int _currentStep;
  static const int _totalSteps = 5;

  /// 是否为重提模式（跳过 Step 0 账号注册）
  bool get _isResubmit => widget.isResubmit;

  // 是否已经从 DB 预填过表单（防止重复填充）
  bool _prefilled = false;

  // Step 1: 账号注册表单
  final _step1FormKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _passwordVisible = false;

  // Step 2: 公司信息表单
  final _step2FormKey = GlobalKey<FormState>();
  final _companyNameCtrl = TextEditingController();
  final _contactNameCtrl = TextEditingController();
  final _contactEmailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // Step 4: EIN 输入
  final _step4FormKey = GlobalKey<FormState>();
  final _einCtrl = TextEditingController();

  // Step 5: 地址表单（拆分为多字段）
  final _step5FormKey = GlobalKey<FormState>();
  final _address1Ctrl = TextEditingController();
  final _address2Ctrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _zipcodeCtrl = TextEditingController();

  // 记录每个证件上传是否在加载中
  final Map<DocumentType, bool> _uploadingMap = {};

  static const _primaryOrange = Color(0xFFFF6B35);
  static const _bgColor = Color(0xFFF8F9FA);

  @override
  void initState() {
    super.initState();
    // 重提模式从 Step 1（Business Info）开始，普通注册从 Step 0
    _currentStep = _isResubmit ? 1 : 0;

    Future.microtask(() {
      if (_isResubmit) {
        // 重提模式：从 DB 加载已有申请数据
        ref.read(merchantAuthProvider.notifier).refreshStatus();
      } else {
        // 普通注册：重置状态
        ref.read(merchantAuthProvider.notifier).resetState();
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _companyNameCtrl.dispose();
    _contactNameCtrl.dispose();
    _contactEmailCtrl.dispose();
    _phoneCtrl.dispose();
    _einCtrl.dispose();
    _address1Ctrl.dispose();
    _address2Ctrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _zipcodeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(merchantAuthProvider);

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: (_currentStep > 0 && !(_isResubmit && _currentStep == 1))
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF212121)),
                onPressed: _goBack,
              )
            : _isResubmit && _currentStep == 1
                ? IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF212121)),
                    onPressed: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        context.go('/auth/review');
                      }
                    },
                  )
                : null,
        title: Text(
          _stepTitle(_currentStep),
          style: const TextStyle(
            color: Color(0xFF212121),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 顶部进度指示器
          _StepProgressBar(
            currentStep: _isResubmit ? _currentStep - 1 : _currentStep,
            totalSteps: _isResubmit ? _totalSteps - 1 : _totalSteps,
          ),
          // 表单内容区域
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: authState.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: CircularProgressIndicator(color: _primaryOrange),
                  ),
                ),
                error: (error, _) {
                  final errStr = error.toString();
                  if (errStr.contains('user_already_exists') ||
                      errStr.contains('User already registered')) {
                    return _UserExistsBanner();
                  }
                  return _ErrorBanner(message: errStr);
                },
                data: (application) {
                  // 重提模式下，数据加载完成后预填表单
                  if (_isResubmit && !_prefilled && application != null) {
                    _prefillFromApplication(application);
                  }
                  return _buildStep(_currentStep, application);
                },
              ),
            ),
          ),
          // 底部按钮区
          _buildBottomBar(authState),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // 步骤标题
  // ----------------------------------------------------------
  String _stepTitle(int step) {
    switch (step) {
      case 0:
        return 'Create Account';
      case 1:
        return 'Business Info';
      case 2:
        return 'Select Category';
      case 3:
        return 'Upload Documents';
      case 4:
        return 'Store Address';
      default:
        return 'Register';
    }
  }

  // ----------------------------------------------------------
  // 根据步骤渲染对应表单
  // ----------------------------------------------------------
  Widget _buildStep(int step, MerchantApplication? application) {
    switch (step) {
      case 0:
        return _buildStep1AccountForm();
      case 1:
        return _buildStep2BusinessInfo(application);
      case 2:
        return _buildStep3CategorySelect(application);
      case 3:
        return _buildStep4Documents(application);
      case 4:
        return _buildStep5Address(application);
      default:
        return const SizedBox.shrink();
    }
  }

  // ----------------------------------------------------------
  // Step 1: 账号注册表单（邮箱+密码）
  // ----------------------------------------------------------
  Widget _buildStep1AccountForm() {
    return Form(
      key: _step1FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Create your merchant account',
            subtitle:
                'Use your business email address to get started.',
          ),
          const SizedBox(height: 24),
          _AppTextField(
            controller: _emailCtrl,
            label: 'Business Email',
            hint: 'you@business.com',
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              final emailReg = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
              if (!emailReg.hasMatch(v.trim())) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _AppTextField(
            controller: _passwordCtrl,
            label: 'Password',
            hint: 'At least 8 characters',
            obscureText: !_passwordVisible,
            suffixIcon: IconButton(
              icon: Icon(
                _passwordVisible ? Icons.visibility_off : Icons.visibility,
                color: const Color(0xFF9E9E9E),
              ),
              onPressed: () =>
                  setState(() => _passwordVisible = !_passwordVisible),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (v.length < 8) {
                return 'Password must be at least 8 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _AppTextField(
            controller: _confirmPasswordCtrl,
            label: 'Confirm Password',
            hint: 'Re-enter your password',
            obscureText: !_passwordVisible,
            validator: (v) {
              if (v != _passwordCtrl.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          // 已有账号，跳转登录
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Already have an account? ',
                style: TextStyle(color: Color(0xFF757575)),
              ),
              GestureDetector(
                onTap: () {
                  context.go('/auth/login');
                },
                child: const Text(
                  'Sign In',
                  style: TextStyle(
                    color: _primaryOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // Step 2: 公司基本信息
  // ----------------------------------------------------------
  Widget _buildStep2BusinessInfo(MerchantApplication? app) {
    // 预填邮箱
    if (_contactEmailCtrl.text.isEmpty && app?.email != null) {
      _contactEmailCtrl.text = app!.email;
    }
    return Form(
      key: _step2FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Tell us about your business',
            subtitle: 'All fields are required.',
          ),
          const SizedBox(height: 24),
          _AppTextField(
            controller: _companyNameCtrl,
            label: 'Company Name',
            hint: 'Legal business name',
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Company name is required'
                : null,
          ),
          const SizedBox(height: 16),
          _AppTextField(
            controller: _contactNameCtrl,
            label: 'Contact Person Name',
            hint: 'Your full name',
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Contact name is required'
                : null,
          ),
          const SizedBox(height: 16),
          _AppTextField(
            controller: _phoneCtrl,
            label: 'Contact Phone',
            hint: '+1 (555) 000-0000',
            keyboardType: TextInputType.phone,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Phone number is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _AppTextField(
            controller: _contactEmailCtrl,
            label: 'Contact Email',
            hint: 'Business contact email',
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Contact email is required';
              }
              final emailReg = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
              if (!emailReg.hasMatch(v.trim())) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // Step 3: 类别选择
  // ----------------------------------------------------------
  Widget _buildStep3CategorySelect(MerchantApplication? app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'Select your business category',
          subtitle:
              'This determines the licenses and permits you need to provide.',
        ),
        const SizedBox(height: 24),
        CategorySelector(
          selectedCategory: app?.category,
          onCategorySelected: (cat) {
            ref.read(merchantAuthProvider.notifier).updateCategory(cat);
          },
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // Step 4: EIN + 证件上传（动态显示）
  // ----------------------------------------------------------
  Widget _buildStep4Documents(MerchantApplication? app) {
    final category = app?.category;
    final requiredDocs = category?.requiredDocuments ?? [];

    return Form(
      key: _step4FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Upload your documents',
            subtitle:
                'Please provide all required documents. Supported formats: JPG, PNG, PDF.',
          ),
          const SizedBox(height: 24),

          // EIN / Tax ID 文本输入
          const Text(
            'EIN / Tax ID',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF212121),
            ),
          ),
          const SizedBox(height: 8),
          _AppTextField(
            controller: _einCtrl,
            label: 'EIN / Tax ID',
            hint: 'XX-XXXXXXX',
            keyboardType: TextInputType.number,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'EIN/Tax ID is required';
              }
              final einReg = RegExp(r'^\d{2}-\d{7}$');
              if (!einReg.hasMatch(v.trim())) {
                return 'Format must be XX-XXXXXXX (e.g. 12-3456789)';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          // 动态证件上传列表
          if (category == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Please go back and select a category first.',
                style: TextStyle(color: Color(0xFF9E9E9E)),
              ),
            )
          else ...[
            const Text(
              'Required Documents',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF212121),
              ),
            ),
            const SizedBox(height: 12),
            ...requiredDocs.map((docType) {
              final uploadedDoc = app?.getDocument(docType);
              final isLoading = _uploadingMap[docType] ?? false;
              return DocumentUploadTile(
                documentType: docType,
                uploadedDocument: uploadedDoc,
                isLoading: isLoading,
                onFilePicked: (path) => _handleFileUpload(docType, path),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // Step 5: 门店地址 + 提交前摘要
  // ----------------------------------------------------------
  Widget _buildStep5Address(MerchantApplication? app) {
    return Form(
      key: _step5FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Where is your store located?',
            subtitle: 'Enter your full store address.',
          ),
          const SizedBox(height: 24),
          _AppTextField(
            controller: _address1Ctrl,
            label: 'Address Line 1',
            hint: '123 Main St',
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Address is required'
                : null,
          ),
          const SizedBox(height: 16),
          _AppTextField(
            controller: _address2Ctrl,
            label: 'Address Line 2 (Optional)',
            hint: 'Apt, Suite, Unit, etc.',
          ),
          const SizedBox(height: 16),
          _AppTextField(
            controller: _cityCtrl,
            label: 'City',
            hint: 'Dallas',
            validator: (v) => v == null || v.trim().isEmpty
                ? 'City is required'
                : null,
          ),
          const SizedBox(height: 16),
          // State + Zipcode 同一行
          Row(
            children: [
              Expanded(
                child: _AppTextField(
                  controller: _stateCtrl,
                  label: 'State',
                  hint: 'TX',
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Required'
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AppTextField(
                  controller: _zipcodeCtrl,
                  label: 'Zip Code',
                  hint: '75201',
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (!RegExp(r'^\d{5}(-\d{4})?$').hasMatch(v.trim())) {
                      return 'Invalid zip';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // 提交摘要
          const Text(
            'Review & Submit',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF212121),
            ),
          ),
          const SizedBox(height: 12),
          _SummaryCard(application: app),
          const SizedBox(height: 20),

          // Stripe Coming Soon 占位
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: const Row(
              children: [
                Icon(Icons.credit_card, color: Color(0xFF9E9E9E), size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stripe Payout Setup',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF757575),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Coming Soon — Set up after approval',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // 底部按钮区（Next / Submit）
  // ----------------------------------------------------------
  Widget _buildBottomBar(AsyncValue<MerchantApplication?> authState) {
    final isLoading = authState is AsyncLoading;
    final isLastStep = _currentStep == _totalSteps - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: isLoading ? null : _handleNext,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryOrange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            disabledBackgroundColor: _primaryOrange.withAlpha(128),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Text(
                  isLastStep ? 'Submit for Review' : 'Next',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // 前进处理（每个步骤的校验 + 状态更新）
  // ----------------------------------------------------------
  Future<void> _handleNext() async {
    final notifier = ref.read(merchantAuthProvider.notifier);

    switch (_currentStep) {
      case 0:
        // Step 1: 仅做本地校验，暂存邮箱密码（不调 signUp）
        if (!(_step1FormKey.currentState?.validate() ?? false)) return;
        notifier.updateAccountInfo(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
        _goNext();

      case 1:
        // Step 2: 公司信息
        if (!(_step2FormKey.currentState?.validate() ?? false)) return;
        notifier.updateBusinessInfo(
          companyName: _companyNameCtrl.text.trim(),
          contactName: _contactNameCtrl.text.trim(),
          contactEmail: _contactEmailCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
        );
        _goNext();

      case 2:
        // Step 3: 类别选择（必须选了才能继续）
        final app = ref.read(merchantAuthProvider).value;
        if (app?.category == null) {
          _showError('Please select a business category');
          return;
        }
        _goNext();

      case 3:
        // Step 4: EIN + 证件校验
        if (!(_step4FormKey.currentState?.validate() ?? false)) return;
        notifier.updateEin(_einCtrl.text.trim());

        // 检查所有必需证件是否已上传
        final app4 = ref.read(merchantAuthProvider).value;
        final category = app4?.category;
        if (category != null) {
          final requiredDocs = category.requiredDocuments;
          final missing = requiredDocs
              .where((d) => app4?.getDocument(d) == null)
              .toList();
          if (missing.isNotEmpty) {
            _showError(
              'Please upload: ${missing.map((d) => d.label).join(', ')}',
            );
            return;
          }
        }
        _goNext();

      case 4:
        // Step 5: 地址 + 提交申请
        if (!(_step5FormKey.currentState?.validate() ?? false)) return;
        notifier.updateAddress(
          address1: _address1Ctrl.text.trim(),
          address2: _address2Ctrl.text.trim(),
          city: _cityCtrl.text.trim(),
          state: _stateCtrl.text.trim(),
          zipcode: _zipcodeCtrl.text.trim(),
        );

        if (_isResubmit) {
          // 重提模式：直接重新提交（已有账号，无需 signUp）
          await notifier.resubmitApplication();
        } else {
          // 新注册模式：注册账号 + 提交申请
          await notifier.registerAndSubmit();
        }
        final state5 = ref.read(merchantAuthProvider);
        if (state5 is AsyncError) {
          _showError(state5.error.toString());
          return;
        }
        // 提交成功，跳转审核状态页
        if (mounted) context.go('/auth/review');
    }
  }

  // 前进一步
  void _goNext() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
    }
  }

  // 后退一步
  void _goBack() {
    final minStep = _isResubmit ? 1 : 0;
    if (_currentStep > minStep) {
      setState(() => _currentStep--);
    }
  }

  // 处理证件文件选择（仅暂存本地路径，延迟到提交时上传）
  void _handleFileUpload(DocumentType docType, String path) {
    ref.read(merchantAuthProvider.notifier).addDocumentLocal(
          documentType: docType,
          localFilePath: path,
        );
  }

  // ----------------------------------------------------------
  // 重提模式：从已有申请数据预填表单
  // ----------------------------------------------------------
  void _prefillFromApplication(MerchantApplication app) {
    _prefilled = true;
    _companyNameCtrl.text = app.companyName;
    _contactNameCtrl.text = app.contactName;
    _contactEmailCtrl.text = app.contactEmail;
    _phoneCtrl.text = app.phone;
    _einCtrl.text = app.ein;
    _address1Ctrl.text = app.address1;
    _address2Ctrl.text = app.address2;
    _cityCtrl.text = app.city;
    _stateCtrl.text = app.state;
    _zipcodeCtrl.text = app.zipcode;
  }

  // 显示错误 SnackBar
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFD32F2F),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ============================================================
// 步骤进度条（私有组件）
// ============================================================
class _StepProgressBar extends StatelessWidget {
  const _StepProgressBar({
    required this.currentStep,
    required this.totalSteps,
  });

  final int currentStep;
  final int totalSteps;

  static const _primaryOrange = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        children: [
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (currentStep + 1) / totalSteps,
              backgroundColor: const Color(0xFFE0E0E0),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(_primaryOrange),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          // 步骤文字
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step ${currentStep + 1} of $totalSteps',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9E9E9E),
                ),
              ),
              Text(
                '${((currentStep + 1) / totalSteps * 100).round()}% complete',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9E9E9E),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 区段标题（私有组件）
// ============================================================
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF212121),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF757575),
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// 通用文本输入框（私有组件）
// ============================================================
class _AppTextField extends StatelessWidget {
  const _AppTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: Color(0xFFFF6B35),
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD32F2F)),
        ),
      ),
    );
  }
}

// ============================================================
// 提交前摘要卡片（私有组件）
// ============================================================
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.application});

  final MerchantApplication? application;

  @override
  Widget build(BuildContext context) {
    final app = application;
    if (app == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryRow(label: 'Company', value: app.companyName),
          _SummaryRow(label: 'Contact', value: app.contactName),
          _SummaryRow(label: 'Phone', value: app.phone),
          _SummaryRow(label: 'Email', value: app.contactEmail),
          _SummaryRow(label: 'Category', value: app.category?.label ?? '-'),
          _SummaryRow(label: 'EIN', value: app.ein),
          _SummaryRow(
            label: 'Address',
            value: '${app.address1}${app.address2.isNotEmpty ? ', ${app.address2}' : ''}\n${app.city}, ${app.state} ${app.zipcode}',
          ),
          _SummaryRow(
            label: 'Documents',
            value: '${app.documents.length} uploaded',
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
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

// ============================================================
// 错误横幅（私有组件）
// ============================================================
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF9A9A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFD32F2F)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFD32F2F),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 邮箱已注册横幅（引导去登录）
// ============================================================
class _UserExistsBanner extends StatelessWidget {
  const _UserExistsBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF9A9A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, color: Color(0xFFD32F2F)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This email is already registered.',
                  style: TextStyle(
                    color: Color(0xFFD32F2F),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => context.go('/auth/login'),
            child: const Text(
              'Sign in to your existing account →',
              style: TextStyle(
                color: Color(0xFFFF6B35),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
