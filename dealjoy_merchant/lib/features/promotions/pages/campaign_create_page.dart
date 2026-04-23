// 创建 Campaign 页面
// 多步骤表单：Target → 具体对象 → 广告位 → 出价 → 日预算 → 时间段 → 日期范围
// 完成后调用 service 创建并返回主页刷新

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/promotions_models.dart';
import '../providers/promotions_provider.dart';
import '../../store/services/store_service.dart';

// =============================================================
// CampaignCreatePage — 创建 Campaign 页面（ConsumerStatefulWidget）
// 使用 ConsumerStatefulWidget 管理多步骤表单本地状态
// =============================================================
class CampaignCreatePage extends ConsumerStatefulWidget {
  /// 从 promotions 主页传入的预选类型（'splash' / 'store_booster' / 'deal_booster'）
  final String? campaignType;

  const CampaignCreatePage({super.key, this.campaignType});

  @override
  ConsumerState<CampaignCreatePage> createState() =>
      _CampaignCreatePageState();
}

class _CampaignCreatePageState extends ConsumerState<CampaignCreatePage> {
  // 当前步骤（0-6）
  int _currentStep = 0;

  // 表单数据
  String _targetType = 'deal'; // 'deal' | 'store'
  String? _targetId;
  String? _targetName;
  String? _placement;
  double _bidPrice = 0.5;
  double _dailyBudget = 10.0;
  String _scheduleHours = 'all_day'; // 'lunch' | 'dinner' | 'all_day'
  DateTime? _startDate;
  DateTime? _endDate;

  // splash 广告位专属字段
  File? _splashCreativeFile;       // 本地选取的素材图片文件
  String? _splashCreativeUrl;      // 上传后的 Storage URL
  String _splashLinkType = 'none'; // 'none' | 'deal' | 'merchant' | 'external'
  String? _splashLinkValue;        // 跳转目标值
  int _splashRadiusMeters = 16093; // 投放半径（米），默认 10mi
  bool _isUploadingCreative = false; // 是否正在上传图片

  bool _isSubmitting = false;

  // 本地缓存的 deals/merchants 列表（从 Supabase 直接查）
  List<Map<String, dynamic>> _targetList = [];
  bool _isLoadingTargets = false;

  // splash link type = deal 时的 active deal 列表
  List<Map<String, dynamic>> _activeDeals = [];

  final _bidController   = TextEditingController();
  final _budgetController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bidController.text    = _bidPrice.toStringAsFixed(2);
    _budgetController.text = _dailyBudget.toStringAsFixed(0);

    // 根据 campaignType 预设表单字段和起始步骤（R14）
    final type = widget.campaignType;
    if (type == 'splash') {
      // splash：预设 target=store、placement='splash'，直接跳到 step 3（splash 配置）
      // targetId 将在 _loadTargets 完成后自动填充为当前商家 ID
      _targetType = 'store';
      _placement = 'splash';
      _currentStep = 3;
    } else if (type == 'store_booster') {
      // store_booster：预设 target=store，从 step 1 开始选门店
      _targetType = 'store';
      _currentStep = 1;
    } else if (type == 'deal_booster') {
      // deal_booster：预设 target=deal，从 step 1 开始选 deal
      _targetType = 'deal';
      _currentStep = 1;
    }

