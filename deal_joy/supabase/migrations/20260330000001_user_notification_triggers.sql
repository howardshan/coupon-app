-- =============================================================
-- 用户端通知触发器
-- 在关键事件发生时自动向 notifications 表写入通知记录
-- 推送通知通过 Realtime + FCM 双通道到达用户
-- =============================================================

-- ---- 1. 好友申请 → 通知接收方 ----
CREATE OR REPLACE FUNCTION notify_user_friend_request()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO notifications (user_id, type, title, body, data)
  VALUES (
    NEW.receiver_id,
    'friend_request',
    'New Friend Request',
    COALESCE(
      (SELECT username FROM users WHERE id = NEW.sender_id),
      'Someone'
    ) || ' wants to be your friend',
    jsonb_build_object('sender_id', NEW.sender_id::text)
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- 通知失败不影响好友申请主流程
  RAISE WARNING '[notify_user_friend_request] %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_friend_request ON friend_requests;
CREATE TRIGGER trg_notify_friend_request
  AFTER INSERT ON friend_requests
  FOR EACH ROW
  EXECUTE FUNCTION notify_user_friend_request();

-- ---- 2. 新聊天消息 → 通知对方（仅直接消息，群组暂不支持） ----
CREATE OR REPLACE FUNCTION notify_user_new_message()
RETURNS TRIGGER AS $$
DECLARE
  v_other_user_id uuid;
  v_sender_name text;
  v_conv_type text;
BEGIN
  -- 获取会话类型
  SELECT type INTO v_conv_type
  FROM conversations WHERE id = NEW.conversation_id;

  -- 仅对 direct（一对一）会话触发通知
  IF v_conv_type != 'direct' THEN
    RETURN NEW;
  END IF;

  -- 找到对方用户 ID
  SELECT user_id INTO v_other_user_id
  FROM conversation_members
  WHERE conversation_id = NEW.conversation_id
    AND user_id != NEW.sender_id
  LIMIT 1;

  IF v_other_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- 获取发送者名称
  SELECT COALESCE(username, 'Someone') INTO v_sender_name
  FROM users WHERE id = NEW.sender_id;

  INSERT INTO notifications (user_id, type, title, body, data)
  VALUES (
    v_other_user_id,
    'chat_message',
    'New Message',
    v_sender_name || ': ' || LEFT(COALESCE(NEW.content, 'Sent a message'), 100),
    jsonb_build_object(
      'conversation_id', NEW.conversation_id::text,
      'sender_id', NEW.sender_id::text
    )
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '[notify_user_new_message] %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_new_message ON messages;
CREATE TRIGGER trg_notify_new_message
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_user_new_message();

-- ---- 3. 平台公告发布 → 通知所有用户 ----
CREATE OR REPLACE FUNCTION notify_announcement_published()
RETURNS TRIGGER AS $$
BEGIN
  -- 仅在 published_at 从 NULL 变为非 NULL 时触发（发布动作）
  IF OLD.published_at IS NOT NULL OR NEW.published_at IS NULL THEN
    RETURN NEW;
  END IF;

  -- 向所有活跃用户插入通知
  INSERT INTO notifications (user_id, type, title, body, data)
  SELECT
    u.id,
    'announcement',
    NEW.title,
    LEFT(NEW.body, 200),
    jsonb_build_object('announcement_id', NEW.id::text)
  FROM users u
  WHERE u.id IS NOT NULL;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '[notify_announcement_published] %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_announcement ON announcements;
CREATE TRIGGER trg_notify_announcement
  AFTER UPDATE ON announcements
  FOR EACH ROW
  EXECUTE FUNCTION notify_announcement_published();

-- ---- 4. 订单创建 → 通知买家订单确认 ----
CREATE OR REPLACE FUNCTION notify_user_order_created()
RETURNS TRIGGER AS $$
DECLARE
  v_deal_title text;
BEGIN
  -- 获取订单关联的第一个 deal 标题
  SELECT d.title INTO v_deal_title
  FROM order_items oi
  JOIN deals d ON d.id = oi.deal_id
  WHERE oi.order_id = NEW.id
  LIMIT 1;

  INSERT INTO notifications (user_id, type, title, body, data)
  VALUES (
    NEW.user_id,
    'transaction',
    'Order Confirmed',
    'Your order for ' || COALESCE(v_deal_title, 'a deal') || ' has been confirmed!',
    jsonb_build_object('order_id', NEW.id::text)
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '[notify_user_order_created] %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_user_order ON orders;
CREATE TRIGGER trg_notify_user_order
  AFTER INSERT ON orders
  FOR EACH ROW
  EXECUTE FUNCTION notify_user_order_created();

-- ---- 5. 退款完成 → 通知用户 ----
CREATE OR REPLACE FUNCTION notify_user_refund_completed()
RETURNS TRIGGER AS $$
DECLARE
  v_user_id uuid;
  v_amount numeric;
BEGIN
  -- 仅在状态变为 refunded 时触发
  IF NEW.status != 'refunded' OR OLD.status = 'refunded' THEN
    RETURN NEW;
  END IF;

  -- 获取订单的用户 ID 和金额
  SELECT o.user_id, NEW.unit_price INTO v_user_id, v_amount
  FROM orders o
  WHERE o.id = NEW.order_id;

  IF v_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, data)
  VALUES (
    v_user_id,
    'transaction',
    'Refund Processed',
    'Your refund of $' || COALESCE(v_amount::text, '0') || ' has been processed.',
    jsonb_build_object('order_id', NEW.order_id::text)
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '[notify_user_refund_completed] %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_user_refund ON order_items;
CREATE TRIGGER trg_notify_user_refund
  AFTER UPDATE ON order_items
  FOR EACH ROW
  EXECUTE FUNCTION notify_user_refund_completed();
