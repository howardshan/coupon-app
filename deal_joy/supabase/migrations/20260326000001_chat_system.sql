-- ============================================================
-- Chat 系统 Migration
-- 包含：好友系统、会话、消息、通知中心、用户推送
-- ============================================================

-- ============================================================
-- Step 0: 确保 update_updated_at_column 触发器函数存在
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Step 1: users 表补充字段（跳过已存在的 username, avatar_url）
-- ============================================================
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS push_token               text,
  ADD COLUMN IF NOT EXISTS show_activity_to_friends  boolean NOT NULL DEFAULT true;

-- ============================================================
-- Step 2: friend_requests 表
-- ============================================================
CREATE TABLE IF NOT EXISTS friend_requests (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  receiver_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status       text NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE(sender_id, receiver_id)
);

CREATE INDEX IF NOT EXISTS idx_friend_requests_receiver
  ON friend_requests(receiver_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_friend_requests_sender
  ON friend_requests(sender_id);

ALTER TABLE friend_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users_view_own_friend_requests" ON friend_requests
  FOR SELECT USING (sender_id = auth.uid() OR receiver_id = auth.uid());
CREATE POLICY "users_insert_friend_requests" ON friend_requests
  FOR INSERT WITH CHECK (sender_id = auth.uid());
CREATE POLICY "users_update_own_friend_requests" ON friend_requests
  FOR UPDATE USING (sender_id = auth.uid() OR receiver_id = auth.uid());

CREATE TRIGGER set_friend_requests_updated_at
  BEFORE UPDATE ON friend_requests
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- Step 3: friendships 表
-- ============================================================
CREATE TABLE IF NOT EXISTS friendships (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  friend_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, friend_id)
);

CREATE INDEX IF NOT EXISTS idx_friendships_user_id   ON friendships(user_id);
CREATE INDEX IF NOT EXISTS idx_friendships_friend_id ON friendships(friend_id);

ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users_view_own_friendships" ON friendships
  FOR SELECT USING (user_id = auth.uid());

-- ============================================================
-- Step 4: conversations 表
-- ============================================================
CREATE TABLE IF NOT EXISTS conversations (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type           text NOT NULL CHECK (type IN ('direct', 'group', 'support')),
  name           text,
  avatar_url     text,
  created_by     uuid REFERENCES users(id),
  support_status text CHECK (support_status IN ('ai', 'human', 'resolved')),
  assigned_to    uuid REFERENCES users(id),
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_conversations_updated_at
  ON conversations(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversations_type
  ON conversations(type);

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members_view_conversations" ON conversations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM conversation_members cm
      WHERE cm.conversation_id = conversations.id
        AND cm.user_id = auth.uid()
        AND cm.left_at IS NULL
    )
  );
CREATE POLICY "members_update_conversations" ON conversations
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM conversation_members cm
      WHERE cm.conversation_id = conversations.id
        AND cm.user_id = auth.uid()
        AND cm.left_at IS NULL
    )
  );