    _loadTargets();
  }

  @override
  void dispose() {
    _bidController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------
  // 加载 Deal / Store 列表
  // ----------------------------------------------------------
  Future<void> _loadTargets() async {
    setState(() => _isLoadingTargets = true);
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // 优先用 store switcher 的活跃门店 ID（品牌管理员多门店支持）
      String merchantId = StoreService.globalActiveMerchantId ?? '';
      if (merchantId.isEmpty) {
        final merchantRow = await supabase
            .from('merchants')
            .select('id')
            .eq('user_id', user.id)
            .maybeSingle();
        merchantId = merchantRow?['id'] as String? ?? '';
      }
      if (merchantId.isEmpty) return;

      // 始终加载 active deals（供 splash link type = deal 选择用）
      final dealRows = await supabase
          .from('deals')
          .select('id, title, discount_price')
          .eq('merchant_id', merchantId)
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(50);
      setState(() {
        _activeDeals = List<Map<String, dynamic>>.from(dealRows as List);
      });

      if (_targetType == 'deal') {
        // deal booster 模式：直接复用已加载的 active deals
        setState(() {
          _targetList = _activeDeals;
        });
      } else {
        // store 模式：只展示当前门店本身
        final row = await supabase
            .from('merchants')
            .select('id, name')
            .eq('id', merchantId)
            .maybeSingle();
        if (row != null) {
          setState(() {
            _targetList = [Map<String, dynamic>.from(row)];
            // splash 模式：_loadTargets 完成后自动填充 targetId 为当前商家 ID（R14）
            if (widget.campaignType == 'splash' && _targetId == null) {
              _targetId   = row['id'] as String? ?? '';
              _targetName = row['name'] as String? ?? 'My Store';
            }
          });
        }
      }
    } catch (e) {
      // 加载失败静默处理，用户可手动重试
    } finally {
      setState(() => _isLoadingTargets = false);
    }
  }

  // ----------------------------------------------------------
  // 提交创建
  // ----------------------------------------------------------
  /// UI 预设时段 → Edge Function 所需的 schedule_hours（null 表示全天）
  List<int>? _schedulePresetToHours(String preset) {
    switch (preset) {
      case 'lunch':
        return [11, 12, 13];
      case 'dinner':
        return [17, 18, 19, 20, 21];
      default:
        return null;
    }
  }

  // ----------------------------------------------------------
  // 上传 splash 素材图片到 Supabase Storage
  // ----------------------------------------------------------

  /// 调起图片选择器，选择后上传到 Storage，更新 _splashCreativeUrl
  Future<void> _pickAndUploadCreative() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null) return;

    setState(() {
      _splashCreativeFile = File(picked.path);
      _isUploadingCreative = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      // 查当前商家 ID
      final merchantRow = await supabase
          .from('merchants')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();
      final merchantId = merchantRow?['id'] as String? ?? '';

      // 生成唯一文件名并上传
      final ext = picked.path.split('.').last;
      final fileName =
          'ad-creatives/splash/$merchantId/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await supabase.storage
          .from('ad-creatives')
          .upload(
            'splash/$merchantId/${DateTime.now().millisecondsSinceEpoch}.$ext',
            File(picked.path),
            fileOptions: const FileOptions(upsert: true),
          );

      // 获取公开 URL
      final url = supabase.storage
          .from('ad-creatives')
          .getPublicUrl(
            'splash/$merchantId/${fileName.split('/').last}',
          );

      setState(() => _splashCreativeUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload image: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingCreative = false);
    }
  }

  /// 组装创建请求用的草稿（仅 toCreateJson 字段有效，其余为占位）
  AdCampaign _buildDraftCampaign() {
    // splash 广告位强制 target_type = store，target_id = merchantId
    final isSplash = _placement == 'splash';
    final tt = (isSplash || _targetType == 'store')
        ? TargetType.store
        : TargetType.deal;
    final hours = _schedulePresetToHours(_scheduleHours);
    final start = _startDate != null
        ? DateTime(_startDate!.year, _startDate!.month, _startDate!.day)
        : DateTime.now();
    final end = _endDate != null
        ? DateTime(
            _endDate!.year,
            _endDate!.month,
            _endDate!.day,
            23,
            59,
            59,
          )
        : null;
    return AdCampaign(
      id: '',
      merchantId: '',
      adAccountId: '',
      targetType: tt,
      targetId: _targetId!,
      placement: _placement!,
      categoryId: null,
      bidPrice: _bidPrice,
      dailyBudget: _dailyBudget,
      scheduleHours: hours,
      startAt: start,
      endAt: end,
      status: CampaignStatus.active,
      adminNote: null,
      todaySpend: 0,
      todayImpressions: 0,
      todayClicks: 0,
      totalSpend: 0,
      totalImpressions: 0,
      totalClicks: 0,
      qualityScore: 0.7,
      adScore: 0,
      // splash 专属字段
      creativeUrl: _splashCreativeUrl,
      splashLinkType: _splashLinkType,
      splashLinkValue: _splashLinkValue,
      splashRadiusMeters: _splashRadiusMeters,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _submit() async {
    if (_targetId == null || _placement == null) return;

    setState(() => _isSubmitting = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final draft = _buildDraftCampaign();
      await ref.read(campaignsProvider.notifier).createCampaign(draft);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Campaign launched successfully!'),
            backgroundColor: Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        // 解析错误信息，提取 details 中的 error 字段
        String message = '$e';
        final detailMatch = RegExp(r'error:\s*(.+?)[},]').firstMatch(message);
        if (detailMatch != null) {
          message = detailMatch.group(1)?.trim() ?? message;
        }
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cannot Create Campaign'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ----------------------------------------------------------
  // splash 广告位辅助属性
  // ----------------------------------------------------------

  /// 当前选中的是否为 splash 广告位
  bool get _isSplash => _placement == 'splash';

  /// splash 模式下总步骤数（跳过 target type / target 选择，新增 splash 配置）
  /// 非 splash: 7 步（0-6），splash: 6 步（0,2,2.5=splash,3,4,5,6）
  /// 实现上统一用 0-6 共 7 个 case，splash 时 step1 自动跳过
  int get _totalSteps => 7;

  // ----------------------------------------------------------
  // 步骤是否可进入下一步
  // ----------------------------------------------------------
  bool get _canProceed {
    switch (_currentStep) {
      case 0: return true; // 选 target type 始终可继续（splash 时也直接继续）
      case 1: return _targetId != null; // splash 时自动填充，始终满足
      case 2: return _placement != null;
      case 3:
        // splash 时：必须已上传素材图片
        if (_isSplash) return _splashCreativeUrl != null;
        // 非 splash：出价有效
        return _bidPrice > 0;
      case 4: return _isSplash ? _bidPrice > 0 : _dailyBudget >= 10;
      case 5: return _isSplash ? _dailyBudget >= 10 : true;
      case 6: return true; // 日期范围可选
      default: return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final placementsAsync = ref.watch(placementConfigsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // 步骤进度条
          _StepProgressBar(currentStep: _currentStep, totalSteps: _totalSteps),

          // 步骤内容
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildStepContent(placementsAsync),
            ),
          ),

          // 底部按钮区
          _buildBottomBar(),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // AppBar
  // ----------------------------------------------------------
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.close, size: 22),
        color: const Color(0xFF1A1A2E),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        'New Campaign — Step ${_currentStep + 1} of $_totalSteps',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A2E),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // 步骤内容路由
  // splash 模式步骤顺序：0(target type) → 1(target, 自动填充) → 2(placement)
  //   → 3(splash 配置) → 4(出价) → 5(日预算) → 6(日期范围)
  // 非 splash 步骤顺序：0 → 1 → 2 → 3(出价) → 4(日预算) → 5(时间段) → 6(日期范围)
  // ----------------------------------------------------------
  Widget _buildStepContent(AsyncValue<List<AdPlacementConfig>> placementsAsync) {
    switch (_currentStep) {
      case 0: return _buildStep0TargetType();
      case 1: return _buildStep1SelectTarget();
      case 2: return _buildStep2SelectPlacement(placementsAsync);
      case 3:
        // splash 广告位：显示 splash 专属配置步骤
        if (_isSplash) return _buildStep3SplashConfig();
        return _buildStep3BidPrice(placementsAsync);
      case 4:
        // splash 广告位：step4 是出价
        if (_isSplash) return _buildStep3BidPrice(placementsAsync);
        return _buildStep4DailyBudget();
      case 5:
        // splash 广告位：step5 是日预算
        if (_isSplash) return _buildStep4DailyBudget();
        return _buildStep5ScheduleHours();
      case 6: return _buildStep6DateRange();
      default: return const SizedBox.shrink();
    }
  }

  // ----------------------------------------------------------
  // Step 0: Target Type 选择
  // ----------------------------------------------------------
  Widget _buildStep0TargetType() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          title: 'What do you want to promote?',
          subtitle: 'Choose the type of content for your campaign.',
        ),
        const SizedBox(height: 24),
        _OptionCard(
          icon: Icons.local_offer_outlined,
          title: 'Deal',
          subtitle: 'Promote a specific deal or offer',
          isSelected: _targetType == 'deal',
          onTap: () {
            setState(() {
              _targetType = 'deal';
              _targetId = null;
              _targetName = null;
            });
            _loadTargets();
          },
        ),
        const SizedBox(height: 12),
        _OptionCard(
          icon: Icons.store_outlined,
          title: 'Store',
          subtitle: 'Promote your entire store',
          isSelected: _targetType == 'store',
          onTap: () {
            setState(() {
              _targetType = 'store';
              _targetId = null;
              _targetName = null;
            });
            _loadTargets();
          },
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // Step 1: 选择具体 Deal / Store
  // ----------------------------------------------------------
  Widget _buildStep1SelectTarget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          title: _targetType == 'deal' ? 'Select a Deal' : 'Select a Store',
          subtitle: _targetType == 'deal'
              ? 'Choose which deal to advertise.'
              : 'This will promote your store page.',
        ),
        const SizedBox(height: 24),
        if (_isLoadingTargets)
          const Center(child: CircularProgressIndicator(
            color: Color(0xFFFF6B35),
          ))
        else if (_targetList.isEmpty)
          _EmptyTargetHint(targetType: _targetType)
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _targetList.length,
            itemBuilder: (_, i) {
              final item = _targetList[i];
              final id   = item['id'] as String;
              final name = item['title'] as String? ??
                           item['name']  as String? ?? '';
              return _SelectableTile(
                title: name,
                isSelected: _targetId == id,
                onTap: () => setState(() {
                  _targetId   = id;
                  _targetName = name;
                }),
              );
            },
          ),
      ],
    );
  }

  // ----------------------------------------------------------
  // 根据 campaignType 过滤广告位列表（R8/R13）
  // ----------------------------------------------------------
  List<AdPlacementConfig> _getFilteredPlacements(List<AdPlacementConfig> all) {
    final type = widget.campaignType;
    if (type == 'store_booster') {
      // store_booster 仅展示门店相关广告位
      return all.where((p) =>
        ['home_store_top', 'category_store_top'].contains(p.placement)
      ).toList();
    } else if (type == 'deal_booster') {
      // deal_booster 仅展示 deal 相关广告位（R8：不含 home_banner，CPM 计费不同）
      return all.where((p) =>
        ['home_deal_top', 'category_deal_top'].contains(p.placement)
      ).toList();
    }
    // 无类型限制时显示全部
    return all;
  }

  // ----------------------------------------------------------
  // Step 2: 选择广告位
  // ----------------------------------------------------------
  Widget _buildStep2SelectPlacement(
      AsyncValue<List<AdPlacementConfig>> placementsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          title: 'Choose Ad Placement',
          subtitle: 'Select where your ad will appear.',
        ),
        const SizedBox(height: 24),
        placementsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
          ),
          error: (e, st) => const Text('Failed to load placements'),
          data: (configs) {
            // 根据入口类型过滤广告位列表（R8/R13）
            final filtered = _getFilteredPlacements(configs);
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final config = filtered[i];
                return _PlacementOptionCard(
                  config: config,
                  isSelected: _placement == config.placement,
                  onTap: () async {
                    // 选择广告位，若为 splash 则自动填充 target_id 为当前门店
                    if (config.placement == 'splash') {
                      final supabase = Supabase.instance.client;
                      final user = supabase.auth.currentUser;
                      if (user != null) {
                        final row = await supabase
                            .from('merchants')
                            .select('id, name')
                            .eq('user_id', user.id)
                            .maybeSingle();
                        if (mounted && row != null) {
                          setState(() {
                            _placement = config.placement;
                            _targetId = row['id'] as String? ?? '';
                            _targetName = row['name'] as String? ?? 'My Store';
                            _targetType = 'store';
                          });
                          return;
                        }
                      }
                    }
                    setState(() => _placement = config.placement);
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // Step 3 (splash 专属): splash 广告配置
  // ----------------------------------------------------------
  Widget _buildStep3SplashConfig() {
    // 投放半径选项（米 → 英里显示）
    const radiusOptions = [
      (8047,  '5 miles'),
      (16093, '10 miles'),
      (24140, '15 miles'),
      (40234, '25 miles'),
    ];

    // Link Type 选项
    const linkTypes = [
      ('none',     'None',         Icons.block_outlined),
      ('deal',     'Deal',         Icons.local_offer_outlined),
      ('merchant', 'Merchant',     Icons.store_outlined),
      ('external', 'External URL', Icons.link_outlined),
    ];

    final splashLinkController = TextEditingController(text: _splashLinkValue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          title: 'Splash Ad Settings',
          subtitle: 'Configure your app splash screen ad.',
        ),
        const SizedBox(height: 24),

        // ------------------------------------------------
        // 提示说明
        // ------------------------------------------------
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F0FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: Color(0xFF7C4DFF)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your ad will be shown to users when they open the app, '
                  'once per day per user. CPC billing — you\'re only charged '
                  'when users tap your ad.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF5E35B1), height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ------------------------------------------------
        // 素材图片上传区
        // ------------------------------------------------
        const Text(
          'Ad Creative',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
        ),
        const SizedBox(height: 4),
        const Text(
          'Recommended: 1080×1920 (9:16 portrait)',
          style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _isUploadingCreative ? null : _pickAndUploadCreative,
          child: Container(
            width: double.infinity,
            height: 160,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _splashCreativeUrl != null
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFE0E0E0),
                width: _splashCreativeUrl != null ? 2 : 1,
              ),
            ),
            child: _isUploadingCreative
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
                  )
                : _splashCreativeFile != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.file(
                          _splashCreativeFile!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 40, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to upload image',
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
          ),
        ),
        if (_splashCreativeUrl != null) ...[
          const SizedBox(height: 6),
          const Row(
            children: [
              Icon(Icons.check_circle, size: 14, color: Color(0xFF4CAF50)),
              SizedBox(width: 4),
              Text('Image uploaded', style: TextStyle(fontSize: 12, color: Color(0xFF4CAF50))),
            ],
          ),
        ],
        const SizedBox(height: 24),

        // ------------------------------------------------
        // Link Type 下拉选择
        // ------------------------------------------------
        const Text(
          'Link Type',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
        ),
        const SizedBox(height: 10),
        ...linkTypes.map((lt) {
          final isSelected = _splashLinkType == lt.$1;
          return GestureDetector(
            onTap: () => setState(() {
              _splashLinkType = lt.$1;
              // 切换类型时重置 value
              _splashLinkValue = null;
              splashLinkController.clear();
              // merchant 类型：自动填充当前商家 ID
              if (_splashLinkType == 'merchant' && _targetId != null) {
                _splashLinkValue = _targetId;
                splashLinkController.text = _targetId!;
              }
            }),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFFF6B35).withAlpha(13)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFFF6B35)
                      : const Color(0xFFE0E0E0),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(lt.$3,
                      size: 18,
                      color: isSelected
                          ? const Color(0xFFFF6B35)
                          : Colors.grey.shade500),
                  const SizedBox(width: 10),
                  Text(
                    lt.$2,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFFFF6B35)
                          : const Color(0xFF1A1A2E),
                    ),
                  ),
                  const Spacer(),
                  if (isSelected)
                    const Icon(Icons.check_circle,
                        size: 18, color: Color(0xFFFF6B35)),
                ],
              ),
            ),
          );
        }),

        // ------------------------------------------------
        // Link Value（Link Type 非 none 时显示）
        // deal: 选择列表 / merchant: 自动当前商家 / external: 输入 URL
        // ------------------------------------------------
        if (_splashLinkType == 'deal') ...[
          const SizedBox(height: 16),
          const Text(
            'Select Deal',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
          ),
          const SizedBox(height: 8),
          if (_activeDeals.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Text(
                'No active deals available',
                style: TextStyle(color: Colors.grey, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            )
          else
            ...(_activeDeals.map((deal) {
              final dealId = deal['id'] as String;
              final title = deal['title'] as String? ?? '';
              final price = (deal['discount_price'] as num?)?.toDouble();
              final isSelected = _splashLinkValue == dealId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: isSelected ? const Color(0xFFFFF3ED) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() {
                      _splashLinkValue = dealId;
                      splashLinkController.text = dealId;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFFF6B35) : Colors.grey.shade200,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                if (price != null)
                                  Text('\$${price.toStringAsFixed(2)}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle, color: Color(0xFFFF6B35), size: 22),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            })),
        ] else if (_splashLinkType == 'external') ...[
          const SizedBox(height: 16),
          const Text(
            'URL',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: splashLinkController,
            decoration: InputDecoration(
              hintText: 'https://example.com',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFFF6B35)),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (val) => setState(() => _splashLinkValue = val.isEmpty ? null : val),
          ),
        ] else if (_splashLinkType == 'merchant') ...[
          // merchant 类型：自动填充当前商家 ID，显示提示
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.store, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Will link to your store page',
                      style: TextStyle(fontSize: 13, color: Color(0xFF2E7D32))),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),

        // ------------------------------------------------
        // 投放半径选择
        // ------------------------------------------------
        const Text(
          'Delivery Radius',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: radiusOptions.map((opt) {
            final isSelected = _splashRadiusMeters == opt.$1;
            return GestureDetector(
              onTap: () => setState(() => _splashRadiusMeters = opt.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFF6B35) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFFF6B35)
                        : const Color(0xFFE0E0E0),
                  ),
                ),
                child: Text(
                  opt.$2,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          'Your ad will be shown to users within this distance.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // Step 3: 设置出价
  // ----------------------------------------------------------
  Widget _buildStep3BidPrice(
      AsyncValue<List<AdPlacementConfig>> placementsAsync) {
    // 找到当前选中广告位的配置
    final config = placementsAsync.maybeWhen(
      data: (list) =>
          list.where((c) => c.placement == _placement).firstOrNull,
      orElse: () => null,
    );
    // config 可能为 null（广告位未选或列表未加载），下方用 config?.xxx 访问

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          title: 'Set Your Bid',
          subtitle: 'You pay per click. Set how much you\'d bid.',
        ),
        const SizedBox(height: 24),
        if (config != null) ...[
          const SizedBox(height: 16),
        ],
        // 出价输入框
        TextField(
          controller: _bidController,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
          ],
          decoration: InputDecoration(
            labelText: 'Bid per click',
            prefixText: '\$ ',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFFF6B35)),
            ),
            helperText: null,
          ),
          onChanged: (val) {
            final parsed = double.tryParse(val) ?? 0;
            setState(() => _bidPrice = parsed);
          },
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // Step 4: 设置日预算
  // ----------------------------------------------------------
  Widget _buildStep4DailyBudget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          title: 'Set Daily Budget',
          subtitle: 'Your campaign will stop showing ads once the daily budget is reached.',
        ),
        const SizedBox(height: 24),
        // 快速选择
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [10, 20, 50, 100].map((amount) {
            final isSelected = _dailyBudget == amount.toDouble();
            return GestureDetector(
              onTap: () {
                setState(() => _dailyBudget = amount.toDouble());
                _budgetController.text = amount.toString();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFF6B35)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFFF6B35)
                        : const Color(0xFFE0E0E0),
                  ),
                ),
                child: Text(
                  '\$$amount',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        // 自定义金额输入
        TextField(
          controller: _budgetController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Daily budget',
            prefixText: '\$ ',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFFF6B35)),
            ),
            helperText: 'Minimum \$10/day',
          ),
          onChanged: (val) {
            final parsed = double.tryParse(val) ?? 0;
            setState(() => _dailyBudget = parsed);
          },
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // Step 5: 时间段
  // ----------------------------------------------------------
  Widget _buildStep5ScheduleHours() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          title: 'Ad Schedule (Optional)',
          subtitle: 'Choose when your ad runs during the day.',
        ),
        const SizedBox(height: 24),
        ...[
          ('all_day', 'All Day', '24 hours / 7 days'),
          ('lunch',   'Lunch Time',  '11am – 2pm'),
          ('dinner',  'Dinner Time', '5pm – 9pm'),
        ].map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _OptionCard(
              icon: item.$1 == 'all_day'
                  ? Icons.wb_sunny_outlined
                  : item.$1 == 'lunch'
                      ? Icons.lunch_dining_outlined
                      : Icons.dinner_dining_outlined,
              title: item.$2,
              subtitle: item.$3,
              isSelected: _scheduleHours == item.$1,
              onTap: () => setState(() => _scheduleHours = item.$1),
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // Step 6: 日期范围（可选）
  // ----------------------------------------------------------
  Widget _buildStep6DateRange() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          title: 'Date Range (Optional)',
          subtitle: 'Leave empty to run indefinitely.',
        ),
        const SizedBox(height: 24),
        // 开始日期
        _DatePickerTile(
          label: 'Start Date',
          date: _startDate,
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) setState(() => _startDate = picked);
          },
          onClear: () => setState(() => _startDate = null),
        ),
        const SizedBox(height: 12),
        // 结束日期
        _DatePickerTile(
          label: 'End Date',
          date: _endDate,
          onTap: () async {
            final firstDate = _startDate ?? DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: firstDate.add(const Duration(days: 1)),
              firstDate: firstDate.add(const Duration(days: 1)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) setState(() => _endDate = picked);
          },
          onClear: () => setState(() => _endDate = null),
        ),

        const SizedBox(height: 32),
        // 总结预览
        _CampaignSummary(
          targetType:    _targetType,
          targetName:    _targetName ?? '',
          placement:     _placement ?? '',
          bidPrice:      _bidPrice,
          dailyBudget:   _dailyBudget,
          scheduleHours: _scheduleHours,
          startDate:     _startDate,
          endDate:       _endDate,
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // 底部按钮区
  // ----------------------------------------------------------
  Widget _buildBottomBar() {
    final isLastStep = _currentStep == 6;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 上一步按钮（第一步隐藏）
          if (_currentStep > 0)
            Expanded(
              flex: 1,
              child: OutlinedButton(
                onPressed: () => setState(() => _currentStep--),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  side: const BorderSide(color: Color(0xFFE0E0E0)),
                ),
                child: const Text(
                  'Back',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),

          // 下一步 / Launch Campaign 按钮
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _canProceed && !_isSubmitting
                  ? () {
                      if (isLastStep) {
                        _submit();
                      } else {
                        setState(() => _currentStep++);
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade200,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      isLastStep ? 'Launch Campaign' : 'Next',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// 辅助私有组件
// =============================================================

// 步骤进度条
class _StepProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _StepProgressBar({
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      value: (currentStep + 1) / totalSteps,
      backgroundColor: const Color(0xFFE0E0E0),
      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
      minHeight: 3,
    );
  }
}

// 步骤标题
class _StepTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _StepTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade500,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

// 选项卡片（Target Type / Schedule）
class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF6B35).withAlpha(13)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFF6B35)
                : const Color(0xFFE0E0E0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFFF6B35).withAlpha(26)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 22,
                color: isSelected
                    ? const Color(0xFFFF6B35)
                    : Colors.grey.shade500,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? const Color(0xFFFF6B35)
                          : const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFFFF6B35),
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

// 可选择的列表项（Deal / Store 列表）
class _SelectableTile extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _SelectableTile({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF6B35).withAlpha(13)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFF6B35)
                : const Color(0xFFE0E0E0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? const Color(0xFFFF6B35)
                      : const Color(0xFF1A1A2E),
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFFFF6B35),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

// 广告位选项卡片
class _PlacementOptionCard extends StatelessWidget {
  final AdPlacementConfig config;
  final bool isSelected;
  final VoidCallback onTap;

  const _PlacementOptionCard({
    required this.config,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF6B35).withAlpha(13)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFF6B35)
                : const Color(0xFFE0E0E0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.displayName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? const Color(0xFFFF6B35)
                          : const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${config.suggestedBidLow.toStringAsFixed(2)}'
                    ' – \$${config.suggestedBidHigh.toStringAsFixed(2)} / click',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFFFF6B35),
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

// 日期选择器 Tile
class _DatePickerTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DatePickerTile({
    required this.label,
    required this.date,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: Color(0xFFFF6B35)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                date != null
                    ? '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}'
                    : label,
                style: TextStyle(
                  fontSize: 14,
                  color: date != null
                      ? const Color(0xFF1A1A2E)
                      : Colors.grey.shade400,
                ),
              ),
            ),
            if (date != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 18, color: Colors.grey.shade400),
              )
            else
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// Campaign 总结预览
class _CampaignSummary extends StatelessWidget {
  final String targetType;
  final String targetName;
  final String placement;
  final double bidPrice;
  final double dailyBudget;
  final String scheduleHours;
  final DateTime? startDate;
  final DateTime? endDate;

  const _CampaignSummary({
    required this.targetType,
    required this.targetName,
    required this.placement,
    required this.bidPrice,
    required this.dailyBudget,
    required this.scheduleHours,
    this.startDate,
    this.endDate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F0FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Campaign Summary',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5E35B1),
            ),
          ),
          const SizedBox(height: 12),
          _SummaryRow(
              label: 'Target',
              value: '$targetName (${targetType.toUpperCase()})'),
          _SummaryRow(label: 'Placement', value: placement),
          _SummaryRow(
              label: 'Bid', value: '\$${bidPrice.toStringAsFixed(2)}/click'),
          _SummaryRow(
              label: 'Daily Budget',
              value: '\$${dailyBudget.toStringAsFixed(2)}/day'),
          _SummaryRow(label: 'Schedule', value: scheduleHours),
          if (startDate != null)
            _SummaryRow(
                label: 'Start',
                value:
                    '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}'),
          if (endDate != null)
            _SummaryRow(
                label: 'End',
                value:
                    '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}'),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 无 Target 可选时的提示
class _EmptyTargetHint extends StatelessWidget {
  final String targetType;

  const _EmptyTargetHint({required this.targetType});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            targetType == 'deal'
                ? 'No active deals found.\nCreate a deal first to promote it.'
                : 'No store found.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
