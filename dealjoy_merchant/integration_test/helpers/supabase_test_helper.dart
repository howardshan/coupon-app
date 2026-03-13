// Supabase 测试辅助类
// 封装管理操作，通过 Service Role Key 直接调用 Supabase REST API
// 用于集成测试中创建/修改/清理测试数据

import 'dart:convert';
import 'dart:io';

import 'test_config.dart';

/// Supabase 集成测试辅助工具
/// 使用 Service Role Key 绕过 RLS，直接操作数据库
class SupabaseTestHelper {
  // REST API 基础 URL
  static const _restBase = '${TestConfig.supabaseUrl}/rest/v1';
  // Auth API 基础 URL
  static const _authBase = '${TestConfig.supabaseUrl}/auth/v1';

  // 标准请求头（Anon Key，用于登录）
  static Map<String, String> get _anonHeaders => {
        'Content-Type': 'application/json',
        'apikey': TestConfig.supabaseAnonKey,
        'Authorization': 'Bearer ${TestConfig.supabaseAnonKey}',
      };

  // 管理员请求头（Service Role Key，绕过 RLS）
  static Map<String, String> get _serviceHeaders => {
        'Content-Type': 'application/json',
        'apikey': TestConfig.serviceRoleKey,
        'Authorization': 'Bearer ${TestConfig.serviceRoleKey}',
        'Prefer': 'return=representation',
      };

  // 存储当前登录的 access_token
  static String? _accessToken;

  // ──────────────────────────────────────────────────────────
  // 认证操作
  // ──────────────────────────────────────────────────────────

  /// 使用测试商家账号登录，返回 access_token
  static Future<String> signInAsMerchant() async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_authBase/token?grant_type=password');
      final req = await client.postUrl(uri);
      _anonHeaders.forEach((k, v) => req.headers.set(k, v));
      req.write(jsonEncode({
        'email': TestConfig.merchantEmail,
        'password': TestConfig.merchantPassword,
      }));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        throw Exception('Login failed (${res.statusCode}): $body');
      }
      _accessToken = data['access_token'] as String;
      return _accessToken!;
    } finally {
      client.close();
    }
  }

  /// 退出当前会话
  static Future<void> signOut() async {
    if (_accessToken == null) return;
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_authBase/logout');
      final req = await client.postUrl(uri);
      req.headers.set('apikey', TestConfig.supabaseAnonKey);
      req.headers.set('Authorization', 'Bearer $_accessToken');
      await req.close();
      _accessToken = null;
    } catch (_) {
      _accessToken = null;
    } finally {
      client.close();
    }
  }

  // ──────────────────────────────────────────────────────────
  // 商家状态操作（使用 Service Role Key 绕过 RLS）
  // ──────────────────────────────────────────────────────────

  /// 修改 merchants 表中指定商家的 status 字段
  /// [status]: 'pending' | 'approved' | 'rejected'
  static Future<void> setMerchantStatus(
    String merchantId,
    String status,
  ) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(
        '$_restBase/merchants?id=eq.$merchantId',
      );
      final req = await client.patchUrl(uri);
      _serviceHeaders.forEach((k, v) => req.headers.set(k, v));
      req.write(jsonEncode({'status': status}));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(
          'setMerchantStatus failed (${res.statusCode}): $body',
        );
      }
    } finally {
      client.close();
    }
  }

  /// 查询 merchants 表中指定商家的当前数据
  /// 返回完整行数据，方便断言
  static Future<Map<String, dynamic>> queryMerchant(
    String merchantId,
  ) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(
        '$_restBase/merchants?id=eq.$merchantId&select=*',
      );
      final req = await client.getUrl(uri);
      _serviceHeaders.forEach((k, v) => req.headers.set(k, v));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('queryMerchant failed (${res.statusCode}): $body');
      }
      final list = jsonDecode(body) as List<dynamic>;
      if (list.isEmpty) {
        throw Exception('Merchant $merchantId not found');
      }
      return list.first as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  // ──────────────────────────────────────────────────────────
  // 测试 Deal 操作
  // ──────────────────────────────────────────────────────────

  /// 创建一条最简单的测试 Deal（返回新建的 deal id）
  static Future<String> createTestDeal(String merchantId) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_restBase/deals');
      final req = await client.postUrl(uri);
      _serviceHeaders.forEach((k, v) => req.headers.set(k, v));
      req.write(jsonEncode({
        'merchant_id': merchantId,
        'title': 'Integration Test Deal',
        'description': 'Auto-created by integration test',
        'original_price': 100.0,
        'deal_price': 50.0,
        'status': 'active',
        'max_quantity': 10,
        'sold_count': 0,
        'valid_from': DateTime.now().toIso8601String(),
        'valid_until':
            DateTime.now().add(const Duration(days: 30)).toIso8601String(),
      }));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('createTestDeal failed (${res.statusCode}): $body');
      }
      final list = jsonDecode(body) as List<dynamic>;
      return (list.first as Map<String, dynamic>)['id'] as String;
    } finally {
      client.close();
    }
  }

  /// 删除测试 Deal（按 id）
  static Future<void> deleteTestDeal(String dealId) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_restBase/deals?id=eq.$dealId');
      final req = await client.deleteUrl(uri);
      _serviceHeaders.forEach((k, v) => req.headers.set(k, v));
      final res = await req.close();
      await res.drain<void>(); // 忽略响应体
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('deleteTestDeal failed (${res.statusCode})');
      }
    } finally {
      client.close();
    }
  }

  // ──────────────────────────────────────────────────────────
  // 清理操作
  // ──────────────────────────────────────────────────────────

  /// 清理当次测试产生的测试数据（删除标题含 "Integration Test" 的 deals）
  static Future<void> cleanupTestData() async {
    final client = HttpClient();
    try {
      // 删除所有标题含 "Integration Test" 的 deals
      final uri = Uri.parse(
        '$_restBase/deals?merchant_id=eq.${TestConfig.merchantId}'
        '&title=like.*Integration Test*',
      );
      final req = await client.deleteUrl(uri);
      _serviceHeaders.forEach((k, v) => req.headers.set(k, v));
      final res = await req.close();
      await res.drain<void>();
    } catch (_) {
      // 清理失败不影响测试结论，仅打印日志
      // ignore: avoid_print
      print('[SupabaseTestHelper] cleanupTestData error, ignored');
    } finally {
      client.close();
    }
  }

  /// 确保测试后将商家状态恢复为 approved
  static Future<void> restoreMerchantToApproved() async {
    await setMerchantStatus(TestConfig.merchantId, 'approved');
  }
}