-- ============================================================
-- Step 5: conversation_members 表
-- ============================================================
CREATE TABLE IF NOT EXISTS conversation_members (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role            text NOT NULL DEFAULT 'member'
                    CHECK (role IN ('owner', 'admin', 'member')),
  last_read_at    timestamptz,
  joined_at       timestamptz NOT NULL DEFAULT now(),
  left_at         timestamptz,
  UNIQUE(conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_conv_members_user_id
  ON conversation_members(user_id);
CREATE INDEX IF NOT EXISTS idx_conv_members_conv_id
  ON conversation_members(conversation_id);

ALTER TABLE conversation_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members_view_conv_members" ON conversation_members
  FOR SELECT USING (
    conversation_id IN (
      SELECT conversation_id FROM conversation_members
      WHERE user_id = auth.uid() AND left_at IS NULL
    )
  );
CREATE POLICY "members_update_own_read" ON conversation_members
  FOR UPDATE USING (user_id = auth.uid());

-- ============================================================
-- Step 6: messages 表
-- ============================================================
CREATE TABLE IF NOT EXISTS messages (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id       uuid REFERENCES users(id),
  type            text NOT NULL DEFAULT 'text'
                    CHECK (type IN ('text', 'image', 'coupon', 'emoji', 'system')),
  content         text,
  image_url       text,
  coupon_payload  jsonb,
  is_deleted      boolean NOT NULL DEFAULT false,
  deleted_at      timestamptz,
  is_ai_message   boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_conv_id
  ON messages(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id
  ON messages(sender_id);

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members_view_messages" ON messages
  FOR SELECT USING (
    conversation_id IN (
      SELECT conversation_id FROM conversation_members
      WHERE user_id = auth.uid() AND left_at IS NULL
    )
  );
CREATE POLICY "members_insert_messages" ON messages
  FOR INSERT WITH CHECK (
    sender_id = auth.uid() AND
    conversation_id IN (
      SELECT conversation_id FROM conversation_members
      WHERE user_id = auth.uid() AND left_at IS NULL
    )
  );

-- 消息插入后自动更新 conversation.updated_at
CREATE OR REPLACE FUNCTION update_conversation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE conversations SET updated_at = now() WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_conversation_on_message
  AFTER INSERT ON messages
  FOR EACH ROW EXECUTE FUNCTION update_conversation_timestamp();

-- ============================================================
-- Step 7: 好友申请接受后自动创建好友关系 + 1v1 会话
-- ============================================================
CREATE OR REPLACE FUNCTION handle_friend_request_accepted()
RETURNS TRIGGER AS $$
DECLARE
  conv_id uuid;
BEGIN
  IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
    -- 写入双向好友关系
    INSERT INTO friendships (user_id, friend_id)
    VALUES (NEW.sender_id, NEW.receiver_id),
           (NEW.receiver_id, NEW.sender_id)
    ON CONFLICT DO NOTHING;

    -- 检查是否已有 1v1 会话（避免重复创建）
    SELECT cm1.conversation_id INTO conv_id
    FROM conversation_members cm1
    JOIN conversation_members cm2
      ON cm1.conversation_id = cm2.conversation_id
    JOIN conversations c
      ON c.id = cm1.conversation_id
    WHERE cm1.user_id = NEW.sender_id
      AND cm2.user_id = NEW.receiver_id
      AND c.type = 'direct'
    LIMIT 1;

    -- 不存在则创建
    IF conv_id IS NULL THEN
      INSERT INTO conversations (type, created_by)
      VALUES ('direct', NEW.receiver_id)
      RETURNING id INTO conv_id;

      INSERT INTO conversation_members (conversation_id, user_id, role)
      VALUES (conv_id, NEW.sender_id, 'member'),
             (conv_id, NEW.receiver_id, 'member');
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_friend_request_accepted
  AFTER UPDATE ON friend_requests
  FOR EACH ROW EXECUTE FUNCTION handle_friend_request_accepted();

-- ============================================================
-- Step 8: notifications 表（用户端）
-- ============================================================
CREATE TABLE IF NOT EXISTS notifications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type        text NOT NULL CHECK (type IN (
                'transaction',
                'announcement',
                'friend_activity',
                'friend_request',
                'review_reply',
                'chat_message'
              )),
  title       text NOT NULL,
  body        text NOT NULL,
  data        jsonb,
  is_read     boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id
  ON notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread
  ON notifications(user_id) WHERE is_read = false;

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users_view_own_notifications" ON notifications
  FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "users_update_own_notifications" ON notifications
  FOR UPDATE USING (user_id = auth.uid());

-- ============================================================
-- Step 9: user_fcm_tokens 表（用户端推送）
-- ============================================================
CREATE TABLE IF NOT EXISTS user_fcm_tokens (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  fcm_token   text NOT NULL,
  device_type text NOT NULL CHECK (device_type IN ('ios', 'android')),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, fcm_token)
);

CREATE INDEX IF NOT EXISTS idx_user_fcm_tokens_user_id
  ON user_fcm_tokens(user_id);

ALTER TABLE user_fcm_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users_manage_own_fcm_tokens" ON user_fcm_tokens
  FOR ALL USING (user_id = auth.uid());

-- ============================================================
-- Step 10: announcements 表（系统公告）
-- ============================================================
CREATE TABLE IF NOT EXISTS announcements (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title        text NOT NULL,
  body         text NOT NULL,
  data         jsonb,
  published_at timestamptz,
  created_by   uuid REFERENCES users(id),
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- Step 11: 启用 Realtime（messages + notifications + friend_requests）
-- ============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE friend_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE conversations;

-- ============================================================
-- Step 12: Storage bucket（chat-media，公开读，登录用户可上传）
-- 需要在 Supabase Dashboard 或 CLI 手动创建：
--   supabase storage create chat-media --public
-- 以下 RLS 在 bucket 创建后生效
-- ============================================================
-- INSERT policy: 登录用户可上传到自己的目录
-- SELECT policy: 公开可读
-- DELETE policy: 只能删除自己上传的文件
