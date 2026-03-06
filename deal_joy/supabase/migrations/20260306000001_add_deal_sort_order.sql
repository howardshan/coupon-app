-- 给 deals 表添加 sort_order 字段，用于首页券排序展示
ALTER TABLE deals ADD COLUMN IF NOT EXISTS sort_order INT DEFAULT NULL;

-- sort_order 有值的 active deal 会在首页按升序展示
COMMENT ON COLUMN deals.sort_order IS '首页展示排序，NULL 表示不在首页展示，数字越小越靠前';
