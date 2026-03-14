// 集成测试配置常量
// 包含 Supabase 连接信息和测试商家账号信息

class TestConfig {
  // ── Supabase 连接 ──────────────────────────────────────────
  static const supabaseUrl = 'https://kqyolvmgrdekybjrwizx.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxeW9sdm1ncmRla3lianJ3aXp4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIzMTk2NTksImV4cCI6MjA4Nzg5NTY1OX0.1edjpxO5lT191vv2tjVc25EcXHf6cEJkc0lL4QyXV8k';
  static const serviceRoleKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxeW9sdm1ncmRla3lianJ3aXp4Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjMxOTY1OSwiZXhwIjoyMDg3ODk1NjU5fQ.tkYSikgL9UenIw_MUhxbh73MSKA0tcTMQNJX08eaGNA';

  // ── 测试商家账号 ──────────────────────────────────────────
  static const merchantEmail = 'test_merchant@dealjoy.test';
  static const merchantPassword = 'TestPass123';

  // ── 测试商家 ID（auth uid 和 merchants 表主键）──────────
  static const merchantUid = 'c2c2f2f8-fed0-405a-9640-b10588e1ad47';
  static const merchantId = 'f21929c3-bbe0-4b95-a7be-e292f6e0ee32';

  // ── 等待超时配置（毫秒）─────────────────────────────────
  /// App 启动 + Supabase 初始化等待时间
  static const Duration appLaunchTimeout = Duration(seconds: 8);

  /// 路由跳转等待时间（async redirect 需要查数据库）
  static const Duration routeRedirectTimeout = Duration(seconds: 10);

  /// API 请求等待时间
  static const Duration apiTimeout = Duration(seconds: 15);
}
