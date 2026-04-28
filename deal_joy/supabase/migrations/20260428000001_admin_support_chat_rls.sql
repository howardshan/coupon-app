-- Admin 用户可读写用户客服会话消息
-- 用途：Admin 面板的 User Support 页面需要读取用户的客服消息并发送回复

-- Admin 可读 support 类型会话的所有消息（用于 Realtime 订阅）
CREATE POLICY "admin_read_support_messages"
ON messages FOR SELECT
USING (
  (SELECT role FROM users WHERE id = auth.uid()) = 'admin'
  AND (SELECT type FROM conversations WHERE id = messages.conversation_id) = 'support'
);

-- Admin 可向 support 类型会话写入消息（用于人工回复）
CREATE POLICY "admin_insert_support_messages"
ON messages FOR INSERT
WITH CHECK (
  (SELECT role FROM users WHERE id = auth.uid()) = 'admin'
  AND (SELECT type FROM conversations WHERE id = messages.conversation_id) = 'support'
);

-- Admin 可读所有 support 类型会话（用于会话列表展示）
CREATE POLICY "admin_read_support_conversations"
ON conversations FOR SELECT
USING (
  (SELECT role FROM users WHERE id = auth.uid()) = 'admin'
  AND type = 'support'
);

-- Admin 可更新 support 类型会话的 support_status（用于标记已解决）
CREATE POLICY "admin_update_support_conversations"
ON conversations FOR UPDATE
USING (
  (SELECT role FROM users WHERE id = auth.uid()) = 'admin'
  AND type = 'support'
);

-- Admin 可读 support 类型会话的成员信息（用于获取用户姓名、头像）
CREATE POLICY "admin_read_support_conversation_members"
ON conversation_members FOR SELECT
USING (
  (SELECT role FROM users WHERE id = auth.uid()) = 'admin'
  AND (SELECT type FROM conversations WHERE id = conversation_members.conversation_id) = 'support'
);
