-- 客服回拨请求表
CREATE TABLE IF NOT EXISTS support_callbacks (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  phone TEXT NOT NULL,
  preferred_time_slot TEXT NOT NULL CHECK (preferred_time_slot IN ('morning', 'afternoon', 'evening')),
  description TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE support_callbacks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "support_callbacks_select_own"
  ON support_callbacks FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "support_callbacks_insert_own"
  ON support_callbacks FOR INSERT
  WITH CHECK (auth.uid() = user_id);
