// 商家端邮件偏好设置页面
// 读写 merchant_email_preferences 表（Supabase），仅展示 global_enabled=true 且 user_configurable=true 的商家端邮件类型

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 单条邮件偏好数据
class _EmailPrefItem {
  final String code;
  final String name;
  bool enabled;

  _EmailPrefItem({
    required this.code,
    required this.name,
    required this.enabled,
  });
}

class EmailPreferencesPage extends StatefulWidget {
  const EmailPreferencesPage({super.key});

  @override
  State<EmailPreferencesPage> createState() => _EmailPreferencesPageState();
}

class _EmailPreferencesPageState extends State<EmailPreferencesPage> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  String? _merchantId;
  List<_EmailPrefItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── 数据加载 ──────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      // 获取 merchant_id
      final merchantRes = await _supabase
          .from('merchants')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      if (merchantRes == null) throw Exception('Merchant profile not found');
      final merchantId = merchantRes['id'] as String;

      // 查询全局启用且商家可配置的邮件类型
      final settingsRes = await _supabase
          .from('email_type_settings')
          .select('email_code, email_name')
          .eq('recipient_type', 'merchant')
          .eq('global_enabled', true)
          .eq('user_configurable', true)
          .order('email_code');

      if (settingsRes.isEmpty) {
        setState(() {
          _merchantId = merchantId;
          _items = [];
          _loading = false;
        });
        return;
      }

      final codes =
          settingsRes.map((e) => e['email_code'] as String).toList();

      // 查询商家当前偏好
      final prefsRes = await _supabase
          .from('merchant_email_preferences')
          .select('email_code, enabled')
          .eq('merchant_id', merchantId)
          .inFilter('email_code', codes);

      final prefsMap = {
        for (final p in prefsRes)
          p['email_code'] as String: p['enabled'] as bool
      };

      setState(() {
        _merchantId = merchantId;
        _items = settingsRes.map((s) {
          final code = s['email_code'] as String;
          return _EmailPrefItem(
            code: code,
            name: s['email_name'] as String? ?? code,
            enabled: prefsMap[code] ?? true, // 无记录默认开启
          );
        }).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── 切换开关 ──────────────────────────────────────────────────────────────

  Future<void> _toggle(int index, bool newVal) async {
    final merchantId = _merchantId;
    if (merchantId == null) return;

    // 乐观更新
    final oldVal = _items[index].enabled;
    setState(() => _items[index].enabled = newVal);

    try {
      await _supabase.from('merchant_email_preferences').upsert(
        {
          'merchant_id': merchantId,
          'email_code': _items[index].code,
          'enabled': newVal,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'merchant_id,email_code',
      );
    } catch (_) {
      // 写入失败时回滚
      if (mounted) setState(() => _items[index].enabled = oldVal);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Email Notifications'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Failed to load preferences'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'No configurable email preferences',
          style: TextStyle(color: Color(0xFF6B7280), fontSize: 15),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 说明文案
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            "Choose which email notifications you'd like to receive. "
            'Changes are saved automatically.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
        ),

        // 开关卡片
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
              for (int i = 0; i < _items.length; i++)
                _buildSwitchTile(i, isLast: i == _items.length - 1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile(int index, {required bool isLast}) {
    final item = _items[index];
    final isEnabled = item.enabled;

    IconData iconFor(String code) {
      switch (code) {
        case 'M5':
          return Icons.receipt_long_outlined;
        case 'M6':
          return Icons.event_outlined;
        case 'M7':
          return Icons.qr_code_scanner_outlined;
        case 'M13':
          return Icons.summarize_outlined;
        default:
          return Icons.mail_outline;
      }
    }

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
                  iconFor(item.code),
                  size: 20,
                  color: isEnabled
                      ? const Color(0xFFFF6B35)
                      : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),

              // 文案
              Expanded(
                child: Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isEnabled
                        ? const Color(0xFF1A1A1A)
                        : Colors.grey,
                  ),
                ),
              ),

              // Switch
              Switch.adaptive(
                value: isEnabled,
                activeThumbColor: Colors.white,
                activeTrackColor: const Color(0xFFFF6B35),
                onChanged: (val) => _toggle(index, val),
              ),
            ],
          ),
        ),
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
