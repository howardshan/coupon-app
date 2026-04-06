// 编辑 Campaign 页面
// 有消费（totalSpend > 0）：只能改 dailyBudget 和 scheduleHours
// 无消费：可改所有字段（出价、预算、时间段、日期）
// 显示 adminPaused 状态提示

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/promotions_models.dart';
import '../providers/promotions_provider.dart';

// =============================================================
// CampaignEditPage — 编辑 Campaign 页面（ConsumerStatefulWidget）
// =============================================================
class CampaignEditPage extends ConsumerStatefulWidget {
  final String campaignId;

  const CampaignEditPage({super.key, required this.campaignId});

  @override
  ConsumerState<CampaignEditPage> createState() => _CampaignEditPageState();
}

class _CampaignEditPageState extends ConsumerState<CampaignEditPage> {
  // 编辑表单状态
  late double _bidPrice;
  late double _dailyBudget;
  late String _scheduleHours;
  DateTime? _startDate;
  DateTime? _endDate;

  bool _isSubmitting = false;
  bool _initialized = false;

  final _bidController    = TextEditingController();
  final _budgetController = TextEditingController();
  final _formKey          = GlobalKey<FormState>();

  @override
  void dispose() {
    _bidController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------
  // 从 campaign 对象初始化表单
  // ----------------------------------------------------------
  /// 后端 schedule_hours 列表 → 编辑页单选预设
  String _presetFromScheduleHours(List<int>? h) {
    if (h == null || h.isEmpty) return 'all_day';
    final s = h.toSet();
    if (s.containsAll({11, 12, 13}) && s.length <= 4) return 'lunch';
    if (h.any((e) => e >= 17 && e <= 21)) return 'dinner';
    return 'all_day';
  }

  /// 预设 → 创建/更新用的 schedule_hours
  List<int>? _hoursFromPreset(String k) {
    switch (k) {
      case 'lunch':
        return [11, 12, 13];
      case 'dinner':
        return [17, 18, 19, 20, 21];
      default:
        return null;
    }
  }

  void _initFromCampaign(AdCampaign campaign) {
    if (_initialized) return;
    _initialized = true;
    _bidPrice = campaign.bidPrice;
    _dailyBudget = campaign.dailyBudget;
    _scheduleHours = _presetFromScheduleHours(campaign.scheduleHours);
    _startDate = campaign.startAt;
    _endDate = campaign.endAt;
    _bidController.text = campaign.bidPrice.toStringAsFixed(2);
    _budgetController.text = campaign.dailyBudget.toStringAsFixed(0);
  }

  // ----------------------------------------------------------
  // 保存更新
  // ----------------------------------------------------------
  Future<void> _save(AdCampaign campaign) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final hasSpend = campaign.totalSpend > 0;

      await ref.read(campaignsProvider.notifier).updateCampaignOnServer(
            campaignId: widget.campaignId,
            dailyBudget: _dailyBudget,
            applyScheduleHours: true,
            scheduleHours: _hoursFromPreset(_scheduleHours),
            bidPrice: hasSpend ? null : _bidPrice,
            startAt: (!hasSpend && _startDate != null)
                ? DateTime(
                    _startDate!.year,
                    _startDate!.month,
                    _startDate!.day,
                  )
                : null,
            applyEndAt: !hasSpend,
            endAt: !hasSpend
                ? (_endDate != null
                    ? DateTime(
                        _endDate!.year,
                        _endDate!.month,
                        _endDate!.day,
                        23,
                        59,
                        59,
                      )
                    : null)
                : null,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Campaign updated successfully!'),
            backgroundColor: Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update campaign: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final campaignsAsync = ref.watch(campaignsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(context),
      body: campaignsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
        ),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (campaigns) {
          // 在列表中找到对应 campaign
          final matched = campaigns
              .where((c) => c.id == widget.campaignId)
              .toList();

          if (matched.isEmpty) {
            return const Center(child: Text('Campaign not found'));
          }

          final campaign = matched.first;

          // 初始化表单（仅首次）
          _initFromCampaign(campaign);

          return _buildBody(campaign);
        },
      ),
    );
  }

  // ----------------------------------------------------------
  // AppBar
  // ----------------------------------------------------------
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        color: const Color(0xFF1A1A2E),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text(
        'Edit Campaign',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A2E),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // 主体内容
  // ----------------------------------------------------------
  Widget _buildBody(AdCampaign campaign) {
    final hasSpend = campaign.totalSpend > 0;

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ------------------------------------------------
            // Admin 暂停提示
            // ------------------------------------------------
            if (campaign.status == CampaignStatus.adminPaused) ...[
              _AdminPausedBanner(),
              const SizedBox(height: 16),
            ],

            // ------------------------------------------------
            // 只读信息（target、placement）
            // ------------------------------------------------
            _ReadOnlyInfoCard(campaign: campaign),
            const SizedBox(height: 20),

            // ------------------------------------------------
            // 有消费时的限制提示
            // ------------------------------------------------
            if (hasSpend) ...[
              _SpendLimitBanner(totalSpend: campaign.totalSpend),
              const SizedBox(height: 20),
            ],

            // ------------------------------------------------
            // 出价（无消费才可编辑）
            // ------------------------------------------------
            _SectionLabel(label: 'Bid per Click'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _bidController,
              enabled: !hasSpend,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'^\d+\.?\d{0,2}')),
              ],
              decoration: _inputDecoration(
                label: 'Bid per click',
                prefix: '\$ ',
                hint: hasSpend ? 'Cannot change after spend' : null,
              ),
              validator: (val) {
                final v = double.tryParse(val ?? '');
                if (v == null || v <= 0) return 'Enter a valid bid';
                return null;
              },
              onChanged: (val) {
                final parsed = double.tryParse(val) ?? 0;
                setState(() => _bidPrice = parsed);
              },
            ),
            const SizedBox(height: 20),

            // ------------------------------------------------
            // 日预算（始终可编辑）
            // ------------------------------------------------
            _SectionLabel(label: 'Daily Budget'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _budgetController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _inputDecoration(
                label: 'Daily budget',
                prefix: '\$ ',
              ),
              validator: (val) {
                final v = double.tryParse(val ?? '');
                if (v == null || v < 10) return 'Minimum \$10/day';
                return null;
              },
              onChanged: (val) {
                final parsed = double.tryParse(val) ?? 0;
                setState(() => _dailyBudget = parsed);
              },
            ),
            const SizedBox(height: 20),

            // ------------------------------------------------
            // 时间段（始终可编辑）
            // ------------------------------------------------
            _SectionLabel(label: 'Ad Schedule'),
            const SizedBox(height: 8),
            _ScheduleSelector(
              selected: _scheduleHours,
              onChanged: (val) => setState(() => _scheduleHours = val),
            ),
            const SizedBox(height: 20),

            // ------------------------------------------------
            // 日期范围（无消费才可编辑）
            // ------------------------------------------------
            _SectionLabel(label: 'Date Range'),
            const SizedBox(height: 8),
            _DateRangeSection(
              enabled: !hasSpend,
              startDate: _startDate,
              endDate: _endDate,
              onStartChanged: hasSpend
                  ? null
                  : (d) => setState(() => _startDate = d),
              onEndChanged: hasSpend
                  ? null
                  : (d) => setState(() => _endDate = d),
            ),
            const SizedBox(height: 40),

            // ------------------------------------------------
            // 保存按钮
            // ------------------------------------------------
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : () => _save(campaign),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade200,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // 输入框装饰
  // ----------------------------------------------------------
  InputDecoration _inputDecoration({
    required String label,
    String? prefix,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      prefixText: prefix,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFFF6B35)),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
      ),
    );
  }
}

