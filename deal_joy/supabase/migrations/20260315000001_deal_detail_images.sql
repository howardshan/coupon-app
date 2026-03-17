-- =============================================================
-- Migration: deals 表新增 detail_images 字段
-- detail_images 用于存储商品详情页的多张图片 URL
-- =============================================================

ALTER TABLE deals
  ADD COLUMN IF NOT EXISTS detail_images text[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN deals.detail_images IS '商品详情图片 URL 列表，用于详情页轮播展示';
