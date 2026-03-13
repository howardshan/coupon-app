import 'dart:convert';
import 'dart:io';
import 'test_config.dart';

/// Supabase 测试辅助类
/// 通过 REST API 直接操作 Supabase，绕过 App UI，用于测试前置条件的准备和结果验证
/// 使用 Service Role Key 绕过 RLS，模拟后台管理员操作
class SupabaseTestHelper {
  // ---- HTTP 客户端 ----
  final _client = HttpClient();

  // ---- 认证相关 ----

  /// 用测试客户账号登录，返回 access_token
  /// 用途：获取客户端 JWT，供后续需要用户身份的请求使用
  Future<String?> signInAsCustomer() async {
    final uri = Uri.parse(
      '${TestConfig.supabaseUrl}/auth/v1/token?grant_type=password',
    );
    final request = await _client.postUrl(uri);
    _setJsonHeaders(request, useServiceRole: false);
    request.write(jsonEncode({
      'email': TestConfig.customerEmail,
      'password': TestConfig.customerPassword,
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['access_token'] as String?;
  }

  /// 退出登录（使 token 失效）
  /// 参数 [accessToken] 是当前登录用户的 access_token
  Future<void> signOut(String accessToken) async {
    final uri = Uri.parse('${TestConfig.supabaseUrl}/auth/v1/logout');
    final request = await _client.postUrl(uri);
    _setJsonHeaders(request, useServiceRole: false);
    request.headers.set('Authorization', 'Bearer $accessToken');
    await (await request.close()).drain();
  }

  // ---- 商家管理操作（模拟后台审核） ----

  /// 审核通过商家
  /// [merchantId] 对应 merchants 表主键
  Future<void> approveMerchant(String merchantId) async {
    await _updateTable(
      table: 'merchants',
      id: merchantId,
      data: {'status': 'approved'},
    );
  }

  /// 审核拒绝商家
  /// [merchantId] 对应 merchants 表主键，[reason] 拒绝原因
  Future<void> rejectMerchant(String merchantId, String reason) async {
    await _updateTable(
      table: 'merchants',
      id: merchantId,
      data: {'status': 'rejected', 'rejection_reason': reason},
    );
  }

  // ---- Deal 管理 ----

  /// 激活 Deal（模拟后台审核通过）
  /// [dealId] 对应 deals 表主键
  Future<void> activateDeal(String dealId) async {
    await _updateTable(
      table: 'deals',
      id: dealId,
      data: {'status': 'active'},
    );
  }

  // ---- 订单和核销 ----

  /// 查询订单状态
  /// 返回 orders 表中 [orderId] 对应的完整行数据
  Future<Map<String, dynamic>?> queryOrder(String orderId) async {
    final result = await _queryTable(table: 'orders', id: orderId);
    return result;
  }

  /// 查询商家信息
  /// 返回 merchants 表中 [merchantId] 对应的完整行数据
  Future<Map<String, dynamic>?> queryMerchant(String merchantId) async {
    final result = await _queryTable(table: 'merchants', id: merchantId);
    return result;
  }

  /// 模拟商家扫码核销
  /// 调用 merchant-scan Edge Function，传入 couponCode
  /// 返回 Edge Function 的响应体
  Future<Map<String, dynamic>> scanCoupon(String couponCode) async {
    final uri = Uri.parse(
      '${TestConfig.supabaseUrl}/functions/v1/${TestConfig.functionsMerchantScan}',
    );
    final request = await _client.postUrl(uri);
    _setJsonHeaders(request, useServiceRole: true);
    request.write(jsonEncode({'coupon_code': couponCode}));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// 模拟后台批准退款
  /// 直接更新 orders 表状态为 refunded
  Future<void> approveRefund(String orderId) async {
    await _updateTable(
      table: 'orders',
      id: orderId,
      data: {'status': 'refunded', 'refunded_at': DateTime.now().toIso8601String()},
    );
  }

  // ---- 测试数据准备 ----

  /// 直接在 orders 表创建测试订单（绕过 Stripe 支付流程）
  /// 返回新创建的订单 ID
  Future<String?> createTestOrder({
    required String userId,
    required String dealId,
    required String merchantId,
    double totalAmount = 9.99,
  }) async {
    final uri = Uri.parse('${TestConfig.supabaseUrl}/rest/v1/orders');
    final request = await _client.postUrl(uri);
    _setJsonHeaders(request, useServiceRole: true);
    // 返回插入后的完整行
    request.headers.set('Prefer', 'return=representation');
    request.write(jsonEncode({
      'user_id': userId,
      'deal_id': dealId,
      'merchant_id': merchantId,
      'total_amount': totalAmount,
      'status': 'unused',
      'payment_status': 'paid',
      'created_at': DateTime.now().toIso8601String(),
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final list = jsonDecode(body) as List<dynamic>;
    if (list.isEmpty) return null;
    return (list.first as Map<String, dynamic>)['id'] as String?;
  }

  /// 直接在 coupons 表创建测试优惠券
  /// 返回新创建的 coupon code
  Future<String?> createTestCoupon({
    required String orderId,
    required String userId,
    required String dealId,
    required String merchantId,
  }) async {
    final couponCode = 'TEST-${DateTime.now().millisecondsSinceEpoch}';
    final uri = Uri.parse('${TestConfig.supabaseUrl}/rest/v1/coupons');
    final request = await _client.postUrl(uri);
    _setJsonHeaders(request, useServiceRole: true);
    request.headers.set('Prefer', 'return=representation');
    request.write(jsonEncode({
      'order_id': orderId,
      'user_id': userId,
      'deal_id': dealId,
      'merchant_id': merchantId,
      'coupon_code': couponCode,
      'status': 'active',
      'created_at': DateTime.now().toIso8601String(),
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final list = jsonDecode(body) as List<dynamic>;
    if (list.isEmpty) return null;
    return (list.first as Map<String, dynamic>)['coupon_code'] as String?;
  }

  /// 根据 coupon_code 查询优惠券信息
  Future<Map<String, dynamic>?> queryCouponByCode(String couponCode) async {
    final uri = Uri.parse(
      '${TestConfig.supabaseUrl}/rest/v1/coupons?coupon_code=eq.$couponCode',
    );
    final request = await _client.getUrl(uri);
    _setJsonHeaders(request, useServiceRole: true);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final list = jsonDecode(body) as List<dynamic>;
    if (list.isEmpty) return null;
    return list.first as Map<String, dynamic>;
  }

  /// 获取当前登录用户的 user_id（通过 access_token 查询 auth.users）
  Future<String?> getUserId(String accessToken) async {
    final uri = Uri.parse('${TestConfig.supabaseUrl}/auth/v1/user');
    final request = await _client.getUrl(uri);
    _setJsonHeaders(request, useServiceRole: false);
    request.headers.set('Authorization', 'Bearer $accessToken');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['id'] as String?;
  }

  /// 获取 deals 表第一条 active 状态的 Deal（用于测试购买流程）
  Future<Map<String, dynamic>?> getFirstActiveDeal() async {
    final uri = Uri.parse(
      '${TestConfig.supabaseUrl}/rest/v1/deals?status=eq.active&limit=1',
    );
    final request = await _client.getUrl(uri);
    _setJsonHeaders(request, useServiceRole: true);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final list = jsonDecode(body) as List<dynamic>;
    if (list.isEmpty) return null;
    return list.first as Map<String, dynamic>;
  }

  // ---- 清理测试数据 ----

  /// 删除测试订单（清理 orders 表中的测试数据）
  Future<void> deleteTestOrder(String orderId) async {
    final uri = Uri.parse(
      '${TestConfig.supabaseUrl}/rest/v1/orders?id=eq.$orderId',
    );
    final request = await _client.deleteUrl(uri);
    _setJsonHeaders(request, useServiceRole: true);
    await (await request.close()).drain();
  }

  /// 删除测试优惠券（清理 coupons 表中的测试数据）
  Future<void> deleteTestCoupon(String couponCode) async {
    final uri = Uri.parse(
      '${TestConfig.supabaseUrl}/rest/v1/coupons?coupon_code=eq.$couponCode',
    );
    final request = await _client.deleteUrl(uri);
    _setJsonHeaders(request, useServiceRole: true);
    await (await request.close()).drain();
  }

  // ---- 私有辅助方法 ----

  /// 通用 PATCH 更新单行数据
  Future<void> _updateTable({
    required String table,
    required String id,
    required Map<String, dynamic> data,
  }) async {
    final uri = Uri.parse(
      '${TestConfig.supabaseUrl}/rest/v1/$table?id=eq.$id',
    );
    final request = await _client.openUrl('PATCH', uri);
    _setJsonHeaders(request, useServiceRole: true);
    request.write(jsonEncode(data));
    await (await request.close()).drain();
  }

  /// 通用 GET 查询单行数据
  Future<Map<String, dynamic>?> _queryTable({
    required String table,
    required String id,
  }) async {
    final uri = Uri.parse(
      '${TestConfig.supabaseUrl}/rest/v1/$table?id=eq.$id',
    );
    final request = await _client.getUrl(uri);
    _setJsonHeaders(request, useServiceRole: true);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final list = jsonDecode(body) as List<dynamic>;
    if (list.isEmpty) return null;
    return list.first as Map<String, dynamic>;
  }

  /// 设置通用请求头
  /// [useServiceRole] 为 true 时使用 Service Role Key（绕过 RLS），否则使用 Anon Key
  void _setJsonHeaders(HttpClientRequest request, {required bool useServiceRole}) {
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('apikey', TestConfig.supabaseAnonKey);
    if (useServiceRole) {
      request.headers.set('Authorization', 'Bearer ${TestConfig.serviceRoleKey}');
      request.headers.set('apikey', TestConfig.serviceRoleKey);
    }
  }

  /// 直接将订单标记为 used 状态（模拟扫码核销结果，绕过 merchant-scan Edge Function）
  /// 用于 X006-C 测试中准备已核销数据
  Future<void> updateOrderToUsed(String orderId) async {
    await _updateTable(
      table: 'orders',
      id: orderId,
      data: {
        'status': 'used',
        'used_at': DateTime.now().toIso8601String(),
      },
    );
  }

  /// 关闭 HTTP 客户端，释放资源
  void dispose() {
    _client.close();
  }
}
