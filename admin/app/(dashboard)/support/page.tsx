// 客服聊天管理页面（Admin 端）
// 布局：左侧会话列表 + 右侧聊天窗口

import { getServiceRoleClient } from '@/lib/supabase/service'
import SupportPanel from './support-panel'

interface Conversation {
  id: string
  merchant_id: string
  status: string
  created_at: string
  updated_at: string
  merchant_name: string
  last_message: string | null
  last_sender: string | null
  has_unread: boolean
}

interface Message {
  id: string
  conversation_id: string
  sender_role: string
  content: string
  created_at: string
}

export const dynamic = 'force-dynamic'

export default async function SupportPage() {
  const supabase = getServiceRoleClient()

  // 查询所有会话（含商家名 + 最后一条消息预览）
  const { data: conversations } = await supabase
    .from('support_conversations')
    .select(`
      id,
      merchant_id,
      status,
      created_at,
      updated_at,
      merchants!inner(name)
    `)
    .order('updated_at', { ascending: false })

  // 查询每个会话的最后一条消息
  const conversationIds = (conversations ?? []).map((c) => c.id)
  let lastMessages: Record<string, { content: string; sender_role: string }> = {}
  if (conversationIds.length > 0) {
    const { data: msgs } = await supabase
      .from('support_messages')
      .select('conversation_id, content, sender_role, created_at')
      .in('conversation_id', conversationIds)
      .order('created_at', { ascending: false })

    // 每个会话取最新一条
    if (msgs) {
      for (const m of msgs) {
        if (!lastMessages[m.conversation_id]) {
          lastMessages[m.conversation_id] = { content: m.content, sender_role: m.sender_role }
        }
      }
    }
  }

  const formattedConversations: Conversation[] = (conversations ?? []).map((c) => {
    const last = lastMessages[c.id]
    return {
      id: c.id,
      merchant_id: c.merchant_id,
      status: c.status,
      created_at: c.created_at,
      updated_at: c.updated_at,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      merchant_name: (c.merchants as any)?.name ?? 'Unknown',
      last_message: last?.content ?? null,
      last_sender: last?.sender_role ?? null,
      // 最后一条消息来自商家 = 有未读（admin 尚未回复）
      has_unread: last?.sender_role === 'merchant',
    }
  })

  return (
    <div className="flex h-[calc(100vh-4rem)] overflow-hidden">
      <SupportPanel conversations={formattedConversations} />
    </div>
  )
}
