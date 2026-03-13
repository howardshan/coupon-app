/// 集成测试配置常量
/// 包含 Supabase 连接信息、测试账号凭据、测试商家 ID 等
class TestConfig {
  // ---- Supabase 项目配置 ----
  static const supabaseUrl = 'https://kqyolvmgrdekybjrwizx.supabase.co';

  /// Anon Key：客户端公开密钥，受 RLS 约束
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxeW9sdm1ncmRla3lianJ3aXp4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIzMTk2NTksImV4cCI6MjA4Nzg5NTY1OX0.1edjpxO5lT191vv2tjVc25EcXHf6cEJkc0lL4QyXV8k';

  /// Service Role Key：绕过 RLS，仅在测试辅助操作中使用（模拟后台管理员操作）
  static const serviceRoleKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxeW9sdm1ncmRla3lianJ3aXp4Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjMxOTY1OSwiZXhwIjoyMDg3ODk1NjU5fQ.tkYSikgL9UenIw_MUhxbh73MSKA0tcTMQNJX08eaGNA';

  // ---- 测试客户账号 ----
  static const customerEmail = 'test_customer@dealjoy.test';
  static const customerPassword = 'TestPass123';

  // ---- 测试商家信息 ----
  /// 商家 auth.users.id（用于 Edge Function 鉴权）
  static const merchantUid = 'c2c2f2f8-fed0-405a-9640-b10588e1ad47';

  /// 商家在 merchants 表中的主键 ID
  static const merchantId = 'f21929c3-bbe0-4b95-a7be-e292f6e0ee32';

  // ---- Edge Functions 路径 ----
  static const functionsMerchantScan = 'merchant-scan';
  static const functionsMerchantOrders = 'merchant-orders';
  static const functionsCreatePaymentIntent = 'create-payment-intent';
  static const functionsCreateRefund = 'create-refund';

  // ---- 超时配置（毫秒） ----
  /// App 启动等待时间，包含 Supabase 初始化 + 路由跳转
  static const appLaunchTimeout = Duration(seconds: 8);

  /// 路由跳转等待时间
  static const routeTransitionTimeout = Duration(seconds: 3);

  /// 网络请求等待时间
  static const networkTimeout = Duration(seconds: 10);
}
