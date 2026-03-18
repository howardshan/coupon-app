'use client'

// 客服面板：左侧会话列表 + 右侧聊天窗口（含 Supabase Realtime 实时订阅）

import { useState, useEffect, useRef, useTransition } from 'react'
import { createClient } from '@/lib/supabase/client'
import { sendSupportReply, closeSupportConversation, reopenSupportConversation } from '@/app/actions/admin'
import { toast } from 'sonner'

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

interface Props {
  conversations: Conversation[]
}

function formatTime(iso: string): string {
  const d = new Date(iso)
  const now = new Date()
  const diffDays = Math.floor((now.getTime() - d.getTime()) / 86400000)
  if (diffDays === 0) {
    return d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })
  } else if (diffDays === 1) {
    return 'Yesterday'
  } else if (diffDays < 7) {
    return d.toLocaleDateString('en-US', { weekday: 'short' })
  }
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

function formatDate(iso: string): string {
  const d = new Date(iso)
  const now = new Date()
  const diffDays = Math.floor((now.getTime() - d.getTime()) / 86400000)
  if (diffDays === 0) return 'Today'
  if (diffDays === 1) return 'Yesterday'
  return d.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })
}

export default function SupportPanel({ conversations: initialConversations }: Props) {
  const [conversations, setConversations] = useState<Conversation[]>(initialConversations)
  const [selectedId, setSelectedId] = useState<string | null>(
    initialConversations[0]?.id ?? null
  )
  const [messages, setMessages] = useState<Message[]>([])
  const [input, setInput] = useState('')
  const [loadingMessages, setLoadingMessages] = useState(false)
  const [isPending, startTransition] = useTransition()
  const scrollRef = useRef<HTMLDivElement>(null)
  const supabase = createClient()

  const selectedConv = conversations.find((c) => c.id === selectedId) ?? null

  // 加载选中会话的消息
  useEffect(() => {
    if (!selectedId) return
    setLoadingMessages(true)
    supabase
      .from('support_messages')
      .select('*')
      .eq('conversation_id', selectedId)
      .order('created_at', { ascending: true })
      .then(({ data }) => {
        setMessages((data as Message[]) ?? [])
        setLoadingMessages(false)
      })
  }, [selectedId])

  // 滚动到底部
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight
    }
  }, [messages])

  // Realtime 订阅新消息
  useEffect(() => {
    const channel = supabase
      .channel('admin_support_messages')
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'support_messages' },
        (payload) => {
          const msg = payload.new as Message
          // 更新当前选中会话的消息列表
          if (msg.conversation_id === selectedId) {
            setMessages((prev) => {
              // 防止重复（乐观更新已添加过）
              if (prev.some((m) => m.id === msg.id)) return prev
              return [...prev, msg]
            })
          }
          // 更新会话列表中的最新消息预览 + 未读标记
          setConversations((prev) =>
            prev.map((c) =>
              c.id === msg.conversation_id
                ? {
                    ...c,
                    last_message: msg.content,
                    last_sender: msg.sender_role,
                    has_unread: msg.sender_role === 'merchant' && msg.conversation_id !== selectedId,
                    updated_at: msg.created_at,
                  }
                : c
            ).sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime())
          )
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [selectedId])

  function handleSelectConversation(id: string) {
    setSelectedId(id)
    // 清除该会话的未读标记
    setConversations((prev) =>
      prev.map((c) => (c.id === id ? { ...c, has_unread: false } : c))
    )
  }

  async function handleSend() {
    if (!selectedId || !input.trim()) return
    const content = input.trim()
    setInput('')

    // 乐观更新
    const tempMsg: Message = {
      id: `temp_${Date.now()}`,
      conversation_id: selectedId,
      sender_role: 'admin',
      content,
      created_at: new Date().toISOString(),
    }
    setMessages((prev) => [...prev, tempMsg])

    startTransition(async () => {
      try {
        await sendSupportReply(selectedId, content)
      } catch (e) {
        toast.error((e as Error).message)
        // 回滚乐观更新
        setMessages((prev) => prev.filter((m) => m.id !== tempMsg.id))
      }
    })
  }

  function handleCloseConversation() {
    if (!selectedId) return
    startTransition(async () => {
      try {
        await closeSupportConversation(selectedId)
        setConversations((prev) =>
          prev.map((c) => (c.id === selectedId ? { ...c, status: 'closed' } : c))
        )
        toast.success('Conversation closed')
      } catch (e) {
        toast.error((e as Error).message)
      }
    })
  }

  function handleReopenConversation() {
    if (!selectedId) return
    startTransition(async () => {
      try {
        await reopenSupportConversation(selectedId)
        setConversations((prev) =>
          prev.map((c) => (c.id === selectedId ? { ...c, status: 'open' } : c))
        )
        toast.success('Conversation reopened')
      } catch (e) {
        toast.error((e as Error).message)
      }
    })
  }

  // 按日期分组消息，用于展示日期分隔线
  function renderMessages() {
    let lastDate = ''
    return messages.map((msg) => {
      const msgDate = formatDate(msg.created_at)
      const showDivider = msgDate !== lastDate
      lastDate = msgDate
      const isAdmin = msg.sender_role === 'admin'

      return (
        <div key={msg.id}>
          {showDivider && (
            <div className="flex items-center gap-3 my-4">
              <div className="flex-1 h-px bg-gray-200" />
              <span className="text-xs text-gray-400">{msgDate}</span>
              <div className="flex-1 h-px bg-gray-200" />
            </div>
          )}
          <div className={`flex items-end gap-2 mb-3 ${isAdmin ? 'flex-row-reverse' : 'flex-row'}`}>
            {/* 头像 */}
            <div
              className={`w-7 h-7 rounded-full flex-shrink-0 flex items-center justify-center text-xs font-bold ${
                isAdmin ? 'bg-blue-600 text-white' : 'bg-orange-100 text-orange-600'
              }`}
            >
              {isAdmin ? 'A' : 'M'}
            </div>
            {/* 气泡 */}
            <div
              className={`max-w-[65%] px-4 py-2.5 rounded-2xl text-sm leading-relaxed ${
                isAdmin
                  ? 'bg-blue-600 text-white rounded-br-sm'
                  : 'bg-white border border-gray-200 text-gray-800 rounded-bl-sm'
              }`}
            >
              {!isAdmin && (
                <p className="text-xs font-semibold text-orange-500 mb-1">
                  {selectedConv?.merchant_name ?? 'Merchant'}
                </p>
              )}
              <p>{msg.content}</p>
              <p
                className={`text-xs mt-1 ${isAdmin ? 'text-blue-200' : 'text-gray-400'}`}
              >
                {new Date(msg.created_at).toLocaleTimeString('en-US', {
                  hour: '2-digit',
                  minute: '2-digit',
                })}
              </p>
            </div>
          </div>
        </div>
      )
    })
  }

  return (
    <div className="flex w-full h-full">
      {/* 左侧会话列表 */}
      <div className="w-80 flex-shrink-0 border-r border-gray-200 bg-white flex flex-col">
        <div className="px-4 py-4 border-b border-gray-200">
          <h2 className="text-base font-semibold text-gray-900">Support Conversations</h2>
          <p className="text-xs text-gray-500 mt-0.5">{conversations.length} conversation{conversations.length !== 1 ? 's' : ''}</p>
        </div>

        <div className="flex-1 overflow-y-auto">
          {conversations.length === 0 ? (
            <div className="px-4 py-12 text-center text-gray-400 text-sm">
              No conversations yet
            </div>
          ) : (
            conversations.map((conv) => (
              <button
                key={conv.id}
                onClick={() => handleSelectConversation(conv.id)}
                className={`w-full text-left px-4 py-3.5 border-b border-gray-100 hover:bg-gray-50 transition-colors ${
                  conv.id === selectedId ? 'bg-blue-50 border-l-2 border-l-blue-600' : ''
                }`}
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="flex items-center gap-2 min-w-0">
                    {conv.has_unread && (
                      <span className="w-2 h-2 rounded-full bg-orange-500 flex-shrink-0 mt-0.5" />
                    )}
                    <p className={`text-sm font-medium truncate ${conv.has_unread ? 'text-gray-900' : 'text-gray-700'}`}>
                      {conv.merchant_name}
                    </p>
                  </div>
                  <div className="flex flex-col items-end gap-1 flex-shrink-0">
                    <span className="text-xs text-gray-400">{formatTime(conv.updated_at)}</span>
                    {conv.status === 'closed' && (
                      <span className="text-xs bg-gray-100 text-gray-500 px-1.5 py-0.5 rounded">closed</span>
                    )}
                  </div>
                </div>
                {conv.last_message && (
                  <p className="text-xs text-gray-500 mt-1 truncate pl-4">
                    {conv.last_sender === 'admin' ? 'You: ' : ''}{conv.last_message}
                  </p>
                )}
              </button>
            ))
          )}
        </div>
      </div>

      {/* 右侧聊天窗口 */}
      <div className="flex-1 flex flex-col bg-gray-50 min-w-0">
        {selectedConv ? (
          <>
            {/* 顶部栏 */}
            <div className="flex items-center justify-between px-6 py-4 bg-white border-b border-gray-200">
              <div>
                <h3 className="text-base font-semibold text-gray-900">{selectedConv.merchant_name}</h3>
                <p className="text-xs text-gray-500 capitalize">Status: {selectedConv.status}</p>
              </div>
              <div className="flex items-center gap-2">
                {selectedConv.status === 'open' ? (
                  <button
                    onClick={handleCloseConversation}
                    disabled={isPending}
                    className="px-3 py-1.5 text-xs font-medium rounded-lg border border-gray-300 text-gray-600 hover:bg-gray-100 disabled:opacity-50 transition-colors"
                  >
                    Close Conversation
                  </button>
                ) : (
                  <button
                    onClick={handleReopenConversation}
                    disabled={isPending}
                    className="px-3 py-1.5 text-xs font-medium rounded-lg border border-blue-300 text-blue-600 hover:bg-blue-50 disabled:opacity-50 transition-colors"
                  >
                    Reopen
                  </button>
                )}
              </div>
            </div>

            {/* 消息列表 */}
            <div ref={scrollRef} className="flex-1 overflow-y-auto px-6 py-4">
              {loadingMessages ? (
                <div className="flex items-center justify-center h-full text-gray-400 text-sm">
                  Loading messages…
                </div>
              ) : messages.length === 0 ? (
                <div className="flex flex-col items-center justify-center h-full text-center">
                  <div className="w-16 h-16 rounded-full bg-blue-100 flex items-center justify-center mb-3 text-2xl">
                    💬
                  </div>
                  <p className="text-sm font-medium text-gray-600">No messages yet</p>
                  <p className="text-xs text-gray-400 mt-1">
                    The merchant hasn&apos;t sent a message yet
                  </p>
                </div>
              ) : (
                renderMessages()
              )}
            </div>

            {/* 输入框 */}
            <div className="px-6 py-4 bg-white border-t border-gray-200">
              {selectedConv.status === 'closed' ? (
                <p className="text-center text-sm text-gray-400 py-2">
                  This conversation is closed. Reopen it to send a message.
                </p>
              ) : (
                <div className="flex items-end gap-3">
                  <textarea
                    value={input}
                    onChange={(e) => setInput(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter' && !e.shiftKey) {
                        e.preventDefault()
                        handleSend()
                      }
                    }}
                    placeholder="Type a reply… (Enter to send, Shift+Enter for new line)"
                    rows={2}
                    className="flex-1 resize-none px-4 py-2.5 text-sm border border-gray-300 rounded-xl focus:outline-none focus:ring-2 focus:ring-blue-500 placeholder:text-gray-400"
                  />
                  <button
                    onClick={handleSend}
                    disabled={isPending || !input.trim()}
                    className="px-5 py-2.5 text-sm font-semibold bg-blue-600 text-white rounded-xl hover:bg-blue-700 disabled:opacity-50 transition-colors"
                  >
                    Send
                  </button>
                </div>
              )}
            </div>
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center text-gray-400">
            <div className="text-center">
              <div className="text-5xl mb-4">💬</div>
              <p className="text-sm">Select a conversation to start replying</p>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
