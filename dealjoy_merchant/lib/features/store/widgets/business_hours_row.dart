// 单日营业时间行组件
// 包含: 星期名称 + 开关(营业/休息) + 开始时间选择 + 结束时间选择

import 'package:flutter/material.dart';
import '../models/store_info.dart';

// ============================================================
// BusinessHoursRow — 单日营业时间配置行（StatelessWidget）
// 状态由父页面 BusinessHoursPage 统一管理
// ============================================================
class BusinessHoursRow extends StatelessWidget {
  const BusinessHoursRow({
    super.key,
    required this.hours,
    required this.onChanged,
  });

  /// 当前这天的营业时间数据
  final BusinessHours hours;

  /// 数据变更回调（由父页面更新状态）
  final void Function(BusinessHours updated) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF0F0F0), width: 1),
        ),
      ),
      child: Row(
        children: [
          // 星期名称（固定宽度 96px 对齐）
          SizedBox(
            width: 96,
            child: Text(
              BusinessHours.dayName(hours.dayOfWeek),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: hours.isClosed
                    ? const Color(0xFFBBBBBB)
                    : const Color(0xFF333333),
              ),
            ),
          ),

          // 营业/休息开关
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: !hours.isClosed,
              onChanged: (isOpen) {
                onChanged(
                  hours.copyWith(
                    isClosed: !isOpen,
                    // 切换为营业时，若时间为空则设默认值
                    openTime: isOpen ? (hours.openTime ?? '10:00') : null,
                    closeTime: isOpen ? (hours.closeTime ?? '22:00') : null,
                  ),
                );
              },
              activeThumbColor: const Color(0xFFFF6B35),
              activeTrackColor: const Color(0xFFFFCCB3),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),

          const SizedBox(width: 4),

          // 营业时间选择区（休息日时显示"Closed"）
          Expanded(
            child: hours.isClosed
                ? const Text(
                    'Closed',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFFBBBBBB),
                    ),
                  )
                : Row(
                    children: [
                      // 开始时间
                      Expanded(
                        child: _TimePickerButton(
                          time: hours.openTime ?? '10:00',
                          label: 'Open',
                          onChanged: (newTime) {
                            onChanged(hours.copyWith(openTime: newTime));
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '—',
                          style: TextStyle(
                            color: Color(0xFF999999),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      // 结束时间
                      Expanded(
                        child: _TimePickerButton(
                          time: hours.closeTime ?? '22:00',
                          label: 'Close',
                          onChanged: (newTime) {
                            onChanged(hours.copyWith(closeTime: newTime));
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 时间选择按钮（点击弹出 showTimePicker）
// ============================================================
class _TimePickerButton extends StatelessWidget {
  const _TimePickerButton({
    required this.time,
    required this.label,
    required this.onChanged,
  });

  /// 当前时间字符串，格式 "HH:mm"
  final String time;

  /// 按钮辅助标签（"Open" / "Close"）
  final String label;

  /// 时间选择完成回调，返回 "HH:mm" 格式字符串
  final void Function(String time) onChanged;

  /// 将 "HH:mm" 字符串解析为 TimeOfDay
  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 10,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
  }

  /// 将 TimeOfDay 格式化为 "HH:mm" 字符串
  String _formatTime(TimeOfDay tod) {
    final h = tod.hour.toString().padLeft(2, '0');
    final m = tod.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTime(time),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: const Color(0xFFFF6B35),
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      onChanged(_formatTime(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _pick(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              time,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.access_time_rounded,
              size: 14,
              color: Color(0xFF999999),
            ),
          ],
        ),
      ),
    );
  }
}
