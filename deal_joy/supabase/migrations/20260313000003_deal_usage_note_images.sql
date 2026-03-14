-- 给 deals 表添加 usage_note_images 字段，用于存储购买须知相关的图片/视频 URL
ALTER TABLE deals ADD COLUMN IF NOT EXISTS usage_note_images jsonb DEFAULT '[]'::jsonb;
