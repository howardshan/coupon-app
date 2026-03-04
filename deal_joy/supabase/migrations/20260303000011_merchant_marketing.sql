-- ============================================================
-- Migration: 20260303000011_merchant_marketing.sql
-- 模块: 11. 营销工具（Marketing Tools）
-- 优先级: P2/V2 — 创建表结构，业务逻辑在 V2 实现
-- 包含: flash_deals / new_customer_offers / promotions 三张表
-- ============================================================

-- ============================================================
-- 1. flash_deals — 限时折扣表
-- 商家为指定 Deal 设置限时额外折扣
-- V2 TODO: 使用 pg_cron 定时任务自动将过期活动 is_active 置 false
-- ============================================================
CREATE TABLE IF NOT EXISTS flash_deals (
    id                  uuid            PRIMARY KEY DEFAULT gen_random_uuid(),
    deal_id             uuid            NOT NULL REFERENCES deals(id) ON DELETE CASCADE,
    merchant_id         uuid            NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    -- 额外折扣百分比，例如 10 表示再减 10%
    discount_percentage numeric(5, 2)   NOT NULL CHECK (discount_percentage > 0 AND discount_percentage < 100),
    start_time          timestamptz     NOT NULL,
    end_time            timestamptz     NOT NULL,
    -- 是否生效：过期时由 pg_cron (V2) 自动置 false
    is_active           boolean         NOT NULL DEFAULT true,
    created_at          timestamptz     NOT NULL DEFAULT now(),
    updated_at          timestamptz     NOT NULL DEFAULT now(),

    -- 约束：结束时间必须晚于开始时间
    CONSTRAINT flash_deals_time_order CHECK (end_time > start_time)
);

-- 索引
CREATE INDEX idx_flash_deals_merchant_id ON flash_deals (merchant_id);
CREATE INDEX idx_flash_deals_deal_id     ON flash_deals (deal_id);
-- 查询有效中的活动（用户端首页 Flash Deals 专区）
CREATE INDEX idx_flash_deals_active_end  ON flash_deals (end_time) WHERE is_active = true;

-- 唯一约束：同一 Deal 同时只能有一个有效的闪购活动
-- V2 NOTE: 如需支持预排期，改为时间段不重叠约束（用 exclusion constraint + btree_gist）
CREATE UNIQUE INDEX idx_flash_deals_unique_active_per_deal
    ON flash_deals (deal_id)
    WHERE is_active = true;

-- updated_at 自动更新触发器
CREATE OR REPLACE FUNCTION update_flash_deals_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_flash_deals_updated_at
    BEFORE UPDATE ON flash_deals
    FOR EACH ROW EXECUTE FUNCTION update_flash_deals_updated_at();

-- ============================================================
-- 2. new_customer_offers — 新客特惠表
-- 为指定 Deal 设置仅新用户可见/购买的特别价格
-- V2 TODO: 在 CheckoutRepository 中校验用户是否为新客
-- ============================================================
CREATE TABLE IF NOT EXISTS new_customer_offers (
    id            uuid            PRIMARY KEY DEFAULT gen_random_uuid(),
    deal_id       uuid            NOT NULL REFERENCES deals(id) ON DELETE CASCADE,
    merchant_id   uuid            NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    -- 新客特惠价格（USD），必须 > 0
    special_price numeric(10, 2)  NOT NULL CHECK (special_price > 0),
    -- 是否启用
    is_active     boolean         NOT NULL DEFAULT true,
    created_at    timestamptz     NOT NULL DEFAULT now(),
    updated_at    timestamptz     NOT NULL DEFAULT now()
);

-- 索引
CREATE INDEX idx_new_customer_offers_merchant_id ON new_customer_offers (merchant_id);
CREATE INDEX idx_new_customer_offers_deal_id     ON new_customer_offers (deal_id);

-- 唯一约束：每个 Deal 只能有一个有效的新客特惠
CREATE UNIQUE INDEX idx_new_customer_offers_unique_active_per_deal
    ON new_customer_offers (deal_id)
    WHERE is_active = true;

-- updated_at 自动更新触发器
CREATE OR REPLACE FUNCTION update_new_customer_offers_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_new_customer_offers_updated_at
    BEFORE UPDATE ON new_customer_offers
    FOR EACH ROW EXECUTE FUNCTION update_new_customer_offers_updated_at();

