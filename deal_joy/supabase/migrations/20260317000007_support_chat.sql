-- ============================================================
-- 客服聊天系统：会话表 + 消息表
-- 每个商家唯一一个会话，双端 Realtime 实时刷新
-- ============================================================

-- 1. 会话表（每个商家唯一一条）
CREATE TABLE IF NOT EXISTS public.support_conversations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  status      TEXT NOT NULL DEFAULT 'open'
              CONSTRAINT support_conversations_status_check
              CHECK (status IN ('open', 'closed')),
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now(),
  -- 唯一约束：每个商家只能有一个会话，防止并发竞态创建重复记录
  CONSTRAINT support_conversations_merchant_id_key UNIQUE (merchant_id)
);

-- 2. 消息表
CREATE TABLE IF NOT EXISTS public.support_messages (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.support_conversations(id) ON DELETE CASCADE,
  sender_role     TEXT NOT NULL
                  CONSTRAINT support_messages_sender_role_check
                  CHECK (sender_role IN ('merchant', 'admin')),
  content         TEXT NOT NULL,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- 3. 触发器：消息 INSERT 后自动更新会话 updated_at
CREATE OR REPLACE FUNCTION update_support_conversation_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.support_conversations
  SET updated_at = now()
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_support_message_inserted ON public.support_messages;
CREATE TRIGGER trg_support_message_inserted
  AFTER INSERT ON public.support_messages
  FOR EACH ROW EXECUTE FUNCTION update_support_conversation_updated_at();

-- 4. RLS
ALTER TABLE public.support_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;

-- 商家只能读写自己的会话
CREATE POLICY "merchant_own_conversations" ON public.support_conversations
  FOR ALL TO authenticated
  USING (merchant_id IN (
    SELECT id FROM public.merchants WHERE user_id = auth.uid()
  ));

-- 商家只能读写自己会话的消息
CREATE POLICY "merchant_own_messages" ON public.support_messages
  FOR ALL TO authenticated
  USING (conversation_id IN (
    SELECT sc.id FROM public.support_conversations sc
    JOIN public.merchants m ON m.id = sc.merchant_id
    WHERE m.user_id = auth.uid()
  ));

-- Admin 可读写所有会话
CREATE POLICY "admin_all_conversations" ON public.support_conversations
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));

-- Admin 可读写所有消息
CREATE POLICY "admin_all_messages" ON public.support_messages
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));

-- 5. 开启 Realtime（新消息实时推送）
ALTER PUBLICATION supabase_realtime ADD TABLE public.support_messages;
