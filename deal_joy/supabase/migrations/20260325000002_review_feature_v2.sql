-- ============================================================
-- Review 功能升级 v2
-- 新增：review_hashtags 表、reviews 多维评分字段、
--       merchants 持久化评分字段、merchant 级别评分触发器
-- 全部语句保持幂等，可重复执行
-- ============================================================

-- ============================================================
-- Step 1: review_hashtags 表 + 预置数据
-- ============================================================
CREATE TABLE IF NOT EXISTS review_hashtags (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tag        text NOT NULL UNIQUE,
  category   text CHECK (category IN ('positive', 'negative')),
  sort_order int NOT NULL DEFAULT 0,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 预置标签，ON CONFLICT 保证幂等
INSERT INTO review_hashtags (tag, category, sort_order) VALUES
  ('#GreatValue',        'positive', 1),
  ('#MustTry',           'positive', 2),
  ('#FriendlyStaff',     'positive', 3),
  ('#CleanSpace',        'positive', 4),
  ('#QuickService',      'positive', 5),
  ('#TastyFood',         'positive', 6),
  ('#NiceAmbience',      'positive', 7),
  ('#GoodPortion',       'positive', 8),
  ('#WouldReturn',       'positive', 9),
  ('#PerfectForDates',   'positive', 10),
  ('#FamilyFriendly',    'positive', 11),
  ('#HiddenGem',         'positive', 12),
  ('#SlowService',       'negative', 13),
  ('#SmallPortion',      'negative', 14),
  ('#Overpriced',        'negative', 15),
  ('#NoisyEnvironment',  'negative', 16),
  ('#NeedsImprovement',  'negative', 17),
  ('#LongWait',          'negative', 18),
  ('#DisappointingFood', 'negative', 19)
ON CONFLICT (tag) DO NOTHING;

-- RLS：所有人可读，仅管理员写（通过 service_role 操作）
ALTER TABLE review_hashtags ENABLE ROW LEVEL SECURITY;

CREATE POLICY "review_hashtags_public_read" ON review_hashtags
  FOR SELECT USING (true);

-- ============================================================
-- Step 2: reviews 表升级 — 新增字段（保留旧字段兼容）
-- ============================================================

-- 关联 order_item（1:1，旧数据 order_item_id 为 NULL 故不加 UNIQUE）
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS order_item_id uuid REFERENCES order_items(id) ON DELETE CASCADE;

-- 直接挂 merchant（store 级别，方便按商家聚合）
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS merchant_id uuid REFERENCES merchants(id);

-- 实际评价人（受赠方场景：购买者 ≠ 核销/评价者）
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS reviewer_user_id uuid REFERENCES users(id);

-- 5 维度评分（旧 rating 字段保留作为 overall 的向后兼容映射）
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS rating_overall      smallint CHECK (rating_overall      BETWEEN 1 AND 5);
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS rating_environment  smallint CHECK (rating_environment  BETWEEN 1 AND 5);
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS rating_hygiene      smallint CHECK (rating_hygiene      BETWEEN 1 AND 5);
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS rating_service      smallint CHECK (rating_service      BETWEEN 1 AND 5);
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS rating_product      smallint CHECK (rating_product      BETWEEN 1 AND 5);

-- Hashtag ID 数组 + 媒体 URL 数组（替代旧 review_photos 表，但 review_photos 保留）
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS hashtag_ids uuid[] NOT NULL DEFAULT '{}';
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS media_urls  text[] NOT NULL DEFAULT '{}';

-- 商家回复者（记录是哪位 staff 回复的）
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS merchant_replied_by uuid;

-- 软删除（Admin / 商家申诉后由 Admin 操作）
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS is_deleted boolean    NOT NULL DEFAULT false;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS deleted_by uuid;

-- updated_at（旧表没有此字段）
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- 回填旧数据：rating → rating_overall
UPDATE reviews SET rating_overall = rating WHERE rating_overall IS NULL;

-- 回填旧数据：user_id → reviewer_user_id
UPDATE reviews SET reviewer_user_id = user_id WHERE reviewer_user_id IS NULL;

-- 回填旧数据：通过 deal_id → deals.merchant_id 推导 merchant_id
UPDATE reviews r
  SET merchant_id = d.merchant_id
  FROM deals d
  WHERE r.deal_id = d.id
    AND r.merchant_id IS NULL;

-- updated_at 自动维护触发器（函数 update_updated_at_column 已存在）
DO $$ BEGIN
  CREATE TRIGGER set_reviews_updated_at
    BEFORE UPDATE ON reviews
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 新索引（按 merchant 维度查询、软删除过滤、hashtag GIN 搜索）
CREATE INDEX IF NOT EXISTS idx_reviews_merchant_id       ON reviews(merchant_id)      WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_reviews_order_item_id     ON reviews(order_item_id);
CREATE INDEX IF NOT EXISTS idx_reviews_reviewer_user_id  ON reviews(reviewer_user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_rating_overall    ON reviews(rating_overall)   WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_reviews_is_deleted        ON reviews(is_deleted);
CREATE INDEX IF NOT EXISTS idx_reviews_hashtag_ids       ON reviews USING GIN(hashtag_ids) WHERE is_deleted = false;

-- ============================================================
-- Step 3: merchants 表新增持久化评分字段
-- ============================================================
ALTER TABLE merchants
  ADD COLUMN IF NOT EXISTS avg_rating   numeric(3,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS review_count int          NOT NULL DEFAULT 0;

-- 回填已有数据（avg_rating / review_count）
UPDATE merchants m
  SET
    avg_rating   = COALESCE(sub.avg_r, 0),
    review_count = COALESCE(sub.cnt, 0)
  FROM (
    SELECT
      merchant_id,
      ROUND(AVG(COALESCE(rating_overall, rating))::numeric, 2) AS avg_r,
      COUNT(*) AS cnt
    FROM reviews
    WHERE is_deleted = false
      AND merchant_id IS NOT NULL
    GROUP BY merchant_id
  ) sub
  WHERE m.id = sub.merchant_id;

-- ============================================================
-- Step 4: avg_rating 自动维护触发器（merchant 级别）
-- ============================================================
CREATE OR REPLACE FUNCTION update_merchant_rating()
RETURNS TRIGGER AS $$
DECLARE
  v_merchant_id uuid;
BEGIN
  -- INSERT 时用 NEW，DELETE 时用 OLD，UPDATE 两者都有
  v_merchant_id := COALESCE(NEW.merchant_id, OLD.merchant_id);
  IF v_merchant_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  UPDATE merchants
  SET
    avg_rating = COALESCE(
      (
        SELECT ROUND(AVG(COALESCE(rating_overall, rating))::numeric, 2)
        FROM reviews
        WHERE merchant_id = v_merchant_id
          AND is_deleted = false
      ),
      0
    ),
    review_count = (
      SELECT COUNT(*)
      FROM reviews
      WHERE merchant_id = v_merchant_id
        AND is_deleted = false
    )
  WHERE id = v_merchant_id;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- INSERT 触发器
DO $$ BEGIN
  CREATE TRIGGER trg_update_merchant_rating_insert
    AFTER INSERT ON reviews
    FOR EACH ROW EXECUTE FUNCTION update_merchant_rating();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- UPDATE 触发器（仅监听评分和软删除字段变化，减少无关开销）
DO $$ BEGIN
  CREATE TRIGGER trg_update_merchant_rating_update
    AFTER UPDATE OF rating_overall, rating, is_deleted ON reviews
    FOR EACH ROW EXECUTE FUNCTION update_merchant_rating();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 注意：不创建 DELETE 触发器，因为我们使用软删除（is_deleted = true）

-- ============================================================
-- Step 5: 更新 RLS 策略（DO $$ 块保证幂等）
-- ============================================================

-- 用户更新自己的评价（兼容旧 user_id 和新 reviewer_user_id）
DO $$ BEGIN
  CREATE POLICY "reviews_update_own" ON reviews
    FOR UPDATE USING (
      reviewer_user_id = auth.uid()
      OR user_id = auth.uid()
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 商家回复策略（通过 merchant_staff 表验证权限）
DO $$ BEGIN
  CREATE POLICY "reviews_merchant_reply_v2" ON reviews
    FOR UPDATE USING (
      EXISTS (
        SELECT 1
        FROM merchant_staff ms
        WHERE ms.user_id = auth.uid()
          AND ms.merchant_id = reviews.merchant_id
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
