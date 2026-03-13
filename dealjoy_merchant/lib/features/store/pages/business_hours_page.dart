// 营业时间设置页面
// 7 天营业时间配置：每天一行（开关 + 开始/结束时间选择器）
// 底部"Save Changes"按钮批量保存

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/store_info.dart';
import '../providers/store_provider.dart';
import '../widgets/business_hours_row.dart';

// ============================================================
// BusinessHoursPage — 营业时间设置页（ConsumerStatefulWidget）
// ============================================================
class BusinessHoursPage extends ConsumerStatefulWidget {
  const BusinessHoursPage({super.key});

  @override
  ConsumerState<BusinessHoursPage> createState() => _BusinessHoursPageState();
}

class _BusinessHoursPageState extends ConsumerState<BusinessHoursPage> {
  // 本地编辑状态：7 天营业时间列表（从 provider 初始化后本地维护）
  List<BusinessHours>? _localHours;
  bool _isInitialized = false;
  bool _isSaving = false;

  // 默认 7 天营业时间（新商家尚无数据时使用）
  static List<BusinessHours> _buildDefaultHours() {
    return List.generate(7, (dayOfWeek) {
      // 周一(1)-周五(5): 10:00-22:00，周六(6)日(0): 11:00-22:00
      final isWeekend = dayOfWeek == 0 || dayOfWeek == 6;
      return BusinessHours(
        dayOfWeek: dayOfWeek,
        openTime: isWeekend ? '11:00' : '10:00',
        closeTime: '22:00',
        isClosed: false,
      );
    });
  }

  // 从 provider 数据初始化本地状态（只执行一次）
  void _initIfNeeded(List<BusinessHours> serverHours) {
    if (_isInitialized) return;
    if (serverHours.isEmpty) {
      _localHours = _buildDefaultHours();
    } else {
      // 确保 7 天都有记录，缺少的补默认值
      final existingMap = {for (final h in serverHours) h.dayOfWeek: h};
      _localHours = List.generate(7, (day) {
        return existingMap[day] ??
            BusinessHours(
              dayOfWeek: day,
              openTime: (day == 0 || day == 6) ? '11:00' : '10:00',
              closeTime: '22:00',
              isClosed: false,
            );
      });
    }
    _isInitialized = true;
  }

  // 更新某一天的营业时间
  void _updateDay(int dayOfWeek, BusinessHours updated) {
    setState(() {
      _localHours = _localHours!
          .map((h) => h.dayOfWeek == dayOfWeek ? updated : h)
          .toList();
    });
  }

  // 全部设为营业（快捷操作）
  void _setAllOpen() {
    setState(() {
      _localHours = _localHours!.map((h) {
        return h.copyWith(
          isClosed: false,
          openTime: h.openTime ?? '10:00',
          closeTime: h.closeTime ?? '22:00',
        );
      }).toList();
    });
  }

  // 保存营业时间
  Future<void> _save() async {
    if (_localHours == null) return;

    // 校验：营业日必须有开始和结束时间
    for (final h in _localHours!) {
      if (!h.isClosed) {
        if (h.openTime == null || h.closeTime == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${BusinessHours.dayName(h.dayOfWeek)}: open/close time is required',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        // 校验开始时间早于结束时间
        final open = _parseMinutes(h.openTime!);
        final close = _parseMinutes(h.closeTime!);
        if (open >= close) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${BusinessHours.dayName(h.dayOfWeek)}: close time must be after open time',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    }

    setState(() => _isSaving = true);

    try {
      await ref
          .read(storeProvider.notifier)
          .updateBusinessHours(_localHours!);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Business hours saved successfully'),
          backgroundColor: Color(0xFF4CAF50),
          duration: Duration(seconds: 2),
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // 将 "HH:mm" 转换为分钟数（用于比较大小）
  int _parseMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: const Color(0xFF333333),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Business Hours',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        actions: [
          // 快捷：全部设为营业
          TextButton(
            onPressed: _setAllOpen,
            child: const Text(
              'All Open',
              style: TextStyle(
                color: Color(0xFFFF6B35),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
      body: storeAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
        ),
        error: (e, _) => Center(
          child: Text(
            'Failed to load store: $e',
            style: const TextStyle(color: Colors.red),
          ),
        ),
        data: (store) {
          // 初始化本地状态
          _initIfNeeded(store.hours);

          if (_localHours == null) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
            );
          }

          return Column(
            children: [
              // 说明文字
              Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: const Text(
                  'Set your store\'s operating hours. Customers will see "Closed" outside these hours.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF888888),
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 0.5),

              // 营业时间列表
              Expanded(
                child: Container(
                  color: Colors.white,
                  child: ListView.builder(
                    itemCount: _localHours!.length,
                    itemBuilder: (_, index) {
                      final h = _localHours![index];
                      return BusinessHoursRow(
                        hours: h,
                        onChanged: (updated) =>
                            _updateDay(h.dayOfWeek, updated),
                      );
                    },
                  ),
                ),
              ),

              // 底部保存按钮
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      key: const ValueKey('business_hours_save_btn'),
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B35),
                        disabledBackgroundColor:
                            const Color(0xFFFF6B35).withValues(alpha: 0.5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
