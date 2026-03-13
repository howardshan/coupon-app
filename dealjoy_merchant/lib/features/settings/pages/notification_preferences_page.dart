// 通知偏好设置页面
// 功能: 每种通知类型一行 Switch，onChange 实时写入 SharedPreferences

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settings_models.dart';
import '../providers/settings_provider.dart';

// ============================================================
// _NotifItem — 单条通知配置（纯数据，不依赖 Flutter）
// ============================================================
class _NotifItem {
  const _NotifItem({
    required this.label,
    required this.description,
    required this.icon,
    required this.getValue,
    required this.setValue,
  });

  final String label;
  final String description;
  final IconData icon;

  /// 从 NotificationPreferences 读取该项的当前值
  final bool Function(NotificationPreferences) getValue;

  /// 返回更新了该项的新 NotificationPreferences
  final NotificationPreferences Function(NotificationPreferences, bool)
      setValue;
}

// ============================================================
// 全部通知配置列表（静态定义）
// ============================================================
const _notifItems = [
  _NotifItem(
    label: 'New Orders',
    description: 'Get notified when a customer places an order',
    icon: Icons.receipt_long_outlined,
    getValue: _getNewOrder,
    setValue: _setNewOrder,
  ),
  _NotifItem(
    label: 'Redemptions',
    description: 'Alert when a customer redeems a voucher',
    icon: Icons.qr_code_scanner,
    getValue: _getRedemption,
    setValue: _setRedemption,
  ),
  _NotifItem(
    label: 'Deal Approval',
    description: 'Updates on deal review status',
    icon: Icons.verified_outlined,
    getValue: _getDealApproved,
    setValue: _setDealApproved,
  ),
  _NotifItem(
    label: 'Review Results',
    description: 'When customers leave a review on your store',
    icon: Icons.star_outline,
    getValue: _getReviewResult,
    setValue: _setReviewResult,
  ),
  _NotifItem(
    label: 'System Announcements',
    description: 'Platform updates and important notices',
    icon: Icons.campaign_outlined,
    getValue: _getSystemAnnouncement,
    setValue: _setSystemAnnouncement,
  ),
];

// 静态 getter/setter 函数（避免 lambda 在 const 中不支持）
bool _getNewOrder(NotificationPreferences p) => p.newOrder;
bool _getRedemption(NotificationPreferences p) => p.redemption;
bool _getDealApproved(NotificationPreferences p) => p.dealApproved;
bool _getReviewResult(NotificationPreferences p) => p.reviewResult;
bool _getSystemAnnouncement(NotificationPreferences p) => p.systemAnnouncement;

NotificationPreferences _setNewOrder(NotificationPreferences p, bool v) =>
    p.copyWith(newOrder: v);
NotificationPreferences _setRedemption(NotificationPreferences p, bool v) =>
    p.copyWith(redemption: v);
NotificationPreferences _setDealApproved(NotificationPreferences p, bool v) =>
    p.copyWith(dealApproved: v);
NotificationPreferences _setReviewResult(NotificationPreferences p, bool v) =>
    p.copyWith(reviewResult: v);
NotificationPreferences _setSystemAnnouncement(
        NotificationPreferences p, bool v) =>
    p.copyWith(systemAnnouncement: v);

// ============================================================
// NotificationPreferencesPage — 通知偏好页（ConsumerStatefulWidget）
// ============================================================
class NotificationPreferencesPage extends ConsumerStatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  ConsumerState<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends ConsumerState<NotificationPreferencesPage> {
  @override
  Widget build(BuildContext context) {
    // 监听通知偏好状态
    final prefsAsync = ref.watch(notificationPrefsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Notification Preferences'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: prefsAsync.when(
        // 加载中
        loading: () => const Center(child: CircularProgressIndicator()),
        // 错误（实际极罕见）
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text('Failed to load preferences\n$e',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                key: const ValueKey('notification_retry_btn'),
                onPressed: () =>
                    ref.read(notificationPrefsProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        // 正常显示开关列表
        data: (prefs) => _buildList(prefs),
      ),
    );
  }

  Widget _buildList(NotificationPreferences prefs) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      children: [
        // 说明文案
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            "Choose which notifications you'd like to receive. "
            'Changes are saved automatically.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
        ),

        // 通知开关卡片
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < _notifItems.length; i++)
                _buildSwitchTile(prefs, _notifItems[i], isLast: i == _notifItems.length - 1),
            ],
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // 单条通知开关行
  // ----------------------------------------------------------
  Widget _buildSwitchTile(
    NotificationPreferences prefs,
    _NotifItem item, {
    bool isLast = false,
  }) {
    final isEnabled = item.getValue(prefs);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // 图标
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isEnabled
                      ? const Color(0xFFFF6B35).withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.icon,
                  size: 20,
                  color: isEnabled
                      ? const Color(0xFFFF6B35)
                      : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),

              // 标题 + 描述
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),

              // Switch
              Switch.adaptive(
                value: isEnabled,
                activeThumbColor: Colors.white,
                activeTrackColor: const Color(0xFFFF6B35),
                onChanged: (newVal) {
                  // 获取当前 prefs（从 state 中读，确保最新）
                  final currentPrefs =
                      ref.read(notificationPrefsProvider).value;
                  if (currentPrefs == null) return;
                  final updated = item.setValue(currentPrefs, newVal);
                  // 调用 notifier 更新并持久化
                  ref
                      .read(notificationPrefsProvider.notifier)
                      .update(updated);
                },
              ),
            ],
          ),
        ),
        // 非最后一项显示分隔线
        if (!isLast)
          Divider(
            height: 1,
            indent: 64,
            color: Colors.grey.withValues(alpha: 0.15),
          ),
      ],
    );
  }
}
