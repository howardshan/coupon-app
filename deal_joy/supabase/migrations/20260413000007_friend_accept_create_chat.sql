-- 好友请求通过后自动创建 chat + 系统欢迎消息
-- 触发条件：friend_requests.status 从 非 accepted 变为 'accepted'
-- 行为：
--   1. 查找 sender 和 receiver 之间是否已有 direct conversation
--   2. 如果没有，创建一个新的 direct conversation + 两个 members
--   3. 插入一条 type='system' 的欢迎消息
--   4. 幂等：如果已经有 conversation，不重复创建；已发过 system 欢迎不重发

CREATE OR REPLACE FUNCTION public.tg_friend_request_create_chat()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_conversation_id uuid;
  v_sender_id uuid := NEW.sender_id;
  v_receiver_id uuid := NEW.receiver_id;
  v_welcome_text text := 'You are now connected. Say hi to start chatting!';
BEGIN
  -- 仅在 status 变为 accepted 时触发（UPDATE 场景）
  IF NEW.status <> 'accepted' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND COALESCE(OLD.status, '') = 'accepted' THEN
    RETURN NEW;  -- 幂等：已经 accepted 过的更新不重复处理
  END IF;

  -- 1. 查找已有的 direct conversation（两人都是成员且没离开）
  SELECT c.id
  INTO v_conversation_id
  FROM public.conversations c
  WHERE c.type = 'direct'
    AND EXISTS (
      SELECT 1 FROM public.conversation_members m
      WHERE m.conversation_id = c.id AND m.user_id = v_sender_id AND m.left_at IS NULL
    )
    AND EXISTS (
      SELECT 1 FROM public.conversation_members m
      WHERE m.conversation_id = c.id AND m.user_id = v_receiver_id AND m.left_at IS NULL
    )
    AND (
      SELECT COUNT(*) FROM public.conversation_members m
      WHERE m.conversation_id = c.id AND m.left_at IS NULL
    ) = 2
  LIMIT 1;

  -- 2. 没有则创建新的 direct conversation
  IF v_conversation_id IS NULL THEN
    INSERT INTO public.conversations (type, created_by, created_at, updated_at)
    VALUES ('direct', v_sender_id, now(), now())
    RETURNING id INTO v_conversation_id;

    INSERT INTO public.conversation_members (conversation_id, user_id, joined_at)
    VALUES
      (v_conversation_id, v_sender_id,  now()),
      (v_conversation_id, v_receiver_id, now());
  END IF;

  -- 3. 发送欢迎系统消息（避免重复发送）
  IF NOT EXISTS (
    SELECT 1 FROM public.messages
    WHERE conversation_id = v_conversation_id
      AND type = 'system'
      AND content = v_welcome_text
  ) THEN
    INSERT INTO public.messages (conversation_id, sender_id, type, content, created_at)
    VALUES (v_conversation_id, NULL, 'system', v_welcome_text, now());

    -- 顺便把 conversations.updated_at 刷新一下，让列表按最近活跃排序
    UPDATE public.conversations
    SET updated_at = now()
    WHERE id = v_conversation_id;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- 非致命：不因创建 chat 失败阻止 friend_requests 更新
  RAISE WARNING '[tg_friend_request_create_chat] failed: %', SQLERRM;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS friend_request_create_chat ON public.friend_requests;

CREATE TRIGGER friend_request_create_chat
AFTER INSERT OR UPDATE OF status ON public.friend_requests
FOR EACH ROW
EXECUTE FUNCTION public.tg_friend_request_create_chat();

COMMENT ON FUNCTION public.tg_friend_request_create_chat() IS
  '好友请求通过（status=accepted）时自动创建 direct conversation 并插入 system 欢迎消息，幂等。';