// =============================================================
// 私有辅助组件
// =============================================================

// Admin 暂停横幅
class _AdminPausedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.block, color: Color(0xFFE53935), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This campaign has been paused by an admin. '
              'Please contact support to resume it.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFFB71C1C),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 有消费限制提示横幅
class _SpendLimitBanner extends StatelessWidget {
  final double totalSpend;

  const _SpendLimitBanner({required this.totalSpend});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFE65100), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This campaign has \$${totalSpend.toStringAsFixed(2)} in spend. '
              'You can only edit Daily Budget and Ad Schedule now.',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF7F4700),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 只读信息卡片（target、placement）
class _ReadOnlyInfoCard extends StatelessWidget {
  final AdCampaign campaign;

  const _ReadOnlyInfoCard({required this.campaign});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Campaign Info',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF9E9E9E),
            ),
          ),
          const SizedBox(height: 10),
          _InfoRow(
            label: 'Target',
            value:
                '${campaign.targetType == TargetType.deal ? "Deal" : "Store"} · ${campaign.targetId}',
          ),
          const SizedBox(height: 6),
          _InfoRow(label: 'Placement', value: campaign.placement),
          const SizedBox(height: 6),
          _InfoRow(
            label: 'Total Spend',
            value: '\$${campaign.totalSpend.toStringAsFixed(2)}',
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            '$label:',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
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
    );
  }
}