-- ============================================================
-- 3. promotions — 满减活动表
-- 满 X 减 Y 活动，支持绑定特定 Deal 或全店通用
-- V2 TODO: 在结账流程中自动计算并应用满减优惠
-- ============================================================
CREATE TABLE IF NOT EXISTS promotions (
    id               uuid            PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id      uuid            NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    -- 关联特定 Deal，NULL 表示全店通用
    deal_id          uuid            REFERENCES deals(id) ON DELETE SET NULL,
    -- 活动类型，当前仅支持 spend_x_get_y，预留扩展（如 buy_x_get_y, free_item 等）
    promo_type       text            NOT NULL DEFAULT 'spend_x_get_y'
                                     CHECK (promo_type IN ('spend_x_get_y')),
    -- 最低消费金额（USD）
    min_spend        numeric(10, 2)  NOT NULL CHECK (min_spend > 0),
    -- 满足条件后减免金额（USD）
    discount_amount  numeric(10, 2)  NOT NULL CHECK (discount_amount > 0),
    -- 约束：减免金额必须小于最低消费金额（不能减完）
    CONSTRAINT promotions_discount_lt_min_spend CHECK (discount_amount < min_spend),
    -- 是否启用
    is_active        boolean         NOT NULL DEFAULT true,
    -- 活动有效期（NULL 表示无限制）
    start_time       timestamptz,
    end_time         timestamptz,
    -- 展示信息
    title            text,           -- 如 "Spend $30 Get $5 Off"
    description      text,           -- 活动详细说明
    -- V2 预留：使用次数限制
    usage_limit      integer,        -- NULL 表示不限次数
    per_user_limit   integer,        -- NULL 表示每用户不限
    created_at       timestamptz     NOT NULL DEFAULT now(),
    updated_at       timestamptz     NOT NULL DEFAULT now()
);

-- 索引
CREATE INDEX idx_promotions_merchant_id ON promotions (merchant_id);
CREATE INDEX idx_promotions_deal_id     ON promotions (deal_id) WHERE deal_id IS NOT NULL;
-- 查询有效中的活动
CREATE INDEX idx_promotions_active      ON promotions (is_active, end_time);

-- updated_at 自动更新触发器
CREATE OR REPLACE FUNCTION update_promotions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_promotions_updated_at
    BEFORE UPDATE ON promotions
    FOR EACH ROW EXECUTE FUNCTION update_promotions_updated_at();

-- ============================================================
-- RLS（行级安全策略）
-- ============================================================

-- ---- flash_deals RLS ----
ALTER TABLE flash_deals ENABLE ROW LEVEL SECURITY;

-- 商家只能管理自己的闪购活动
CREATE POLICY merchants_manage_own_flash_deals
    ON flash_deals
    FOR ALL
    USING (
        merchant_id IN (
            SELECT id FROM merchants WHERE user_id = auth.uid()
        )
    )
    WITH CHECK (
        merchant_id IN (
            SELECT id FROM merchants WHERE user_id = auth.uid()
        )
    );

-- 所有已登录用户可读取有效中的闪购活动（用于用户端首页 Flash Deals 展示）
CREATE POLICY authenticated_read_active_flash_deals
    ON flash_deals
    FOR SELECT
    TO authenticated
    USING (
        is_active = true
        AND now() BETWEEN start_time AND end_time
    );

-- ---- new_customer_offers RLS ----
ALTER TABLE new_customer_offers ENABLE ROW LEVEL SECURITY;

-- 商家只能管理自己的新客特惠
CREATE POLICY merchants_manage_own_new_customer_offers
    ON new_customer_offers
    FOR ALL
    USING (
        merchant_id IN (
            SELECT id FROM merchants WHERE user_id = auth.uid()
        )
    )
    WITH CHECK (
        merchant_id IN (
            SELECT id FROM merchants WHERE user_id = auth.uid()
        )
    );

-- 已登录用户可读取所有有效的新客特惠（应用层判断是否展示）
CREATE POLICY authenticated_read_active_new_customer_offers
    ON new_customer_offers
    FOR SELECT
    TO authenticated
    USING (is_active = true);

-- ---- promotions RLS ----
ALTER TABLE promotions ENABLE ROW LEVEL SECURITY;

-- 商家只能管理自己的满减活动
CREATE POLICY merchants_manage_own_promotions
    ON promotions
    FOR ALL
    USING (
        merchant_id IN (
            SELECT id FROM merchants WHERE user_id = auth.uid()
        )
    )
    WITH CHECK (
        merchant_id IN (
            SELECT id FROM merchants WHERE user_id = auth.uid()
        )
    );

-- 已登录用户可读取有效中的满减活动
CREATE POLICY authenticated_read_active_promotions
    ON promotions
    FOR SELECT
    TO authenticated
    USING (
        is_active = true
        AND (end_time IS NULL OR end_time > now())
        AND (start_time IS NULL OR start_time <= now())
    );

-- ============================================================
-- V2 TODO: pg_cron 自动结束过期活动
-- 以下 SQL 在 V2 实现时执行（需在 Supabase Dashboard 启用 pg_cron 扩展）
-- ============================================================
-- -- 每分钟检查并关闭已过期的闪购活动
-- SELECT cron.schedule(
--     'expire-flash-deals',
--     '* * * * *',   -- 每分钟执行
--     $$
--         UPDATE flash_deals
--         SET is_active = false, updated_at = now()
--         WHERE is_active = true AND end_time < now();
--     $$
-- );
--
-- -- 每分钟检查并关闭已过期的满减活动
-- SELECT cron.schedule(
--     'expire-promotions',
--     '* * * * *',   -- 每分钟执行
--     $$
--         UPDATE promotions
--         SET is_active = false, updated_at = now()
--         WHERE is_active = true AND end_time IS NOT NULL AND end_time < now();
--     $$
-- );
-- ============================================================
