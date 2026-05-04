-- 修复 Supabase linter 检测到的 Security Definer View 和 RLS Disabled 安全问题
-- 为视图启用 security_invoker = true，使其遵守调用用户的 RLS 策略
ALTER VIEW public.view_merchant_after_sales_requests SET (security_invoker = true);
ALTER VIEW public.view_user_after_sales_requests   SET (security_invoker = true);
ALTER VIEW public.merchant_order_view              SET (security_invoker = true);
ALTER VIEW public.v_earnings_by_store              SET (security_invoker = true);
ALTER VIEW public.brand_review_summary             SET (security_invoker = true);

-- merchant_staff_managers 故意保留 security_invoker = false（防 merchant_staff RLS 自引用递归）
-- 撤销外部角色直接访问，该视图仅供 RLS 策略内部（postgres 权限）使用
REVOKE SELECT ON public.merchant_staff_managers FROM authenticated, anon;

-- 为 announcements 表启用 RLS
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

-- 已认证用户仅可读取已发布的公告
CREATE POLICY "announcements_select" ON public.announcements
  FOR SELECT TO authenticated
  USING (published_at IS NOT NULL AND published_at <= now());