// 区块标签
class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A1A2E),
      ),
    );
  }
}

// 时间段选择器
class _ScheduleSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _ScheduleSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const options = [
      ('all_day', 'All Day',    '24 hrs'),
      ('lunch',   'Lunch',      '11am-2pm'),
      ('dinner',  'Dinner',     '5pm-9pm'),
    ];
    return Row(
      children: options.map((opt) {
        final isSelected = selected == opt.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(opt.$1),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFFF6B35)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFFF6B35)
                      : const Color(0xFFE0E0E0),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    opt.$2,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    opt.$3,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? Colors.white70
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// 日期范围选择区
class _DateRangeSection extends StatelessWidget {
  final bool enabled;
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<DateTime?>? onStartChanged;
  final ValueChanged<DateTime?>? onEndChanged;

  const _DateRangeSection({
    required this.enabled,
    this.startDate,
    this.endDate,
    this.onStartChanged,
    this.onEndChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DateTile(
          label: 'Start Date',
          date: startDate,
          enabled: enabled,
          onTap: enabled
              ? () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: startDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate:
                        DateTime.now().add(const Duration(days: 365)),
                  );
                  onStartChanged?.call(picked);
                }
              : null,
          onClear: enabled ? () => onStartChanged?.call(null) : null,
        ),
        const SizedBox(height: 10),
        _DateTile(
          label: 'End Date',
          date: endDate,
          enabled: enabled,
          onTap: enabled
              ? () async {
                  final first = startDate ?? DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate:
                        endDate ?? first.add(const Duration(days: 1)),
                    firstDate: first.add(const Duration(days: 1)),
                    lastDate:
                        DateTime.now().add(const Duration(days: 365)),
                  );
                  onEndChanged?.call(picked);
                }
              : null,
          onClear: enabled ? () => onEndChanged?.call(null) : null,
        ),
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final bool enabled;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  const _DateTile({
    required this.label,
    required this.date,
    required this.enabled,
    this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? const Color(0xFFE0E0E0)
                : const Color(0xFFEEEEEE),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: enabled
                  ? const Color(0xFFFF6B35)
                  : Colors.grey.shade300,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                date != null
                    ? '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}'
                    : label,
                style: TextStyle(
                  fontSize: 14,
                  color: date != null
                      ? (enabled
                          ? const Color(0xFF1A1A2E)
                          : Colors.grey.shade400)
                      : Colors.grey.shade400,
                ),
              ),
            ),
            if (date != null && enabled && onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close,
                    size: 18, color: Colors.grey.shade400),
              )
            else
              Icon(
                Icons.chevron_right,
                color: enabled
                    ? Colors.grey.shade400
                    : Colors.grey.shade300,
              ),
          ],
        ),
      ),
    );
  }
}
