-- ============================================================
-- Deal 使用规则 + 限购字段
-- usage_rules: 商家自定义使用规则文案（text 数组）
-- max_per_account: 每个账户最多购买张数（-1=无限制）
-- ============================================================

ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS usage_rules text[] DEFAULT ARRAY['1 deal per table per visit', 'Cannot be combined with other offers'],
  ADD COLUMN IF NOT EXISTS max_per_account int NOT NULL DEFAULT -1;

COMMENT ON COLUMN public.deals.usage_rules IS '使用规则文案数组，展示在 Deal 详情页 Purchase Notes 区域';
COMMENT ON COLUMN public.deals.max_per_account IS '每账户限购数量，-1 表示无限制';
