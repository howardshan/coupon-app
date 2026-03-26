// =============================================================
// Edge Function: support-chat
// 用户端客服聊天 — AI 先回答（Claude API），解决不了转人工
// 路由：
//   POST /support-chat  — 发送消息并获取 AI 回复
//     body: { conversation_id, message }
//     返回: { ai_reply, handoff }
// 认证：Bearer JWT（用户）
// =============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function errorResponse(message: string, status = 400): Response {
  return jsonResponse({ error: message }, status);
}

// AI 客服系统提示词
const SUPPORT_SYSTEM_PROMPT = `You are a helpful customer support assistant for DealJoy, a local deals and coupon platform in the Dallas area.

You can help with:
- Order and coupon status questions
- Refund policy explanations ("buy anytime, refund anytime" — unconditional instant refund before use, auto-refund when expired)
- How to use coupons (show QR code to merchant for scanning, or provide 16-digit code)
- Deal expiry and validity questions
- Gift coupon questions (how to send/receive gift coupons)
- Account and profile issues
- How to find deals (search by category, location, or merchant)

If the user's issue requires:
- Actual refund processing
- Account data access or modification
- Dispute resolution
- Payment issues
- Any issue you cannot resolve with information alone

Respond with a helpful message AND include the exact phrase "I'll connect you with a human agent" somewhere in your response to trigger handoff.

Always be friendly, concise, and helpful. Reply in the same language the user writes in.
Current date: ${new Date().toLocaleDateString()}`;

serve(async (req: Request) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return errorResponse('Method not allowed', 405);
  }

  try {
    // 验证用户身份
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return errorResponse('Missing authorization header', 401);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const anthropicApiKey = Deno.env.get('ANTHROPIC_API_KEY');

    // 使用 service role 操作数据库
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // 获取用户 ID
    const userClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return errorResponse('Unauthorized', 401);
    }
    const userId = user.id;

    // 解析请求体
    const { conversation_id, message } = await req.json();
    if (!conversation_id || !message) {
      return errorResponse('conversation_id and message are required');
    }

    // 验证用户是该会话的成员
    const { data: member } = await supabase
      .from('conversation_members')
      .select('id')
      .eq('conversation_id', conversation_id)
      .eq('user_id', userId)
      .is('left_at', null)
      .single();

    if (!member) {
      return errorResponse('Not a member of this conversation', 403);
    }

    // 检查会话是否为 support 类型且状态为 ai
    const { data: conv } = await supabase
      .from('conversations')
      .select('type, support_status')
      .eq('id', conversation_id)
      .single();

    if (!conv || conv.type !== 'support') {
      return errorResponse('Not a support conversation');
    }

    // 如果已转人工或已解决，不再调用 AI
    if (conv.support_status === 'human' || conv.support_status === 'resolved') {
      // 只保存用户消息，不生成 AI 回复
      await supabase.from('messages').insert({
        conversation_id,
        sender_id: userId,
        type: 'text',
        content: message,
      });
      return jsonResponse({ ai_reply: null, handoff: false, status: conv.support_status });
    }

    // 保存用户消息
    await supabase.from('messages').insert({
      conversation_id,
      sender_id: userId,
      type: 'text',
      content: message,
    });

    // 如果没有 Anthropic API Key，直接转人工
    if (!anthropicApiKey) {
      const fallbackReply = "I'm connecting you with a human agent who can help you further. Please wait a moment.";
      await supabase.from('messages').insert({
        conversation_id,
        sender_id: null,
        type: 'text',
        content: fallbackReply,
        is_ai_message: true,
      });
      await supabase.from('conversations').update({
        support_status: 'human',
      }).eq('id', conversation_id);

      return jsonResponse({ ai_reply: fallbackReply, handoff: true });
    }

    // 获取历史消息（最近 20 条，作为上下文）
    const { data: history } = await supabase
      .from('messages')
      .select('sender_id, content, is_ai_message, type, created_at')
      .eq('conversation_id', conversation_id)
      .eq('type', 'text')
      .order('created_at', { ascending: false })
      .limit(20);

    // 构建 Claude API 消息历史
    const messages = (history || [])
      .reverse()
      .filter((m: any) => m.content)
      .map((m: any) => ({
        role: m.sender_id === null || m.is_ai_message ? 'assistant' : 'user',
        content: m.content,
      }));

    // 调用 Claude API
    const claudeResponse = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': anthropicApiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1000,
        system: SUPPORT_SYSTEM_PROMPT,
        messages,
      }),
    });

    if (!claudeResponse.ok) {
      const err = await claudeResponse.text();
      console.error('Claude API error:', err);
      // AI 失败时自动转人工
      const fallbackReply = "I apologize, but I'm having trouble processing your request. I'll connect you with a human agent who can help you further.";
      await supabase.from('messages').insert({
        conversation_id,
        sender_id: null,
        type: 'text',
        content: fallbackReply,
        is_ai_message: true,
      });
      await supabase.from('conversations').update({
        support_status: 'human',
      }).eq('id', conversation_id);

      return jsonResponse({ ai_reply: fallbackReply, handoff: true });
    }

    const claudeData = await claudeResponse.json();
    const aiReply = claudeData.content?.[0]?.text || 'I apologize, I could not generate a response.';

    // 检测是否需要转人工
    const needHandoff = aiReply.toLowerCase().includes("connect you with a human agent");

    // 保存 AI 回复
    await supabase.from('messages').insert({
      conversation_id,
      sender_id: null,
      type: 'text',
      content: aiReply,
      is_ai_message: true,
    });

    // 转人工
    if (needHandoff) {
      await supabase.from('conversations').update({
        support_status: 'human',
      }).eq('id', conversation_id);
    }

    return jsonResponse({ ai_reply: aiReply, handoff: needHandoff });
  } catch (err) {
    console.error('support-chat error:', err);
    return errorResponse(`Internal server error: ${err.message}`, 500);
  }
});
